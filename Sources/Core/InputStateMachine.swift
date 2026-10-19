import Foundation

public enum InputCorrectionMode: Equatable {
    case automatic
    case hotkey
    case layoutSwitch
}

public struct InputPreferencesSnapshot: Equatable {
    public let isEnabled: Bool
    public let correctionMode: InputCorrectionMode

    public init(isEnabled: Bool, correctionMode: InputCorrectionMode) {
        self.isEnabled = isEnabled
        self.correctionMode = correctionMode
    }
}

public enum InputInvalidationReason: Equatable {
    case disabled
    case staleContext
    case disallowedApplication
    case secureFocus
    case unknownFocus
    case navigation
    case focusChanged
    case tapReset
    case queueOverflow
    case bufferOverflow
    case contextChanged
}

public enum InputStateCommand: Equatable {
    case append(String)
    case flush(word: String, boundary: String, sequence: UInt64, context: InputContextSnapshot)
    case deleteLast
    case invalidate(InputInvalidationReason)
    case requestManualCorrection(word: String?, sequence: UInt64, context: InputContextSnapshot)
    case requestRevert(word: String?, sequence: UInt64, context: InputContextSnapshot)
    case nativeUndo
    case untrackedWordHeld(length: Int)
}

/// A word typed back-to-back with its neighbours: `text` followed by `boundary` sits on screen
/// immediately before the next token (or the caret). A correction may have replaced `text`
/// on screen with its same-length conversion.
public struct RunToken: Equatable {
    public let id: UInt64
    public let text: String
    public let boundary: String
    /// False when the word was typed after deletes the buffer could not follow, so it may be
    /// only the tail of a longer on-screen word.
    public let isAnchored: Bool

    public init(id: UInt64, text: String, boundary: String, isAnchored: Bool) {
        self.id = id
        self.text = text
        self.boundary = boundary
        self.isAnchored = isAnchored
    }
}

public struct InputStateMachine {
    public private(set) var currentBuffer = ""
    public private(set) var isInvalidUntilBoundary = false
    public private(set) var context: InputContextSnapshot
    public private(set) var preferences: InputPreferencesSnapshot
    /// Words committed back-to-back since the caret last jumped, oldest first.
    public private(set) var run: [RunToken] = []

    private var untrackedDeleteCount = 0
    /// Characters typed after repeated untracked deletes. They are never judged on their own,
    /// but stay recorded so a later correction of the same run can still reach them.
    private var untrackedFragment: String?

    private static let maxRunLength = 16

    public init(context: InputContextSnapshot, preferences: InputPreferencesSnapshot) {
        self.context = context
        self.preferences = preferences
    }

    public mutating func updateContext(_ context: InputContextSnapshot) -> [InputStateCommand] {
        let changed = self.context != context
        self.context = context
        guard changed else { return [] }
        currentBuffer = ""
        run = []
        untrackedFragment = nil
        untrackedDeleteCount = 0
        isInvalidUntilBoundary = false
        return [.invalidate(.contextChanged)]
    }

    /// Marks the buffer invalid until the next boundary: used when an event was
    /// dropped (stale context), so on-screen text and the buffer may disagree.
    public mutating func invalidateUntilBoundary() {
        invalidate(untilBoundary: true)
    }

    /// Correction configuration changed: drop the run so no earlier word is judged under the new
    /// configuration. A word already in progress is skipped until its boundary, because only part
    /// of it would remain buffered; with nothing in progress the next word starts normally.
    public mutating func resetForConfigurationChange() {
        invalidate(untilBoundary: isInvalidUntilBoundary || !currentBuffer.isEmpty || untrackedFragment != nil)
    }

    public mutating func updatePreferences(_ preferences: InputPreferencesSnapshot) -> [InputStateCommand] {
        let previous = self.preferences
        self.preferences = preferences
        guard previous != preferences else { return [] }

        currentBuffer = ""
        run = []
        untrackedFragment = nil
        untrackedDeleteCount = 0
        isInvalidUntilBoundary = false

        if previous.isEnabled && !preferences.isEnabled {
            return [.invalidate(.disabled)]
        }
        return [.invalidate(.contextChanged)]
    }

    public mutating func consume(_ input: CapturedInput) -> [InputStateCommand] {
        guard input.sourceUserData != switchFixEventMarker else { return [] }

        guard input.context.epoch == context.epoch,
              input.context.frontmostPID == context.frontmostPID,
              input.context.layout == context.layout,
              input.context.inputSourceID == context.inputSourceID else {
            invalidate(untilBoundary: false)
            return [.invalidate(.staleContext)]
        }

        switch input.kind {
        case .tapReset:
            invalidate(untilBoundary: true)
            return [.invalidate(.tapReset)]
        case .queueOverflow:
            invalidate(untilBoundary: true)
            return [.invalidate(.queueOverflow)]
        case .navigation:
            // Once the caret moves, the buffer no longer identifies the text at
            // the caret. Ignore input until a boundary re-establishes a safe
            // word boundary.
            untrackedDeleteCount = 0
            invalidate(untilBoundary: true)
            return [.invalidate(.navigation)]
        case .focusMayChange:
            invalidate(untilBoundary: false)
            return [.invalidate(.focusChanged)]
        case .undo:
            invalidate(untilBoundary: true)
            return [.nativeUndo]
        case .hotkey:
            let word = currentBuffer.isEmpty ? nil : currentBuffer
            // The correction rewrites these characters outside the event stream,
            // so the buffer must drop them; keeping them desyncs the buffer from
            // the screen and makes the next flush delete already-corrected text.
            currentBuffer = ""
            run = []
            untrackedFragment = nil
            return [.requestManualCorrection(word: word, sequence: input.sequence, context: input.context)]
        case .revertHotkey:
            let word = currentBuffer.isEmpty ? nil : currentBuffer
            // Same desync hazard: whether the revert succeeds (original text is
            // restored) or falls back to a manual correction, the on-screen word
            // is rewritten without buffer-visible events.
            currentBuffer = ""
            run = []
            untrackedFragment = nil
            return [.requestRevert(word: word, sequence: input.sequence, context: input.context)]
        case .delete:
            guard canBuffer(input.context) else {
                untrackedDeleteCount = 0
                return invalidateForContext(input.context)
            }
            if isInvalidUntilBoundary {
                // Still contiguous with the caret: forget the last recorded character, if any.
                if untrackedFragment?.isEmpty == false {
                    untrackedFragment?.removeLast()
                }
                return [.invalidate(.navigation)]
            }
            if !currentBuffer.isEmpty {
                currentBuffer.removeLast()
                untrackedDeleteCount = 0
                return [.deleteLast]
            }
            if let last = run.popLast() {
                untrackedDeleteCount = 0
                let boundary = String(last.boundary.dropLast())
                if !boundary.isEmpty {
                    run.append(RunToken(id: last.id, text: last.text, boundary: boundary, isAnchored: last.isAnchored))
                } else if last.isAnchored {
                    currentBuffer = last.text
                } else {
                    untrackedFragment = last.text
                    isInvalidUntilBoundary = true
                }
                return [.deleteLast]
            }
            // One delete beyond the tracked buffer can still be the normal
            // "delete then type" flow. Repeated untracked deletes imply
            // that the caret has entered existing text, so the next word may
            // be a fragment and must not be judged on its own. ponytail: keep
            // this small two-delete ceiling until editors expose reliable
            // caret context.
            untrackedDeleteCount += 1
            let caretEnteredExistingText = untrackedDeleteCount >= 2
            invalidate(untilBoundary: caretEnteredExistingText)
            if caretEnteredExistingText {
                untrackedFragment = ""
            }
            return [.invalidate(.navigation)]
        case .character(let text):
            guard canBuffer(input.context) else {
                untrackedDeleteCount = 0
                return invalidateForContext(input.context)
            }
            guard !isInvalidUntilBoundary else {
                if let fragment = untrackedFragment {
                    untrackedFragment = fragment.count + text.count <= 64 ? fragment + text : nil
                }
                return []
            }
            untrackedDeleteCount = 0
            let nextCount = currentBuffer.count + text.count
            guard nextCount <= 64 else {
                invalidate(untilBoundary: true)
                return [.invalidate(.bufferOverflow)]
            }
            currentBuffer += text
            return [.append(text)]
        case .boundary(let boundary):
            let flushedWord = (!isInvalidUntilBoundary && !currentBuffer.isEmpty) ? currentBuffer : nil
            let heldFragment = isInvalidUntilBoundary ? untrackedFragment : nil
            currentBuffer = ""
            isInvalidUntilBoundary = false
            untrackedDeleteCount = 0
            untrackedFragment = nil
            guard canBuffer(input.context) else {
                return invalidateForContext(input.context)
            }
            if let flushedWord {
                commit(RunToken(id: input.sequence, text: flushedWord, boundary: boundary, isAnchored: true))
                switch preferences.correctionMode {
                case .automatic:
                    return [.flush(
                        word: flushedWord,
                        boundary: boundary,
                        sequence: input.sequence,
                        context: input.context
                    )]
                case .hotkey, .layoutSwitch:
                    return []
                }
            }
            // A boundary with no tracked word before it puts a character on screen
            // that no token accounts for, so earlier words are no longer adjacent.
            run = []
            if let heldFragment, !heldFragment.isEmpty, preferences.correctionMode == .automatic {
                commit(RunToken(id: input.sequence, text: heldFragment, boundary: boundary, isAnchored: false))
                return [.untrackedWordHeld(length: heldFragment.count)]
            }
            return []
        }
    }

    private func canBuffer(_ context: InputContextSnapshot) -> Bool {
        preferences.isEnabled && context.appAllowed && context.secureFocus == .notSecure
    }

    private mutating func invalidateForContext(_ context: InputContextSnapshot) -> [InputStateCommand] {
        invalidate(untilBoundary: false)
        if !preferences.isEnabled { return [.invalidate(.disabled)] }
        if !context.appAllowed { return [.invalidate(.disallowedApplication)] }
        if context.secureFocus == .secure { return [.invalidate(.secureFocus)] }
        return [.invalidate(.unknownFocus)]
    }

    private mutating func invalidate(untilBoundary: Bool) {
        currentBuffer = ""
        run = []
        untrackedFragment = nil
        isInvalidUntilBoundary = untilBoundary
    }

    private mutating func commit(_ token: RunToken) {
        guard !token.boundary.isEmpty else {
            run = []
            return
        }
        run.append(token)
        if run.count > InputStateMachine.maxRunLength {
            run.removeFirst(run.count - InputStateMachine.maxRunLength)
        }
    }
}

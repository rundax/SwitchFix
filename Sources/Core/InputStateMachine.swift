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
}

public struct InputStateMachine {
    public private(set) var currentBuffer = ""
    public private(set) var isInvalidUntilBoundary = false
    public private(set) var context: InputContextSnapshot
    public private(set) var preferences: InputPreferencesSnapshot

    private var committedWord: String?
    private var committedBoundary: String?

    public init(context: InputContextSnapshot, preferences: InputPreferencesSnapshot) {
        self.context = context
        self.preferences = preferences
    }

    public mutating func updateContext(_ context: InputContextSnapshot) -> [InputStateCommand] {
        let changed = self.context != context
        self.context = context
        guard changed else { return [] }
        currentBuffer = ""
        committedWord = nil
        committedBoundary = nil
        isInvalidUntilBoundary = false
        return [.invalidate(.contextChanged)]
    }

    /// Marks the buffer invalid until the next boundary: used when an event was
    /// dropped (stale context), so on-screen text and the buffer may disagree.
    public mutating func invalidateUntilBoundary() {
        invalidate(untilBoundary: true)
    }

    public mutating func updatePreferences(_ preferences: InputPreferencesSnapshot) -> [InputStateCommand] {
        let previous = self.preferences
        self.preferences = preferences
        guard previous != preferences else { return [] }

        currentBuffer = ""
        committedWord = nil
        committedBoundary = nil
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
            invalidate(untilBoundary: false)
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
            committedWord = nil
            committedBoundary = nil
            return [.requestManualCorrection(word: word, sequence: input.sequence, context: input.context)]
        case .revertHotkey:
            let word = currentBuffer.isEmpty ? nil : currentBuffer
            // Same desync hazard: whether the revert succeeds (original text is
            // restored) or falls back to a manual correction, the on-screen word
            // is rewritten without buffer-visible events.
            currentBuffer = ""
            committedWord = nil
            committedBoundary = nil
            return [.requestRevert(word: word, sequence: input.sequence, context: input.context)]
        case .delete:
            guard canBuffer(input.context) else {
                committedWord = nil
                committedBoundary = nil
                return invalidateForContext(input.context)
            }
            if !currentBuffer.isEmpty && !isInvalidUntilBoundary {
                currentBuffer.removeLast()
                return [.deleteLast]
            }
            if !isInvalidUntilBoundary, var boundary = committedBoundary, !boundary.isEmpty {
                boundary.removeLast()
                committedBoundary = boundary
                if boundary.isEmpty {
                    currentBuffer = committedWord ?? ""
                    committedWord = nil
                    committedBoundary = nil
                }
                return [.deleteLast]
            }
            committedWord = nil
            committedBoundary = nil
            if !isInvalidUntilBoundary {
                invalidate(untilBoundary: false)
            }
            return [.invalidate(.navigation)]
        case .character(let text):
            guard canBuffer(input.context) else {
                committedWord = nil
                committedBoundary = nil
                return invalidateForContext(input.context)
            }
            guard !isInvalidUntilBoundary else { return [] }
            committedWord = nil
            committedBoundary = nil
            let nextCount = currentBuffer.count + text.count
            guard nextCount <= 64 else {
                invalidate(untilBoundary: true)
                return [.invalidate(.bufferOverflow)]
            }
            currentBuffer += text
            return [.append(text)]
        case .boundary(let boundary):
            let flushedWord = (!isInvalidUntilBoundary && !currentBuffer.isEmpty) ? currentBuffer : nil
            defer {
                if let flushedWord {
                    committedWord = flushedWord
                    committedBoundary = boundary
                } else {
                    committedWord = nil
                    committedBoundary = nil
                }
                currentBuffer = ""
                isInvalidUntilBoundary = false
            }
            guard canBuffer(input.context) else {
                return invalidateForContext(input.context)
            }
            guard !isInvalidUntilBoundary, !currentBuffer.isEmpty else { return [] }
            switch preferences.correctionMode {
            case .automatic:
                return [.flush(
                    word: currentBuffer,
                    boundary: boundary,
                    sequence: input.sequence,
                    context: input.context
                )]
            case .hotkey, .layoutSwitch:
                return []
            }
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
        committedWord = nil
        committedBoundary = nil
        isInvalidUntilBoundary = untilBoundary
    }
}

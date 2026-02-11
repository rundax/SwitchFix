import Foundation
import CoreGraphics
import AppKit

public class TextCorrector {
    private let inputSourceManager = InputSourceManager.shared

    /// Callback to pause/resume the keyboard monitor during correction.
    public var onCorrectionStarted: (() -> Void)?
    public var onCorrectionFinished: (() -> Void)?

    /// The last original text before correction (for undo support).
    public private(set) var lastOriginalText: String?
    public private(set) var lastCorrectedText: String?
    public private(set) var lastOriginalLayout: Layout?
    public private(set) var lastBoundaryText: String?

    /// Timestamp of last correction (for time-limited undo — 5 second window).
    private var lastCorrectionTime: Date?
    private static let undoTimeWindow: TimeInterval = 5.0
    private var sawUserInputDuringCorrection: Bool = false

    public enum UserInputKind {
        case none
        case character
        case boundary
        case other
    }

    private var lastUserInputKind: UserInputKind = .none
    private var lastUserInputTime: Date = .distantPast
    private var pendingSwitchLayout: Layout?
    private var switchTimer: Timer?
    private let switchDelay: TimeInterval = 0.15
    private var userEditGeneration: UInt64 = 0
    private var lastCorrectionEditGeneration: UInt64 = 0

    /// Whether an undo is available (correction happened within the time window).
    public var canUndo: Bool {
        guard lastOriginalText != nil, lastCorrectedText != nil,
              let time = lastCorrectionTime else { return false }
        guard userEditGeneration == lastCorrectionEditGeneration else { return false }
        return Date().timeIntervalSince(time) < TextCorrector.undoTimeWindow
    }

    public init() {}

    /// Mark that the user typed during a correction window.
    public func noteUserInputDuringCorrection() {
        sawUserInputDuringCorrection = true
    }

    /// Record user input activity to delay any pending layout switch.
    public func recordUserInput(kind: UserInputKind) {
        lastUserInputKind = kind
        lastUserInputTime = Date()
        rescheduleSwitchIfNeeded()
    }

    /// Mark that user edited text in the focused field after a correction.
    /// Used to disable stale undo/revert operations that would target old text.
    public func noteUserEdit() {
        userEditGeneration &+= 1
    }

    private func scheduleLayoutSwitch(_ layout: Layout) {
        pendingSwitchLayout = layout
        rescheduleSwitchIfNeeded()
    }

    private func rescheduleSwitchIfNeeded() {
        guard pendingSwitchLayout != nil else { return }
        switchTimer?.invalidate()
        switchTimer = Timer.scheduledTimer(withTimeInterval: switchDelay, repeats: false) { [weak self] _ in
            self?.handleSwitchTimer()
        }
    }

    private func handleSwitchTimer() {
        guard let layout = pendingSwitchLayout else { return }
        if lastUserInputKind == .boundary || lastUserInputKind == .none {
            inputSourceManager.switchTo(layout)
            usleep(10_000)
            pendingSwitchLayout = nil
            switchTimer?.invalidate()
            switchTimer = nil
            return
        }

        // User is actively typing characters; wait for the next boundary input to reschedule.
        switchTimer?.invalidate()
        switchTimer = nil
    }

    /// Perform text correction: delete the wrong text, switch layout, type the correct text.
    /// - Parameters:
    ///   - originalLength: Number of characters to delete (length of the mistyped word)
    ///   - correctedText: The correct text to type
    ///   - targetLayout: The layout to switch to
    public func performCorrection(originalLength: Int, correctedText: String, targetLayout: Layout) {
        sawUserInputDuringCorrection = false
        // Save for undo
        lastOriginalText = nil // We don't have the original text as a string here
        lastCorrectedText = correctedText
        lastCorrectionTime = Date()
        lastOriginalLayout = nil
        lastBoundaryText = nil
        lastCorrectionEditGeneration = userEditGeneration

        // Notify monitor to pause (avoid feedback loop)
        onCorrectionStarted?()

        // Step 1: Delete the incorrect characters by emitting backspace events
        deleteCharacters(count: originalLength)

        // Step 2: Type the correct text (Unicode typing is layout-independent)
        typeText(correctedText)

        // Step 3: Schedule keyboard layout switch for subsequent typing
        if !sawUserInputDuringCorrection {
            scheduleLayoutSwitch(targetLayout)
        }

        // Step 4: Resume monitoring
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onCorrectionFinished?()
        }
    }

    /// Perform correction with the full detection result.
    public func performCorrection(result: DetectionResult) {
        performCorrection(result: result, boundaryCharacter: nil)
    }

    /// Perform correction with boundary character handling.
    /// When a boundary character (space, enter) triggered the correction, it's already
    /// in the text field — so we need to delete it too and re-type it after the corrected word.
    public func performCorrection(result: DetectionResult, boundaryCharacter: String?) {
        sawUserInputDuringCorrection = false
        lastOriginalText = result.originalWord
        lastCorrectedText = result.convertedWord
        lastCorrectionTime = Date()
        lastOriginalLayout = result.sourceLayout
        lastBoundaryText = boundaryCharacter
        lastCorrectionEditGeneration = userEditGeneration

        onCorrectionStarted?()

        // Delete the wrong word + any boundary characters (space/punctuation) if present
        let boundary = boundaryCharacter ?? ""
        let deleteCount = result.originalWord.count + boundary.count
        NSLog("[SwitchFix] Correction: deleting %d chars ('%@' + boundary '%@'), typing '%@'",
              deleteCount, result.originalWord, boundary.isEmpty ? "none" : boundary, result.convertedWord)

        deleteCharacters(count: deleteCount)
        typeText(result.convertedWord)

        // Re-type the boundary characters after the corrected word
        if !boundary.isEmpty {
            typeText(boundary)
        }

        if result.shouldSwitchLayout && !sawUserInputDuringCorrection {
            scheduleLayoutSwitch(result.targetLayout)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onCorrectionFinished?()
        }
    }

    /// Undo the last correction: delete corrected text, switch back, type original.
    public func undoLastCorrection(currentLayout: Layout) {
        guard let original = lastOriginalText, let corrected = lastCorrectedText else {
            return
        }

        onCorrectionStarted?()

        let boundary = lastBoundaryText ?? ""
        let originalLayout = lastOriginalLayout ?? inferredOriginalLayout(from: currentLayout)

        deleteCharacters(count: corrected.count + boundary.count)

        inputSourceManager.switchTo(originalLayout)
        usleep(10_000)
        typeText(original + boundary)

        lastOriginalText = nil
        lastCorrectedText = nil
        lastCorrectionTime = nil
        lastOriginalLayout = nil
        lastBoundaryText = nil
        lastCorrectionEditGeneration = userEditGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onCorrectionFinished?()
        }
    }

    /// Perform correction on selected text by replacing it via clipboard paste.
    public func performSelectionCorrection(selectedText: String, convertedText: String, targetLayout: Layout) {
        lastOriginalText = selectedText
        lastCorrectedText = convertedText
        lastCorrectionTime = Date()
        lastOriginalLayout = inputSourceManager.currentLayout()
        lastBoundaryText = nil
        lastCorrectionEditGeneration = userEditGeneration

        onCorrectionStarted?()

        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        // Put converted text on clipboard
        pasteboard.clearContents()
        pasteboard.setString(convertedText, forType: .string)

        // Simulate Cmd+V to replace selection
        simulatePaste()

        // Switch layout to target
        inputSourceManager.switchTo(targetLayout)

        // Restore clipboard and resume monitoring after paste completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            if let old = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
            self?.onCorrectionFinished?()
        }
    }

    private func inferredOriginalLayout(from currentLayout: Layout) -> Layout {
        switch currentLayout {
        case .english:
            let available = Set(inputSourceManager.availableLayouts())
            if available.contains(.ukrainian) { return .ukrainian }
            if available.contains(.russian) { return .russian }
            return .english
        case .ukrainian, .russian:
            return .english
        }
    }

    // MARK: - CGEvent helpers

    /// Simulate Cmd+V paste keystroke.
    private func simulatePaste() {
        let vKeyCode: UInt16 = 9
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        usleep(50_000) // 50ms for paste to complete
    }

    /// Delete N characters by posting backspace key events.
    private func deleteCharacters(count: Int) {
        let backspaceKeyCode: UInt16 = 51

        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: backspaceKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: backspaceKeyCode, keyDown: false) else {
                continue
            }
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
            usleep(3_000) // 3ms between keystrokes for reliability
        }
    }

    /// Type text by setting the Unicode string on CGEvents.
    /// Uses keyboardSetUnicodeString which works regardless of active layout.
    private func typeText(_ text: String) {
        for char in text {
            let utf16 = Array(String(char).utf16)

            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                continue
            }

            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
            usleep(3_000) // 3ms between characters
        }
    }
}

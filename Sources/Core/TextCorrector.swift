import Foundation
import CoreGraphics

public class TextCorrector {
    private let inputSourceManager = InputSourceManager.shared

    /// Callback to pause/resume the keyboard monitor during correction.
    public var onCorrectionStarted: (() -> Void)?
    public var onCorrectionFinished: (() -> Void)?

    /// The last original text before correction (for undo support).
    public private(set) var lastOriginalText: String?
    public private(set) var lastCorrectedText: String?

    public init() {}

    /// Perform text correction: delete the wrong text, switch layout, type the correct text.
    /// - Parameters:
    ///   - originalLength: Number of characters to delete (length of the mistyped word)
    ///   - correctedText: The correct text to type
    ///   - targetLayout: The layout to switch to
    public func performCorrection(originalLength: Int, correctedText: String, targetLayout: Layout) {
        // Save for undo
        lastOriginalText = nil // We don't have the original text as a string here
        lastCorrectedText = correctedText

        // Notify monitor to pause (avoid feedback loop)
        onCorrectionStarted?()

        // Step 1: Delete the incorrect characters by emitting backspace events
        deleteCharacters(count: originalLength)

        // Step 2: Switch keyboard layout
        inputSourceManager.switchTo(targetLayout)

        // Small delay to let the layout switch take effect
        usleep(10_000) // 10ms

        // Step 3: Type the correct text
        typeText(correctedText)

        // Step 4: Resume monitoring
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onCorrectionFinished?()
        }
    }

    /// Perform correction with the full detection result.
    public func performCorrection(result: DetectionResult) {
        lastOriginalText = result.originalWord
        lastCorrectedText = result.convertedWord

        onCorrectionStarted?()

        deleteCharacters(count: result.originalWord.count)
        inputSourceManager.switchTo(result.targetLayout)
        usleep(10_000)
        typeText(result.convertedWord)

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

        deleteCharacters(count: corrected.count)

        // Determine the original layout (opposite of current since we switched)
        let originalLayout: Layout
        switch currentLayout {
        case .english: originalLayout = .russian // best guess
        case .russian: originalLayout = .english
        case .ukrainian: originalLayout = .english
        }

        inputSourceManager.switchTo(originalLayout)
        usleep(10_000)
        typeText(original)

        lastOriginalText = nil
        lastCorrectedText = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onCorrectionFinished?()
        }
    }

    // MARK: - CGEvent helpers

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

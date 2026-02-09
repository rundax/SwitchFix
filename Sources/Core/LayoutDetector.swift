import Foundation
import Dictionary

/// Represents a detection result — the target layout and converted word.
public struct DetectionResult {
    public let targetLayout: Layout
    public let convertedWord: String
    public let originalWord: String
}

/// State machine for layout detection.
public enum DetectorState {
    case idle
    case buffering
    case detecting
    case correcting
    case cooldown
}

/// Delegate protocol for layout detection events.
public protocol LayoutDetectorDelegate: AnyObject {
    func layoutDetector(_ detector: LayoutDetector, didDetectWrongLayout result: DetectionResult)
}

public class LayoutDetector {
    public weak var delegate: LayoutDetectorDelegate?

    /// Minimum characters before triggering detection.
    public var detectionThreshold: Int = 3

    /// Require this many consecutive wrong-layout words before correcting.
    public var consecutiveThreshold: Int = 1

    private var wordBuffer: String = ""
    private var state: DetectorState = .idle
    private var consecutiveWrongCount: Int = 0
    private var lastDetectionResult: DetectionResult?

    private let validator = WordValidator.shared

    /// The currently active keyboard layout (set externally by InputSourceManager).
    public var currentLayout: Layout = .english

    public init() {}

    /// Add a character to the word buffer.
    public func addCharacter(_ char: String) {
        // Don't accumulate during correction or cooldown
        guard state != .correcting && state != .cooldown else { return }

        wordBuffer += char
        state = .buffering
    }

    /// Called when a word boundary is detected (space, enter, tab, punctuation).
    /// This is the only point where detection fires and triggers correction.
    public func flushBuffer() {
        guard !wordBuffer.isEmpty else {
            state = .idle
            return
        }

        // Only check words that meet the minimum threshold
        if wordBuffer.count >= detectionThreshold {
            checkBuffer()
        }

        // Reset buffer
        wordBuffer = ""
        state = .idle
    }

    /// Called when backspace/delete is pressed — remove last character from buffer.
    public func deleteLastCharacter() {
        guard !wordBuffer.isEmpty else { return }
        wordBuffer.removeLast()
        if wordBuffer.isEmpty {
            state = .idle
        }
    }

    /// Reset all state (e.g., when app loses focus).
    public func reset() {
        wordBuffer = ""
        state = .idle
        consecutiveWrongCount = 0
        lastDetectionResult = nil
    }

    /// Enter correction state (prevents buffering during correction).
    public func beginCorrection() {
        state = .correcting
    }

    /// Exit correction state after correction is complete.
    public func endCorrection() {
        wordBuffer = ""
        state = .cooldown

        // Brief cooldown then return to idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.state = .idle
        }
    }

    /// The current word buffer contents.
    public var currentBuffer: String {
        return wordBuffer
    }

    // MARK: - Detection Logic

    private func checkBuffer() {
        state = .detecting

        let word = wordBuffer

        // Skip if the word contains mixed scripts (both Latin and Cyrillic)
        if containsMixedScripts(word) {
            state = .buffering
            return
        }

        // Check if the word is valid in the current layout's language
        let currentLanguage = languageForLayout(currentLayout)
        if validator.isValidWord(word, language: currentLanguage) {
            // Word is valid in current layout — reset consecutive counter
            consecutiveWrongCount = 0
            lastDetectionResult = nil
            state = .buffering
            return
        }

        // Try converting to alternative layouts
        let alternatives = LayoutMapper.convertToAlternatives(word, from: currentLayout)
        for (targetLayout, converted) in alternatives {
            let targetLanguage = languageForLayout(targetLayout)
            if validator.isValidWord(converted, language: targetLanguage) {
                consecutiveWrongCount += 1
                lastDetectionResult = DetectionResult(
                    targetLayout: targetLayout,
                    convertedWord: converted,
                    originalWord: word
                )

                if consecutiveWrongCount >= consecutiveThreshold {
                    delegate?.layoutDetector(self, didDetectWrongLayout: lastDetectionResult!)
                    consecutiveWrongCount = 0
                }

                state = .buffering
                return
            }
        }

        // No valid alternative found — unknown word, do nothing
        state = .buffering
    }

    /// Map Layout to Language for dictionary lookup.
    private func languageForLayout(_ layout: Layout) -> Language {
        switch layout {
        case .english: return .english
        case .ukrainian: return .ukrainian
        case .russian: return .russian
        }
    }

    /// Check if a string contains both Latin and Cyrillic characters.
    private func containsMixedScripts(_ text: String) -> Bool {
        var hasLatin = false
        var hasCyrillic = false
        for char in text {
            for scalar in char.unicodeScalars {
                if (scalar.value >= 0x0041 && scalar.value <= 0x007A) {
                    hasLatin = true
                } else if (scalar.value >= 0x0400 && scalar.value <= 0x04FF) {
                    hasCyrillic = true
                }
            }
            if hasLatin && hasCyrillic { return true }
        }
        return false
    }
}

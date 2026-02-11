import Foundation
import Dictionary

/// Represents a detection result — the target layout and converted word.
public struct DetectionResult {
    public let targetLayout: Layout
    public let convertedWord: String
    public let originalWord: String
    public let shouldSwitchLayout: Bool
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
    func layoutDetector(_ detector: LayoutDetector, didDetectWrongLayout result: DetectionResult, boundaryCharacter: String?)
}

public class LayoutDetector {
    public weak var delegate: LayoutDetectorDelegate?

    /// Minimum characters before triggering detection.
    public var detectionThreshold: Int = 3

    /// Require this many consecutive wrong-layout words before correcting.
    public var consecutiveThreshold: Int = 1
    public var lowConfidenceMaxLength: Int = 3
    public var lowConfidenceConfirmations: Int = 2

    private var wordBuffer: String = ""
    private var state: DetectorState = .idle
    private var consecutiveWrongCount: Int = 0
    private var lastDetectionResult: DetectionResult?
    private var pendingBoundaryCharacter: String?
    private var pendingSwitchLayout: Layout?
    private var pendingSwitchCount: Int = 0

    private let validator = WordValidator.shared

    /// Layouts that are allowed as correction targets (defaults to all).
    public var allowedLayouts: Set<Layout> = Set(Layout.allCases)

    private static let boundaryCharacterSet: CharacterSet = {
        var set = CharacterSet.punctuationCharacters.union(.symbols)
        set.subtract(CharacterSet(charactersIn: "'’`-"))
        return set
    }()

    /// The currently active keyboard layout (set externally by InputSourceManager).
    public var currentLayout: Layout = .english

    public init() {}

    /// Add a character to the word buffer.
    public func addCharacter(_ char: String) {
        // Don't accumulate during active correction
        guard state != .correcting else { return }

        wordBuffer += char
        state = .buffering
    }

    /// Called when a word boundary is detected (space, enter, tab, punctuation).
    /// This is the only point where detection fires and triggers correction.
    /// - Parameter boundaryCharacter: The character that triggered the flush (e.g. " ", "\n"), or nil for hotkey-triggered flush.
    public func flushBuffer(boundaryCharacter: String? = nil) {
        guard !wordBuffer.isEmpty else {
            state = .idle
            return
        }

        // Split trailing punctuation from the buffer (e.g. "hello," -> "hello" + ",")
        let (coreWord, trailingPunctuation) = splitTrailingBoundary(from: wordBuffer)
        wordBuffer = coreWord

        guard !wordBuffer.isEmpty else {
            state = .idle
            return
        }

        // Store boundary string (trailing punctuation + explicit boundary like space/newline)
        let boundary = trailingPunctuation + (boundaryCharacter ?? "")
        pendingBoundaryCharacter = boundary.isEmpty ? nil : boundary

        // Check buffer at word boundaries (short words are handled by WordValidator whitelist)
        checkBuffer()

        // Reset buffer
        pendingBoundaryCharacter = nil
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

    /// Discard the current buffer without running detection (used in hotkey mode on word boundary).
    public func discardBuffer() {
        wordBuffer = ""
        state = .idle
    }

    /// Reset all state (e.g., when app loses focus).
    public func reset() {
        wordBuffer = ""
        state = .idle
        consecutiveWrongCount = 0
        lastDetectionResult = nil
        pendingSwitchLayout = nil
        pendingSwitchCount = 0
    }

    /// Enter correction state (prevents buffering during correction).
    public func beginCorrection() {
        state = .correcting
    }

    /// Exit correction state after correction is complete.
    public func endCorrection() {
        wordBuffer = ""
        state = .idle
    }

    /// The current word buffer contents.
    public var currentBuffer: String {
        return wordBuffer
    }

    // MARK: - Detection Logic

    private func checkBuffer() {
        state = .detecting

        let word = wordBuffer
        NSLog("[SwitchFix] Detection: checking buffer '%@' (layout: %@)", word, currentLayout.rawValue)

        // Skip if the word contains mixed scripts (both Latin and Cyrillic)
        if containsMixedScripts(word) {
            NSLog("[SwitchFix] Detection: skipped — mixed scripts")
            state = .buffering
            return
        }

        // Check if the word is valid in the current layout's language
        let currentLanguage = languageForLayout(currentLayout)
        if validator.validate(word, language: currentLanguage, allowSuggestion: false).isValid {
            // Word is valid in current layout — reset consecutive counter
            NSLog("[SwitchFix] Detection: '%@' is valid in %@ — no correction needed", word, currentLayout.rawValue)
            consecutiveWrongCount = 0
            lastDetectionResult = nil
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            state = .buffering
            return
        }

        // Try converting to alternative layouts
        let alternatives = LayoutMapper.convertToAlternatives(word, from: currentLayout)
            .filter { allowedLayouts.contains($0.0) }
        for (targetLayout, converted) in alternatives {
            let targetLanguage = languageForLayout(targetLayout)
            let validation = validator.validate(converted, language: targetLanguage, allowSuggestion: true)
            if validation.isValid {
                let finalWord = validation.correctedWord ?? converted
                let isLowConfidence = validation.correctedWord != nil || word.count <= lowConfidenceMaxLength
                let shouldSwitch = shouldSwitchLayout(isLowConfidence: isLowConfidence, targetLayout: targetLayout)
                consecutiveWrongCount += 1
                lastDetectionResult = DetectionResult(
                    targetLayout: targetLayout,
                    convertedWord: finalWord,
                    originalWord: word,
                    shouldSwitchLayout: shouldSwitch
                )

                NSLog("[SwitchFix] Detection: '%@' → '%@' (%@), consecutive: %d/%d, switch: %@",
                      word, finalWord, targetLayout.rawValue, consecutiveWrongCount, consecutiveThreshold,
                      shouldSwitch ? "yes" : "no")

                if consecutiveWrongCount >= consecutiveThreshold {
                    delegate?.layoutDetector(self, didDetectWrongLayout: lastDetectionResult!, boundaryCharacter: pendingBoundaryCharacter)
                    consecutiveWrongCount = 0
                }

                state = .buffering
                return
            }
        }

        // No valid alternative found — unknown word, do nothing
        NSLog("[SwitchFix] Detection: '%@' — no valid alternative found", word)
        pendingSwitchLayout = nil
        pendingSwitchCount = 0
        state = .buffering
    }

    private func shouldSwitchLayout(isLowConfidence: Bool, targetLayout: Layout) -> Bool {
        if !isLowConfidence {
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            return true
        }

        if pendingSwitchLayout == targetLayout {
            pendingSwitchCount += 1
        } else {
            pendingSwitchLayout = targetLayout
            pendingSwitchCount = 1
        }

        if pendingSwitchCount >= lowConfidenceConfirmations {
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            return true
        }

        return false
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

    /// Split trailing punctuation/symbols from a word.
    private func splitTrailingBoundary(from text: String) -> (core: String, trailing: String) {
        var core = text
        var trailing = ""
        while let last = core.last, isBoundaryChar(last) {
            trailing.insert(last, at: trailing.startIndex)
            core.removeLast()
        }
        return (core, trailing)
    }

    private func isBoundaryChar(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        return LayoutDetector.boundaryCharacterSet.contains(scalar)
    }
}

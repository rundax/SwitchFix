import Foundation
import Dictionary

/// Represents a detection result — the target layout and converted word.
public struct DetectionResult {
    public let sourceLayout: Layout
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
    public var suggestionMaxLength: Int = 2
    public var ukrainianFromVariant: UkrainianKeyboardVariant = .standard
    public var ukrainianToVariant: UkrainianKeyboardVariant = .standard
    public var shortWordSuppressionLength: Int = 2
    public var shortWordSuppressionMinValidContext: Int = 2
    public var shortWordSuppressionContextWindow: Int = 6

    private var wordBuffer: String = ""
    private var state: DetectorState = .idle
    private var consecutiveWrongCount: Int = 0
    private var lastDetectionResult: DetectionResult?
    private var pendingBoundaryCharacter: String?
    private var pendingSwitchLayout: Layout?
    private var pendingSwitchCount: Int = 0
    private var recentOutcomes: [RecentOutcome] = []
    private var pendingSuppressedShort: SuppressedShort?

    private let validator = WordValidator.shared

    /// Layouts that are allowed as correction targets (defaults to all).
    public var allowedLayouts: Set<Layout> = Set(Layout.allCases)

    private enum RecentOutcome {
        case validCurrent
        case corrected
        case unknown
    }

    private struct SuppressedShort {
        let originalWord: String
        let convertedWord: String
        let targetLayout: Layout
        let boundaryAfterWord: String
    }

    private static let boundaryCharacterSet: CharacterSet = {
        var set = CharacterSet.punctuationCharacters.union(.symbols)
        set.subtract(CharacterSet(charactersIn: "'’`-"))
        // Keep punctuation keys that may correspond to letters in other layouts.
        set.subtract(CharacterSet(charactersIn: ",.;'[]`<>:\"{}~"))
        return set
    }()

    private static let englishVowels = CharacterSet(charactersIn: "aeiouyAEIOUY")
    private static let ukrainianVowels = CharacterSet(charactersIn: "аеєиіїоуюяАЕЄИІЇОУЮЯ")
    private static let russianVowels = CharacterSet(charactersIn: "аеёиоуыэюяАЕЁИОУЫЭЮЯ")

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
        recentOutcomes = []
        pendingSuppressedShort = nil
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
        let suppressedShort = consumePendingSuppressedShort()

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
            recordOutcome(.validCurrent)
            state = .buffering
            return
        }

        // Try converting to alternative layouts
        let alternatives = LayoutMapper.convertToAlternatives(
            word,
            from: currentLayout,
            ukrainianFromVariant: ukrainianFromVariant,
            ukrainianToVariant: ukrainianToVariant
        )
            .filter { allowedLayouts.contains($0.0) }
        for (targetLayout, converted) in alternatives {
            let targetLanguage = languageForLayout(targetLayout)
            // Avoid substituting into a different valid word (e.g. "pe" -> "за").
            // Auto-detection should accept only exact layout mapping here.
            let allowSuggestion = false
            let validation = validator.validate(
                converted,
                language: targetLanguage,
                allowSuggestion: allowSuggestion
            )
            if validation.isValid {
                var finalWord = applyCase(from: word, to: validation.correctedWord ?? converted)
                var originalForCorrection = word
                let isLowConfidence = validation.correctedWord != nil || word.count <= lowConfidenceMaxLength
                let shouldSwitch = shouldSwitchLayout(isLowConfidence: isLowConfidence, targetLayout: targetLayout)

                if shouldSuppressLowConfidenceCorrection(
                    original: word,
                    converted: finalWord,
                    targetLayout: targetLayout,
                    isLowConfidence: isLowConfidence,
                    shouldSwitch: shouldSwitch
                ) {
                    NSLog("[SwitchFix] Detection: '%@' → '%@' (%@) suppressed — strong %@ context",
                          word, finalWord, targetLayout.rawValue, currentLayout.rawValue)
                    consecutiveWrongCount = 0
                    lastDetectionResult = nil
                    if let boundary = pendingBoundaryCharacter, !boundary.isEmpty {
                        pendingSuppressedShort = SuppressedShort(
                            originalWord: word,
                            convertedWord: finalWord,
                            targetLayout: targetLayout,
                            boundaryAfterWord: boundary
                        )
                    }
                    recordOutcome(.unknown)
                    state = .buffering
                    return
                }

                if let merged = mergeSuppressedShort(
                    suppressedShort,
                    currentOriginal: word,
                    currentConverted: finalWord,
                    targetLayout: targetLayout,
                    isLowConfidence: isLowConfidence,
                    shouldSwitch: shouldSwitch
                ) {
                    originalForCorrection = merged.original
                    finalWord = merged.converted
                    NSLog("[SwitchFix] Detection: replayed suppressed short word for contextual correction")
                }

                consecutiveWrongCount += 1
                lastDetectionResult = DetectionResult(
                    sourceLayout: currentLayout,
                    targetLayout: targetLayout,
                    convertedWord: finalWord,
                    originalWord: originalForCorrection,
                    shouldSwitchLayout: shouldSwitch
                )

                NSLog("[SwitchFix] Detection: '%@' → '%@' (%@), consecutive: %d/%d, switch: %@",
                      word, finalWord, targetLayout.rawValue, consecutiveWrongCount, consecutiveThreshold,
                      shouldSwitch ? "yes" : "no")

                if consecutiveWrongCount >= consecutiveThreshold {
                    delegate?.layoutDetector(self, didDetectWrongLayout: lastDetectionResult!, boundaryCharacter: pendingBoundaryCharacter)
                    consecutiveWrongCount = 0
                }

                recordOutcome(.corrected)
                state = .buffering
                return
            }

            if shouldAllowAcronymFallback(original: word, converted: converted, currentLanguage: currentLanguage) {
                let finalWord = applyCase(from: word, to: converted)
                let shouldSwitch = shouldSwitchLayout(isLowConfidence: true, targetLayout: targetLayout)
                consecutiveWrongCount += 1
                lastDetectionResult = DetectionResult(
                    sourceLayout: currentLayout,
                    targetLayout: targetLayout,
                    convertedWord: finalWord,
                    originalWord: word,
                    shouldSwitchLayout: shouldSwitch
                )

                NSLog("[SwitchFix] Detection: '%@' → '%@' (%@), consecutive: %d/%d, switch: %@ (acronym)",
                      word, finalWord, targetLayout.rawValue, consecutiveWrongCount, consecutiveThreshold,
                      shouldSwitch ? "yes" : "no")

                if consecutiveWrongCount >= consecutiveThreshold {
                    delegate?.layoutDetector(self, didDetectWrongLayout: lastDetectionResult!, boundaryCharacter: pendingBoundaryCharacter)
                    consecutiveWrongCount = 0
                }

                recordOutcome(.corrected)
                state = .buffering
                return
            }
        }

        // No valid alternative found — unknown word, do nothing
        NSLog("[SwitchFix] Detection: '%@' — no valid alternative found", word)
        pendingSwitchLayout = nil
        pendingSwitchCount = 0
        recordOutcome(.unknown)
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

    private func shouldSuppressLowConfidenceCorrection(
        original: String,
        converted: String,
        targetLayout: Layout,
        isLowConfidence: Bool,
        shouldSwitch: Bool
    ) -> Bool {
        guard isLowConfidence else { return false }
        guard original.count <= shortWordSuppressionLength else { return false }
        guard !shouldSwitch else { return false }
        guard targetLayout != currentLayout else { return false }
        guard !converted.isEmpty else { return false }
        return hasStrongCurrentContext()
    }

    private func consumePendingSuppressedShort() -> SuppressedShort? {
        let value = pendingSuppressedShort
        pendingSuppressedShort = nil
        return value
    }

    private func mergeSuppressedShort(
        _ suppressed: SuppressedShort?,
        currentOriginal: String,
        currentConverted: String,
        targetLayout: Layout,
        isLowConfidence: Bool,
        shouldSwitch: Bool
    ) -> (original: String, converted: String)? {
        guard let suppressed else { return nil }
        guard suppressed.targetLayout == targetLayout else { return nil }

        // Merge only when the current word provides stronger evidence than the suppressed short word.
        let hasStrongCurrentSignal = currentOriginal.count > shortWordSuppressionLength || shouldSwitch || !isLowConfidence
        guard hasStrongCurrentSignal else { return nil }

        let bridge = suppressed.boundaryAfterWord
        guard !bridge.isEmpty else { return nil }

        return (
            original: suppressed.originalWord + bridge + currentOriginal,
            converted: suppressed.convertedWord + bridge + currentConverted
        )
    }

    private func hasStrongCurrentContext() -> Bool {
        let window = max(1, shortWordSuppressionContextWindow)
        let recent = recentOutcomes.suffix(window)
        let validCount = recent.reduce(0) { partial, outcome in
            if case .validCurrent = outcome {
                return partial + 1
            }
            return partial
        }
        let hasRecentCorrection = recent.contains { outcome in
            if case .corrected = outcome { return true }
            return false
        }
        return validCount >= shortWordSuppressionMinValidContext && !hasRecentCorrection
    }

    private func recordOutcome(_ outcome: RecentOutcome) {
        recentOutcomes.append(outcome)
        let window = max(1, shortWordSuppressionContextWindow)
        if recentOutcomes.count > window {
            recentOutcomes.removeFirst(recentOutcomes.count - window)
        }
    }

    private func applyCase(from original: String, to word: String) -> String {
        guard !word.isEmpty else { return word }
        if isAllUppercase(original) {
            return word.uppercased()
        }
        if isCapitalized(original) {
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }
        return word
    }

    private func isAllUppercase(_ word: String) -> Bool {
        var hasLetters = false
        for char in word {
            if char.isLetter {
                hasLetters = true
                if !char.isUppercase {
                    return false
                }
            }
        }
        return hasLetters
    }

    private func isCapitalized(_ word: String) -> Bool {
        var chars = Array(word)
        while let first = chars.first, !first.isLetter {
            chars.removeFirst()
        }
        guard let first = chars.first, first.isUppercase else { return false }
        for c in chars.dropFirst() where c.isLetter {
            if !c.isLowercase { return false }
        }
        return true
    }

    private func shouldAllowAcronymFallback(original: String, converted: String, currentLanguage: Language) -> Bool {
        guard original.count >= 2 else { return false }
        guard original.count <= 3 else { return false }
        guard isAllUppercase(original) else { return false }
        if containsVowel(original, language: currentLanguage) { return false }
        if containsMixedScripts(converted) { return false }
        return true
    }

    private func containsVowel(_ text: String, language: Language) -> Bool {
        let vowels: CharacterSet
        switch language {
        case .english: vowels = LayoutDetector.englishVowels
        case .ukrainian: vowels = LayoutDetector.ukrainianVowels
        case .russian: vowels = LayoutDetector.russianVowels
        }
        for scalar in text.unicodeScalars where vowels.contains(scalar) {
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

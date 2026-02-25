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
    public var suggestionMaxLength: Int = 5
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
    private static let latinLowercaseRange: ClosedRange<UInt32> = 0x0061...0x007A
    private static let latinUppercaseRange: ClosedRange<UInt32> = 0x0041...0x005A
    private static let cyrillicRange: ClosedRange<UInt32> = 0x0400...0x052F
    private static let ukrainianTypoOverrides: [String: String] = [
        "дуе": "дує"
    ]

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
        let sourceLayout = resolvedSourceLayout(for: word)
        if sourceLayout != currentLayout {
            NSLog("[SwitchFix] Detection: inferred source layout %@ for buffer '%@'", sourceLayout.rawValue, word)
        }

        // Skip if the word contains mixed scripts (both Latin and Cyrillic)
        if containsMixedScripts(word) {
            NSLog("[SwitchFix] Detection: skipped — mixed scripts")
            state = .buffering
            return
        }

        // Check if the word is valid in the current layout's language
        let currentLanguage = languageForLayout(sourceLayout)
        if validator.validate(word, language: currentLanguage, allowSuggestion: false).isValid {
            // BloomFilter may produce false positives. For Cyrillic layouts, require an exact
            // dictionary hit before treating the current-layout word as definitely valid.
            if sourceLayout != .english && !validator.isExactWord(word, language: currentLanguage) {
                NSLog("[SwitchFix] Detection: '%@' in %@ rejected as current-layout false positive",
                      word, sourceLayout.rawValue)
            } else {
                // Word is valid in current layout — reset consecutive counter
                NSLog("[SwitchFix] Detection: '%@' is valid in %@ — no correction needed", word, sourceLayout.rawValue)
                consecutiveWrongCount = 0
                lastDetectionResult = nil
                pendingSwitchLayout = nil
                pendingSwitchCount = 0
                recordOutcome(.validCurrent)
                state = .buffering
                return
            }
        }

        if sourceLayout == .ukrainian,
           let override = ukrainianTypoOverride(for: word) {
                let correctedWord = applyCase(from: word, to: override)
                let result = DetectionResult(
                    sourceLayout: sourceLayout,
                    targetLayout: sourceLayout,
                    convertedWord: correctedWord,
                    originalWord: word,
                    shouldSwitchLayout: false
                )
                NSLog("[SwitchFix] Detection: '%@' → '%@' (%@), typo correction in current layout",
                      word, correctedWord, sourceLayout.rawValue)
                lastDetectionResult = result
                pendingSwitchLayout = nil
                pendingSwitchCount = 0
                consecutiveWrongCount = 0
                delegate?.layoutDetector(self, didDetectWrongLayout: result, boundaryCharacter: pendingBoundaryCharacter)
                recordOutcome(.corrected)
                state = .buffering
                return
        }

        // Try converting to alternative layouts
        let alternatives = LayoutMapper.convertToAlternatives(
            word,
            from: sourceLayout,
            ukrainianFromVariant: ukrainianFromVariant,
            ukrainianToVariant: ukrainianToVariant
        )
            .filter { allowedLayouts.contains($0.0) }
        for (targetLayout, converted) in alternatives {
            let targetLanguage = languageForLayout(targetLayout)
            var candidateConversions: [String] = [converted]
            if sourceLayout == .ukrainian && targetLayout == .english {
                let fallbackVariant: UkrainianKeyboardVariant = (ukrainianFromVariant == .legacy) ? .standard : .legacy
                let fallbackConverted = LayoutMapper.convert(
                    word,
                    from: .ukrainian,
                    to: .english,
                    ukrainianFromVariant: fallbackVariant,
                    ukrainianToVariant: ukrainianToVariant
                )
                if fallbackConverted != converted && !candidateConversions.contains(fallbackConverted) {
                    candidateConversions.append(fallbackConverted)
                }
            }

            for candidate in candidateConversions {
                let tokenParts = splitTokenForValidation(candidate)
                let validationInput = tokenParts.core.isEmpty ? candidate : tokenParts.core

                // Avoid substituting into a different valid word (e.g. "pe" -> "за").
                // Allow typo-tolerant suggestions only for EN -> Cyrillic conversion.
                // This keeps automatic mode conservative and avoids aggressive rewrites in other directions.
                let allowSuggestion =
                    sourceLayout == .english &&
                    targetLayout != .english &&
                    word.count >= 4 &&
                    word.count <= suggestionMaxLength &&
                    !containsVowel(validationInput, language: targetLanguage) &&
                    !containsVowel(word, language: currentLanguage)
                let validation = validator.validate(
                    validationInput,
                    language: targetLanguage,
                    allowSuggestion: allowSuggestion
                )
                if validation.isValid {
                    if validation.correctedWord == nil &&
                        !validator.isExactWord(validationInput, language: targetLanguage) {
                        NSLog("[SwitchFix] Detection: '%@' → '%@' (%@) rejected — non-exact dictionary hit",
                              word, candidate, targetLayout.rawValue)
                        continue
                    }

                    let correctedCore = validation.correctedWord ?? validationInput
                    let recomposedWord = tokenParts.prefix + correctedCore + tokenParts.suffix
                    var finalWord = applyCase(from: word, to: recomposedWord)
                    var originalForCorrection = word
                    let isLowConfidence = validation.correctedWord != nil || word.count <= lowConfidenceMaxLength
                    let shouldSwitch = shouldSwitchLayout(isLowConfidence: isLowConfidence, targetLayout: targetLayout)

                    if shouldSuppressLowConfidenceCorrection(
                        original: word,
                        converted: finalWord,
                        targetLayout: targetLayout,
                        sourceLayout: sourceLayout,
                        isLowConfidence: isLowConfidence,
                        shouldSwitch: shouldSwitch
                    ) {
                        NSLog("[SwitchFix] Detection: '%@' → '%@' (%@) suppressed — strong %@ context",
                              word, finalWord, targetLayout.rawValue, sourceLayout.rawValue)
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
                        sourceLayout: sourceLayout,
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
            }

            if shouldAllowAcronymFallback(original: word, converted: converted, currentLanguage: currentLanguage) {
                let finalWord = applyCase(from: word, to: converted)
                let shouldSwitch = shouldSwitchLayout(isLowConfidence: true, targetLayout: targetLayout)

                if shouldSuppressAcronymFallback(
                    targetLayout: targetLayout,
                    sourceLayout: sourceLayout,
                    shouldSwitch: shouldSwitch
                ) {
                    NSLog("[SwitchFix] Detection: '%@' → '%@' (%@) suppressed — strong %@ context (acronym)",
                          word, finalWord, targetLayout.rawValue, sourceLayout.rawValue)
                    consecutiveWrongCount = 0
                    lastDetectionResult = nil
                    recordOutcome(.unknown)
                    state = .buffering
                    return
                }

                consecutiveWrongCount += 1
                lastDetectionResult = DetectionResult(
                    sourceLayout: sourceLayout,
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
        sourceLayout: Layout,
        isLowConfidence: Bool,
        shouldSwitch: Bool
    ) -> Bool {
        guard isLowConfidence else { return false }
        guard original.count <= shortWordSuppressionLength else { return false }
        guard !shouldSwitch else { return false }
        guard targetLayout != sourceLayout else { return false }
        guard !converted.isEmpty else { return false }
        return hasStrongCurrentContext()
    }

    private func shouldSuppressAcronymFallback(
        targetLayout: Layout,
        sourceLayout: Layout,
        shouldSwitch: Bool
    ) -> Bool {
        guard targetLayout != sourceLayout else { return false }
        guard !shouldSwitch else { return false }
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

    private enum ScriptKind {
        case latin
        case cyrillic
        case mixed
        case unknown
    }

    private func resolvedSourceLayout(for word: String) -> Layout {
        let script = scriptKind(for: word)
        switch script {
        case .latin:
            if allowedLayouts.contains(.english) {
                return .english
            }
            return currentLayout
        case .cyrillic:
            if currentLayout == .ukrainian || currentLayout == .russian {
                return currentLayout
            }
            return inferCyrillicLayout(for: word) ?? currentLayout
        case .mixed, .unknown:
            return currentLayout
        }
    }

    private func scriptKind(for text: String) -> ScriptKind {
        var hasLatin = false
        var hasCyrillic = false

        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            let value = scalar.value
            if LayoutDetector.latinLowercaseRange.contains(value) || LayoutDetector.latinUppercaseRange.contains(value) {
                hasLatin = true
            } else if LayoutDetector.cyrillicRange.contains(value) {
                hasCyrillic = true
            }
            if hasLatin && hasCyrillic {
                return .mixed
            }
        }

        if hasLatin { return .latin }
        if hasCyrillic { return .cyrillic }
        return .unknown
    }

    private func inferCyrillicLayout(for word: String) -> Layout? {
        let lower = word.lowercased()

        if containsAnyCharacter(from: "іїєґ", in: lower), allowedLayouts.contains(.ukrainian) {
            return .ukrainian
        }
        if containsAnyCharacter(from: "ыэёъ", in: lower), allowedLayouts.contains(.russian) {
            return .russian
        }

        let hasUkrainian = allowedLayouts.contains(.ukrainian)
        let hasRussian = allowedLayouts.contains(.russian)
        if hasUkrainian && !hasRussian { return .ukrainian }
        if hasRussian && !hasUkrainian { return .russian }
        if hasUkrainian { return .ukrainian }
        if hasRussian { return .russian }
        return nil
    }

    private func containsAnyCharacter(from candidates: String, in text: String) -> Bool {
        let set = Set(candidates)
        return text.contains { set.contains($0) }
    }

    private func splitTokenForValidation(_ token: String) -> (prefix: String, core: String, suffix: String) {
        let chars = Array(token)
        if chars.isEmpty {
            return ("", "", "")
        }

        var start = 0
        while start < chars.count {
            let ch = chars[start]
            if ch.isLetter || ch.isNumber {
                break
            }
            start += 1
        }

        var end = chars.count
        while end > start {
            let ch = chars[end - 1]
            if ch.isLetter || ch.isNumber {
                break
            }
            end -= 1
        }

        let prefix = start > 0 ? String(chars[0..<start]) : ""
        let core = start < end ? String(chars[start..<end]) : ""
        let suffix = end < chars.count ? String(chars[end..<chars.count]) : ""
        return (prefix, core, suffix)
    }

    private func ukrainianTypoOverride(for word: String) -> String? {
        let normalized = word.lowercased()
        return LayoutDetector.ukrainianTypoOverrides[normalized]
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

import Foundation

public class WordValidator {
    private let loader = DictionaryLoader.shared
    private let engine = SuggestionEngine()

    public static let shared = WordValidator()

    private init() {}

    public struct ValidationResult {
        public let isValid: Bool
        public let correctedWord: String?
    }

    private static let englishContractionSuffixes: [String] = [
        "'s", "'re", "'ve", "'ll", "'d", "n't"
    ]

    private static let latinLowercaseRange: ClosedRange<UInt32> = 0x0061...0x007A
    private static let latinUppercaseRange: ClosedRange<UInt32> = 0x0041...0x005A
    private static let cyrillicRange: ClosedRange<UInt32> = 0x0400...0x052F

    private static let englishVowels = CharacterSet(charactersIn: "aeiouyAEIOUY")
    private static let englishCoreVowels = CharacterSet(charactersIn: "aeiouAEIOU")
    private static let ukrainianVowels = CharacterSet(charactersIn: "аеєиіїоуюяАЕЄИІЇОУЮЯ")
    private static let russianVowels = CharacterSet(charactersIn: "аеёиоуыэюяАЕЁИОУЫЭЮЯ")

    /// Validate a word, optionally allowing spellchecker suggestions.
    public func validate(_ word: String, language: Language, allowSuggestion: Bool = false) -> ValidationResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        if shouldSkip(trimmed) {
            return ValidationResult(isValid: false, correctedWord: nil)
        }

        let normalized = trimmed.lowercased().replacingOccurrences(of: "’", with: "'")
        guard matchesExpectedScript(normalized, language: language) else {
            return ValidationResult(isValid: false, correctedWord: nil)
        }

        if language == .english, isEnglishContractionValid(normalized) {
            return ValidationResult(isValid: true, correctedWord: nil)
        }

        // Short words (≤ 2 chars) produce too many false positives — allow only known short words
        if normalized.count <= 2 {
            let ok = SuggestionEngine.shortWords[language]?.contains(normalized) ?? false
            if ok {
                return ValidationResult(isValid: true, correctedWord: nil)
            }

            if allowSuggestion {
                if let best = engine.closestShortWord(to: normalized, language: language) {
                    return ValidationResult(isValid: true, correctedWord: best)
                }
            }

            return ValidationResult(isValid: false, correctedWord: nil)
        }

        if loader.mightContain(normalized, language: language) {
            if shouldRequireExactDictionaryMatch(normalized, language: language) {
                if isExactDictionaryWord(normalized, language: language) {
                    return ValidationResult(isValid: true, correctedWord: nil)
                }
            } else {
                return ValidationResult(isValid: true, correctedWord: nil)
            }
        }

        guard allowSuggestion else {
            return ValidationResult(isValid: false, correctedWord: nil)
        }

        if let best = engine.dictionarySuggestion(for: normalized, language: language),
           engine.isSuggestionAcceptable(original: normalized, suggestion: best) {
            return ValidationResult(isValid: true, correctedWord: best)
        }

        return ValidationResult(isValid: false, correctedWord: nil)
    }

    /// Check if a word is valid in the given language.
    /// Returns true if the word is likely in the dictionary (may have false positives from BloomFilter).
    public func isValidWord(_ word: String, language: Language) -> Bool {
        return validate(word, language: language, allowSuggestion: false).isValid
    }

    /// Check if a word exists exactly in dictionary resources for the language.
    /// Unlike `isValidWord`, this does not rely on BloomFilter membership only.
    public func isExactWord(_ word: String, language: Language) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return false
        }
        let normalized = trimmed.lowercased().replacingOccurrences(of: "’", with: "'")
        guard matchesExpectedScript(normalized, language: language) else {
            return false
        }
        return isExactDictionaryWord(normalized, language: language)
    }

    private func shouldSkip(_ word: String) -> Bool {
        if word.allSatisfy({ $0.isNumber }) { return true }

        let lower = word.lowercased()
        if lower.hasPrefix("http") || lower.hasPrefix("www.") || lower.hasPrefix("ftp") {
            return true
        }

        if word.contains("@") && word.contains(".") {
            return true
        }

        var prevIsLower = false
        for char in word {
            if char.isUppercase {
                if prevIsLower { return true }
                prevIsLower = false
            } else if char.isLowercase {
                prevIsLower = true
            } else {
                prevIsLower = false
            }
        }

        return false
    }

    private func shouldVerifyBloomHit(_ word: String, language: Language) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 4 {
            return false
        }

        if !containsVowel(trimmed, language: language) {
            return true
        }

        if language == .english && !containsCoreEnglishVowel(trimmed) {
            return true
        }

        return false
    }

    private func shouldRequireExactDictionaryMatch(_ word: String, language: Language) -> Bool {
        if word.count <= 4 {
            return true
        }
        return shouldVerifyBloomHit(word, language: language)
    }

    private func isExactDictionaryWord(_ word: String, language: Language) -> Bool {
        return loader.containsExact(word, language: language)
    }

    private func containsVowel(_ word: String, language: Language) -> Bool {
        let vowels: CharacterSet
        switch language {
        case .english:
            vowels = WordValidator.englishVowels
        case .ukrainian:
            vowels = WordValidator.ukrainianVowels
        case .russian:
            vowels = WordValidator.russianVowels
        }

        for scalar in word.unicodeScalars where vowels.contains(scalar) {
            return true
        }
        return false
    }

    private func containsCoreEnglishVowel(_ word: String) -> Bool {
        for scalar in word.unicodeScalars where WordValidator.englishCoreVowels.contains(scalar) {
            return true
        }
        return false
    }



    private func isEnglishContractionValid(_ word: String) -> Bool {
        guard word.contains("'") else { return false }
        for suffix in WordValidator.englishContractionSuffixes where word.hasSuffix(suffix) {
            let base = String(word.dropLast(suffix.count))
            if base.isEmpty { continue }
            if base.hasSuffix("'") { continue }
            if SuggestionEngine.shortWords[.english]?.contains(base) == true {
                return true
            }
            if loader.mightContain(base, language: .english) {
                return true
            }
        }
        return false
    }



    private func matchesExpectedScript(_ word: String, language: Language) -> Bool {
        var hasLatin = false
        var hasCyrillic = false

        for scalar in word.unicodeScalars where scalar.properties.isAlphabetic {
            let value = scalar.value

            if WordValidator.latinLowercaseRange.contains(value) || WordValidator.latinUppercaseRange.contains(value) {
                hasLatin = true
                continue
            }

            if WordValidator.cyrillicRange.contains(value) {
                hasCyrillic = true
                continue
            }

            return false
        }

        switch language {
        case .english:
            return hasLatin && !hasCyrillic
        case .ukrainian, .russian:
            return hasCyrillic && !hasLatin
        }
    }


}

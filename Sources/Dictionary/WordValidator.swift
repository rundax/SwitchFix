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

    /// Contractions whose base does not survive suffix stripping ("can't" → "ca").
    private static let irregularContractions: Set<String> = [
        "can't", "won't", "shan't", "ain't", "let's", "y'all", "o'clock", "ma'am"
    ]

    private static let whitelistedWords: [Language: Set<String>] = [
        .english: [
            "ccs", "cmd", "opt", "ctrl", "mac", "ios", "api", "url", "app", "dev", "bot", "txt", "csv", "xml", "json", "tas", "task", "tasks"
        ]
    ]

    private static let latinLowercaseRange: ClosedRange<UInt32> = 0x0061...0x007A
    private static let latinUppercaseRange: ClosedRange<UInt32> = 0x0041...0x005A
    private static let cyrillicRange: ClosedRange<UInt32> = 0x0400...0x052F

    /// Validate a word with exact dictionary membership and bounded short-word correction.
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

        if WordValidator.whitelistedWords[language]?.contains(normalized) == true {
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

        if loader.containsExact(normalized, language: language) {
            return ValidationResult(isValid: true, correctedWord: nil)
        }

        return ValidationResult(isValid: false, correctedWord: nil)
    }

    /// Check if a word is valid in the given language.
    /// Returns true if the word exists in the exact dictionary or a bounded built-in set.
    public func isValidWord(_ word: String, language: Language) -> Bool {
        return validate(word, language: language, allowSuggestion: false).isValid
    }

    /// Check if a word exists exactly in dictionary resources for the language.
    /// Unlike `isValidWord`, this excludes bounded short-word correction behavior.
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

    private func isExactDictionaryWord(_ word: String, language: Language) -> Bool {
        return loader.containsExact(word, language: language)
    }

    private func isEnglishContractionValid(_ word: String) -> Bool {
        guard word.contains("'") else { return false }
        if WordValidator.irregularContractions.contains(word.lowercased()) {
            return true
        }
        for suffix in WordValidator.englishContractionSuffixes where word.hasSuffix(suffix) {
            let base = String(word.dropLast(suffix.count))
            if base.isEmpty { continue }
            if base.hasSuffix("'") { continue }
            if SuggestionEngine.shortWords[.english]?.contains(base) == true {
                return true
            }
            if loader.containsExact(base, language: .english) {
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

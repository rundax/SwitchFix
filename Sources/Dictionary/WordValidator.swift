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
            "ccs", "cmd", "opt", "ctrl", "mac", "ios", "api", "url", "app", "dev", "bot", "txt", "csv", "xml", "json", "tas", "task", "tasks", "key", "keys", "word", "words", "change", "changes", "whole", "wholes", "remove", "llm", "llms", "replace", "replaces", "replaced", "replacing", "gsd", "vs"
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

        if language == .english, isEnglishInflectionValid(normalized) {
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
        if isExactDictionaryWord(normalized, language: language) {
            return true
        }
        if language == .english {
            if isEnglishContractionValid(normalized) {
                return true
            }
            if isEnglishInflectionValid(normalized) {
                return true
            }
        }
        return false
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

    /// Validate regular English inflections (plurals, verb tenses, participles, adverbs, comparatives)
    /// whose base exists in the dictionary or whitelist.
    private func isEnglishInflectionValid(_ word: String) -> Bool {
        guard word.count > 2 else { return false }

        // 1. Plural and 3rd-person singular present tense (-s, -es, -ies, -ves)
        if word.hasSuffix("s"), !word.hasSuffix("ss") {
            if word.hasSuffix("ies"), word.count >= 5 {
                // e.g. cities -> city, queries -> query, companies -> company
                let base = String(word.dropLast(3)) + "y"
                if isCandidateEnglishBaseValid(base) { return true }
                // e.g. series -> serie (or pies -> pie)
                if isCandidateEnglishBaseValid(String(word.dropLast(1))) { return true }
            }
            if word.hasSuffix("ves"), word.count >= 5 {
                // e.g. knives -> knife, lives -> life, halves -> half, wolves -> wolf
                if isCandidateEnglishBaseValid(String(word.dropLast(3)) + "fe") { return true }
                if isCandidateEnglishBaseValid(String(word.dropLast(3)) + "f") { return true }
            }
            if word.hasSuffix("es"), word.count >= 4 {
                // e.g. changes -> change, types -> type, places -> place
                if isCandidateEnglishBaseValid(String(word.dropLast(1))) { return true }
                // e.g. boxes -> box, watches -> watch, fixes -> fix, wishes -> wish, heroes -> hero
                if isCandidateEnglishBaseValid(String(word.dropLast(2))) { return true }
            }
            // Regular -s: keys -> key, words -> word, tasks -> task, files -> file, users -> user
            if isCandidateEnglishBaseValid(String(word.dropLast(1))) {
                return true
            }
        }

        // 2. Past tense and past participle (-ed, -ied)
        if word.hasSuffix("ed"), word.count >= 4 {
            if word.hasSuffix("ied"), word.count >= 5 {
                // e.g. copied -> copy, tried -> try, modified -> modify
                if isCandidateEnglishBaseValid(String(word.dropLast(3)) + "y") { return true }
                if isCandidateEnglishBaseValid(String(word.dropLast(1))) { return true }
            }
            // e.g. removed -> remove, changed -> change, typed -> type, used -> use
            if isCandidateEnglishBaseValid(String(word.dropLast(1))) { return true }
            // e.g. worked -> work, checked -> check, started -> start, asked -> ask
            if isCandidateEnglishBaseValid(String(word.dropLast(2))) { return true }
            // Double consonant + ed: e.g. stopped -> stop, planned -> plan, dropped -> drop
            let stem = String(word.dropLast(2))
            if stem.count >= 3, hasDoubleConsonantSuffix(stem) {
                if isCandidateEnglishBaseValid(String(stem.dropLast(1))) { return true }
            }
        }

        // 3. Present participle and gerund (-ing, -ying)
        if word.hasSuffix("ing"), word.count >= 5 {
            if word.hasSuffix("ying"), word.count == 5 {
                // e.g. dying -> die, lying -> lie, tying -> tie
                if isCandidateEnglishBaseValid(String(word.dropLast(4)) + "ie") { return true }
            }
            // e.g. working -> work, checking -> check, starting -> start
            if isCandidateEnglishBaseValid(String(word.dropLast(3))) { return true }
            // e.g. removing -> remove, changing -> change, typing -> type, using -> use
            if isCandidateEnglishBaseValid(String(word.dropLast(3)) + "e") { return true }
            // Double consonant + ing: e.g. stopping -> stop, running -> run, getting -> get, setting -> set
            let stem = String(word.dropLast(3))
            if stem.count >= 3, hasDoubleConsonantSuffix(stem) {
                if isCandidateEnglishBaseValid(String(stem.dropLast(1))) { return true }
            }
        }

        // 4. Adverbs (-ly, -ily, -ally)
        if word.hasSuffix("ly"), word.count >= 4 {
            if word.hasSuffix("ily"), word.count >= 5 {
                // e.g. easily -> easy, happily -> happy
                if isCandidateEnglishBaseValid(String(word.dropLast(3)) + "y") { return true }
            }
            if word.hasSuffix("ally"), word.count >= 6 {
                // e.g. basically -> basic, automatically -> automatic
                if isCandidateEnglishBaseValid(String(word.dropLast(4))) { return true }
            }
            // e.g. slowly -> slow, quickly -> quick, properly -> proper, clearly -> clear
            if isCandidateEnglishBaseValid(String(word.dropLast(2))) { return true }
            // e.g. truly -> true
            if isCandidateEnglishBaseValid(String(word.dropLast(2)) + "e") { return true }
        }

        // 5. Comparatives and superlatives (-er, -est)
        if word.hasSuffix("er"), word.count >= 4, !word.hasSuffix("eer") {
            if word.hasSuffix("ier"), word.count >= 5 {
                // e.g. easier -> easy, happier -> happy
                if isCandidateEnglishBaseValid(String(word.dropLast(3)) + "y") { return true }
            }
            // e.g. faster -> fast, longer -> long, harder -> hard
            if isCandidateEnglishBaseValid(String(word.dropLast(2))) { return true }
            // e.g. larger -> large, closer -> close, simpler -> simple
            if isCandidateEnglishBaseValid(String(word.dropLast(1))) { return true }
            // Double consonant + er: e.g. bigger -> big, hotter -> hot
            let stem = String(word.dropLast(2))
            if stem.count >= 3, hasDoubleConsonantSuffix(stem) {
                if isCandidateEnglishBaseValid(String(stem.dropLast(1))) { return true }
            }
        }

        if word.hasSuffix("est"), word.count >= 5 {
            if word.hasSuffix("iest"), word.count >= 6 {
                // e.g. easiest -> easy, happiest -> happy
                if isCandidateEnglishBaseValid(String(word.dropLast(4)) + "y") { return true }
            }
            // e.g. fastest -> fast, longest -> long
            if isCandidateEnglishBaseValid(String(word.dropLast(3))) { return true }
            // e.g. largest -> large, closest -> close
            if isCandidateEnglishBaseValid(String(word.dropLast(2))) { return true }
            // Double consonant + est: e.g. biggest -> big
            let stem = String(word.dropLast(3))
            if stem.count >= 3, hasDoubleConsonantSuffix(stem) {
                if isCandidateEnglishBaseValid(String(stem.dropLast(1))) { return true }
            }
        }

        return false
    }

    private func isCandidateEnglishBaseValid(_ base: String) -> Bool {
        guard base.count >= 2 else { return false }
        if SuggestionEngine.shortWords[.english]?.contains(base) == true {
            return true
        }
        if WordValidator.whitelistedWords[.english]?.contains(base) == true {
            return true
        }
        return loader.containsExact(base, language: .english)
    }

    private func hasDoubleConsonantSuffix(_ text: String) -> Bool {
        guard text.count >= 2 else { return false }
        let last = text.suffix(1)
        let secondLast = text.dropLast(1).suffix(1)
        guard last == secondLast, let char = last.first else { return false }
        return "bdfglmnprstz".contains(char)
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

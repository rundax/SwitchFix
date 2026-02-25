import Foundation

public class WordValidator {
    private let loader = DictionaryLoader.shared

    public static let shared = WordValidator()

    private init() {}

    public struct ValidationResult {
        public let isValid: Bool
        public let correctedWord: String?
    }

    private static let shortWords: [Language: Set<String>] = [
        .english: [
            "a", "i", "an", "am", "is", "it", "to", "of", "in", "on", "at", "as", "by",
            "we", "he", "me", "my", "do", "if", "or", "no", "so", "us", "be", "go", "up"
        ],
        .ukrainian: [
            "в", "у", "і", "й", "та", "не", "на", "до", "за", "з", "із", "це", "я", "ми", "ти", "ви",
            "як", "чи", "що", "де", "бо", "то", "ті", "її", "їх", "ще", "ні"
        ],
        .russian: [
            "в", "и", "я", "мы", "ты", "он", "она", "не", "на", "до", "за", "из", "это"
        ],
    ]

    private static let englishContractionSuffixes: [String] = [
        "'s", "'re", "'ve", "'ll", "'d", "n't"
    ]

    private static let latinLowercaseRange: ClosedRange<UInt32> = 0x0061...0x007A
    private static let latinUppercaseRange: ClosedRange<UInt32> = 0x0041...0x005A
    private static let cyrillicRange: ClosedRange<UInt32> = 0x0400...0x052F

    private static let englishVowels = CharacterSet(charactersIn: "aeiouy")
    private static let englishCoreVowels = CharacterSet(charactersIn: "aeiou")
    private static let ukrainianVowels = CharacterSet(charactersIn: "аеєиіїоуюя")
    private static let russianVowels = CharacterSet(charactersIn: "аеёиоуыэюя")

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
            let ok = WordValidator.shortWords[language]?.contains(normalized) ?? false
            if ok {
                return ValidationResult(isValid: true, correctedWord: nil)
            }

            if allowSuggestion {
                if let best = closestShortWord(to: normalized, language: language) {
                    return ValidationResult(isValid: true, correctedWord: best)
                }
            }

            return ValidationResult(isValid: false, correctedWord: nil)
        }

        let filter = loader.bloomFilter(for: language)
        if filter.mightContain(normalized) {
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

        if let best = dictionarySuggestion(for: normalized, language: language),
           isSuggestionAcceptable(original: normalized, suggestion: best) {
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

    /// Patterns that should not be treated as words.
    private func shouldSkip(_ word: String) -> Bool {
        let lower = word.lowercased()

        // Pure numbers
        if lower.allSatisfy({ $0.isNumber }) {
            return true
        }

        // URLs
        if lower.hasPrefix("http") || lower.hasPrefix("www.") || lower.hasPrefix("ftp") {
            return true
        }

        // Email-like patterns
        if lower.contains("@") && lower.contains(".") {
            return true
        }

        // camelCase or PascalCase (has internal uppercase)
        let chars = Array(word)
        if chars.count > 1 {
            for i in 1..<chars.count {
                if chars[i].isUppercase && chars[i-1].isLowercase {
                    return true
                }
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
        guard let first = word.first else { return false }
        let buckets = loader.suggestionBuckets(for: language)
        guard let byLength = buckets[first],
              let words = byLength[word.count] else {
            return false
        }
        return words.contains(word)
    }

    private func containsVowel(_ word: String, language: Language) -> Bool {
        let lower = word.lowercased()
        let vowels: CharacterSet
        switch language {
        case .english:
            vowels = WordValidator.englishVowels
        case .ukrainian:
            vowels = WordValidator.ukrainianVowels
        case .russian:
            vowels = WordValidator.russianVowels
        }

        for scalar in lower.unicodeScalars where vowels.contains(scalar) {
            return true
        }
        return false
    }

    private func containsCoreEnglishVowel(_ word: String) -> Bool {
        for scalar in word.lowercased().unicodeScalars where WordValidator.englishCoreVowels.contains(scalar) {
            return true
        }
        return false
    }

    private func isSuggestionAcceptable(original: String, suggestion: String) -> Bool {
        let o = original.lowercased()
        let s = suggestion.lowercased()
        if o == s { return true }
        if s.count <= 1 { return false }
        if abs(o.count - s.count) > 1 { return false }
        return damerauLevenshteinDistance(o, s, maxDistance: 2) <= 2
    }

    private func isEnglishContractionValid(_ word: String) -> Bool {
        guard word.contains("'") else { return false }
        for suffix in WordValidator.englishContractionSuffixes where word.hasSuffix(suffix) {
            let base = String(word.dropLast(suffix.count))
            if base.isEmpty { continue }
            if base.hasSuffix("'") { continue }
            if WordValidator.shortWords[.english]?.contains(base) == true {
                return true
            }
            if loader.bloomFilter(for: .english).mightContain(base) {
                return true
            }
        }
        return false
    }

    private func closestShortWord(to word: String, language: Language) -> String? {
        guard let candidates = WordValidator.shortWords[language] else { return nil }
        var matches: [String] = []
        for candidate in candidates where candidate.count == word.count {
            var diff = 0
            for (a, b) in zip(word, candidate) {
                if a != b {
                    diff += 1
                    if diff > 1 { break }
                }
            }
            if diff <= 1 {
                matches.append(candidate)
                continue
            }

            let dist = damerauLevenshteinDistance(word, candidate, maxDistance: 1)
            if dist <= 1 {
                matches.append(candidate)
            }
        }
        if matches.count == 1 {
            return matches[0]
        }
        if let first = word.first {
            let firstMatches = matches.filter { $0.first == first }
            if firstMatches.count == 1 {
                return firstMatches[0]
            }
        }
        if let last = word.last {
            let lastMatches = matches.filter { $0.last == last }
            if lastMatches.count == 1 {
                return lastMatches[0]
            }
        }
        return nil
    }

    private func dictionarySuggestion(for word: String, language: Language) -> String? {
        guard let first = word.first else { return nil }
        let buckets = loader.suggestionBuckets(for: language)
        guard let lengthMap = buckets[first] else { return nil }

        var best: String? = nil
        var bestScore = Int.max
        let minLen = max(1, word.count - 1)
        let maxLen = word.count + 2

        for len in minLen...maxLen {
            guard let candidates = lengthMap[len] else { continue }
            for candidate in candidates {
                let dist = damerauLevenshteinDistance(word, candidate, maxDistance: 2)
                guard dist <= 2 else { continue }
                let lengthPenalty = abs(candidate.count - word.count)
                let score = dist * 10 + lengthPenalty

                if score < bestScore {
                    bestScore = score
                    best = candidate
                    if dist == 0 && lengthPenalty == 0 { return best }
                }
            }
        }

        return best
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

    /// Damerau-Levenshtein distance with early exit.
    private func damerauLevenshteinDistance(_ a: String, _ b: String, maxDistance: Int) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let n = aChars.count
        let m = bChars.count

        if abs(n - m) > maxDistance { return maxDistance + 1 }
        if n == 0 { return m }
        if m == 0 { return n }

        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }

        var minRow = 0
        for i in 1...n {
            minRow = maxDistance + 1
            for j in 1...m {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                var value = min(
                    dp[i - 1][j] + 1,        // deletion
                    dp[i][j - 1] + 1,        // insertion
                    dp[i - 1][j - 1] + cost  // substitution
                )
                if i > 1 && j > 1 && aChars[i - 1] == bChars[j - 2] && aChars[i - 2] == bChars[j - 1] {
                    value = min(value, dp[i - 2][j - 2] + 1) // transposition
                }
                dp[i][j] = value
                if value < minRow { minRow = value }
            }
            if minRow > maxDistance { return maxDistance + 1 }
        }
        return dp[n][m]
    }

}

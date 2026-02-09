import Foundation

public class WordValidator {
    private let loader = DictionaryLoader.shared

    public static let shared = WordValidator()

    private init() {}

    /// Check if a word is valid in the given language.
    /// Returns true if the word is likely in the dictionary (may have false positives from BloomFilter).
    public func isValidWord(_ word: String, language: Language) -> Bool {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Short words (≤ 2 chars) produce too many false positives
        if normalized.count <= 2 {
            return false
        }

        // Skip common non-word patterns
        if shouldSkip(normalized) {
            return false
        }

        let filter = loader.bloomFilter(for: language)
        return filter.mightContain(normalized)
    }

    /// Patterns that should not be treated as words.
    private func shouldSkip(_ word: String) -> Bool {
        // Pure numbers
        if word.allSatisfy({ $0.isNumber }) {
            return true
        }

        // URLs
        if word.hasPrefix("http") || word.hasPrefix("www.") || word.hasPrefix("ftp") {
            return true
        }

        // Email-like patterns
        if word.contains("@") && word.contains(".") {
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
}

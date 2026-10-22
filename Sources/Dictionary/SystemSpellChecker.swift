import AppKit

/// Spike (plan 05): word membership answered by the spell-checking dictionaries macOS ships
/// offline, instead of a bundled word list.
public final class SystemSpellChecker {
    public enum CasePolicy: String {
        /// Only the word as SwitchFix normalizes it (lowercase).
        case lowercase
        /// Also the capitalized form: German nouns are rejected in lowercase.
        case lowercaseOrCapitalized
    }

    public static let shared = SystemSpellChecker()

    // NSSpellChecker documents no thread-safety guarantee; the spike measures it separately.
    private let lock = NSLock()

    public var casePolicy: CasePolicy = .lowercaseOrCapitalized
    /// Words the user taught macOS ("Learn Spelling") are accepted by the checker on this Mac
    /// only. Excluding them keeps results reproducible.
    public var excludesLearnedWords = true

    private init() {}

    public static var availableLanguages: [String] {
        NSSpellChecker.shared.availableLanguages
    }

    public static func languageCode(for language: Language) -> String {
        switch language {
        case .english: return "en"
        case .ukrainian: return "uk"
        case .russian: return "ru"
        }
    }

    public func isValid(_ word: String, language: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return Self.unsynchronizedIsValid(
            word,
            language: language,
            casePolicy: casePolicy,
            excludesLearnedWords: excludesLearnedWords
        )
    }

    /// No locking: used by the spike's thread-safety measurement only.
    public static func unsynchronizedIsValid(
        _ word: String,
        language: String,
        casePolicy: CasePolicy,
        excludesLearnedWords: Bool
    ) -> Bool {
        // The checker splits text into words and ignores punctuation, so "ye," would pass as
        // "ye". Bundled dictionaries only ever contain single words; require the same here.
        guard isSingleWord(word) else { return false }
        let checker = NSSpellChecker.shared
        if excludesLearnedWords, checker.hasLearnedWord(word) {
            return false
        }
        if isCorrectlySpelled(word, language: language, checker: checker) {
            return true
        }
        guard casePolicy == .lowercaseOrCapitalized else { return false }
        let capitalized = word.prefix(1).uppercased() + word.dropFirst()
        guard capitalized != word else { return false }
        if excludesLearnedWords, checker.hasLearnedWord(capitalized) {
            return false
        }
        return isCorrectlySpelled(capitalized, language: language, checker: checker)
    }

    private static let wordCharacters = CharacterSet.letters.union(CharacterSet(charactersIn: "'-"))

    static func isSingleWord(_ word: String) -> Bool {
        guard let first = word.unicodeScalars.first, let last = word.unicodeScalars.last,
              CharacterSet.letters.contains(first), CharacterSet.letters.contains(last) else {
            return false
        }
        return word.unicodeScalars.allSatisfy { wordCharacters.contains($0) }
    }

    private static func isCorrectlySpelled(_ word: String, language: String, checker: NSSpellChecker) -> Bool {
        let misspelled = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return misspelled.location == NSNotFound
    }
}

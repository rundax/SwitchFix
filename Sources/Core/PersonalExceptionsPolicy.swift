import Foundation

public enum ExceptionValidationError: Error, Equatable, Sendable {
    case empty
    case tooLong(Int)
    case byteLimitExceeded(Int)
    case noLetters
    case invalidCharacter(Character)
    case invalidPunctuationPosition
    case capacityExceeded
    case duplicate

    public var localizedDescription: String {
        switch self {
        case .empty:
            return "Word cannot be empty."
        case .tooLong(let count):
            return "Word exceeds 64 characters (\(count))."
        case .byteLimitExceeded(let bytes):
            return "Word exceeds 256 bytes (\(bytes))."
        case .noLetters:
            return "Word must contain at least one letter."
        case .invalidCharacter(let char):
            return "Invalid character: '\(char)'."
        case .invalidPunctuationPosition:
            return "Punctuation cannot be at the start, end, or adjacent to other punctuation."
        case .capacityExceeded:
            return "Maximum exception list capacity (1,000 words) reached."
        case .duplicate:
            return "Already in the list."
        }
    }
}

public struct PersonalExceptionsPolicy: Equatable, Sendable {
    public static let maxEntries = 1_000
    public static let maxCharacters = 64
    public static let maxBytes = 256

    public let words: Set<String>

    public init(words: Set<String> = []) {
        self.words = words
    }

    public static let empty = PersonalExceptionsPolicy(words: [])

    public var isEmpty: Bool {
        return words.isEmpty
    }

    public var count: Int {
        return words.count
    }

    public func contains(_ canonicalWord: String) -> Bool {
        return words.contains(canonicalWord)
    }

    public func matches(rawToken: String) -> Bool {
        guard !words.isEmpty else { return false }
        guard let key = PersonalExceptionsPolicy.deriveMatchingKey(from: rawToken) else {
            return false
        }
        return words.contains(key)
    }

    /// Canonicalization per contract:
    /// 1. NFC normalization
    /// 2. Locale-independent lowercased
    /// 3. Replacement of U+2019 (’) and U+02BC (ʼ) with ASCII apostrophe (')
    /// 4. NFC normalization again
    public static func canonicalize(_ text: String) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        let lower = nfc.lowercased()
        var substituted = ""
        for scalar in lower.unicodeScalars {
            if scalar.value == 0x2019 || scalar.value == 0x02BC {
                substituted.append("'")
            } else {
                substituted.append(String(scalar))
            }
        }
        return substituted.precomposedStringWithCanonicalMapping
    }

    /// Validation per contract:
    /// - 1–64 Characters and <= 256 UTF-8 bytes after normalization
    /// - At least one Unicode letter
    /// - Allowed: letters, combining marks, ASCII digits, internal (', `, -)
    /// - Punctuation may not be first, last, or adjacent to another punctuation
    /// - Rejects whitespace, controls, format chars, emoji, paths, URLs, multiple tokens
    public static func validate(candidate: String) -> Result<String, ExceptionValidationError> {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .failure(.empty)
        }

        let canonical = canonicalize(trimmed)
        if canonical.isEmpty {
            return .failure(.empty)
        }

        if canonical.count > maxCharacters {
            return .failure(.tooLong(canonical.count))
        }

        if canonical.utf8.count > maxBytes {
            return .failure(.byteLimitExceeded(canonical.utf8.count))
        }

        var hasLetter = false
        let allowedPunctuation: Set<UnicodeScalar> = ["'", "`", "-"]

        let scalars = Array(canonical.unicodeScalars)
        for scalar in scalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                hasLetter = true
                continue
            case .nonspacingMark, .spacingMark, .enclosingMark:
                // Combining marks are allowed but do not count as a letter.
                continue
            default:
                break
            }
            if scalar.value >= 0x30 && scalar.value <= 0x39 {
                // ASCII digits allowed
            } else if allowedPunctuation.contains(scalar) {
                // Allowed internal punctuation
            } else {
                return .failure(.invalidCharacter(Character(scalar)))
            }
        }

        guard hasLetter else {
            return .failure(.noLetters)
        }

        // Combining marks may not appear standalone at the start of a word
        if let first = scalars.first {
            switch first.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                return .failure(.invalidCharacter(Character(first)))
            default:
                break
            }
        }

        // Punctuation positioning check:
        // May not be first, last, or adjacent to another punctuation character
        if let first = scalars.first, allowedPunctuation.contains(first) {
            return .failure(.invalidPunctuationPosition)
        }
        if let last = scalars.last, allowedPunctuation.contains(last) {
            return .failure(.invalidPunctuationPosition)
        }

        for i in 0..<(scalars.count - 1) {
            if allowedPunctuation.contains(scalars[i]) && allowedPunctuation.contains(scalars[i + 1]) {
                return .failure(.invalidPunctuationPosition)
            }
        }

        // The stored canonical entry must match its own derived key so it is always reachable
        guard let matchingKey = deriveMatchingKey(from: canonical), matchingKey == canonical else {
            return .failure(.invalidCharacter(canonical.first ?? " "))
        }

        return .success(canonical)
    }

    /// Derive the matching key from a raw captured token with the detector's own tokenizers:
    /// 1. Take the token after `splitTrailingBoundary`
    /// 2. Drop the leading and trailing non-letter, non-digit characters (`splitTokenForValidation`)
    /// 3. Canonicalize
    public static func deriveMatchingKey(from text: String) -> String? {
        let core = LayoutDetector.splitTrailingBoundary(from: text).core
        let stripped = LayoutDetector.splitTokenForValidation(core).core
        guard !stripped.isEmpty else { return nil }
        let canonical = canonicalize(stripped)
        return canonical.isEmpty ? nil : canonical
    }
}

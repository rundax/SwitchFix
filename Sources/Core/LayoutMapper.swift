import Foundation

public enum UkrainianKeyboardVariant: String, Sendable {
    case standard
    case legacy
}

public enum Layout: String, CaseIterable, Equatable, Sendable {
    case english
    case ukrainian
    case russian

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .ukrainian: return "Ukrainian"
        case .russian: return "Russian"
        }
    }

    public var isCyrillic: Bool {
        switch self {
        case .ukrainian, .russian: return true
        case .english: return false
        }
    }

    /// The primary macOS input source identifier for this layout.
    public var inputSourceID: String {
        return inputSourceIDs[0]
    }

    /// All known macOS input source identifiers that map to this layout.
    public var inputSourceIDs: [String] {
        switch self {
        case .english: return [
            "keylayout.US",
            "keylayout.USExtended",
            "keylayout.ABC",
            "keylayout.British",
            "keylayout.USInternational-PC",
            "keylayout.Colemak",
            "keylayout.Dvorak",
        ]
        case .ukrainian: return [
            "keylayout.Ukrainian",
            "keylayout.Ukrainian-PC",
        ]
        case .russian: return [
            "keylayout.Russian",
            "keylayout.RussianWin",
            "keylayout.Russian-Phonetic",
        ]
        }
    }

    /// Check if a given input source ID matches this layout.
    public func matches(sourceID: String) -> Bool {
        return inputSourceIDs.contains(where: { sourceID.hasSuffix($0) })
    }
}

public class LayoutMapper {

    // MARK: - Mapping tables

    // EN (QWERTY) → RU (ЙЦУКЕН) — standard macOS Russian layout
    private static let enToRu: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ъ", "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
        "l": "д", ";": "ж", "'": "э", "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", ".": "ю", "/": ".",
        // Uppercase
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ъ", "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л",
        "L": "Д", ":": "Ж", "\"": "Э", "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь",
        "<": "Б", ">": "Ю", "?": ",",
        "`": "ё", "~": "Ё",
    ]

    // EN (QWERTY) → UK (Ukrainian) — modern macOS Ukrainian layout
    private static let enToUkStandard: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ї", "a": "ф", "s": "і", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
        "l": "д", ";": "ж", "'": "є", "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", ".": "ю", "/": ".",
        // Uppercase
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ї", "A": "Ф", "S": "І", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л",
        "L": "Д", ":": "Ж", "\"": "Є", "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь",
        "<": "Б", ">": "Ю", "?": ",",
        "`": "ґ", "~": "Ґ",
    ]

    // EN (QWERTY) → UK (Ukrainian Legacy) — swaps positions of и/і.
    private static let enToUkLegacy: [Character: Character] = {
        var map = enToUkStandard
        map["s"] = "и"
        map["b"] = "і"
        map["S"] = "И"
        map["B"] = "І"
        return map
    }()

    // Pre-built reverse mappings
    private static let ruToEn: [Character: Character] = buildReverse(enToRu)
    private static let ukStandardToEn: [Character: Character] = buildReverse(enToUkStandard)
    private static let ukLegacyToEn: [Character: Character] = buildReverse(enToUkLegacy)

    private static func buildReverse(_ map: [Character: Character]) -> [Character: Character] {
        var result = [Character: Character]()
        for (k, v) in map {
            result[v] = k
        }
        return result
    }

    /// Get the mapping table for converting from one layout to another.
    private static func mappingTable(
        from: Layout,
        to: Layout,
        ukrainianFromVariant: UkrainianKeyboardVariant,
        ukrainianToVariant: UkrainianKeyboardVariant
    ) -> [Character: Character]? {
        switch (from, to) {
        case (.english, .russian):   return enToRu
        case (.english, .ukrainian):
            return ukrainianToVariant == .legacy ? enToUkLegacy : enToUkStandard
        case (.russian, .english):   return ruToEn
        case (.ukrainian, .english):
            return ukrainianFromVariant == .legacy ? ukLegacyToEn : ukStandardToEn
        // Cyrillic ↔ Cyrillic (Ukrainian ↔ Russian) conversion is intentionally unsupported.
        default: return nil
        }
    }

    /// Convert text from one layout to another.
    /// Characters without a mapping are left as-is.
    public static func convert(_ text: String, from: Layout, to: Layout) -> String {
        return convert(
            text,
            from: from,
            to: to,
            ukrainianFromVariant: .standard,
            ukrainianToVariant: .standard
        )
    }

    /// Convert text from one layout to another with explicit Ukrainian variant selection.
    public static func convert(
        _ text: String,
        from: Layout,
        to: Layout,
        ukrainianFromVariant: UkrainianKeyboardVariant,
        ukrainianToVariant: UkrainianKeyboardVariant
    ) -> String {
        guard from != to,
              let table = mappingTable(
                from: from,
                to: to,
                ukrainianFromVariant: ukrainianFromVariant,
                ukrainianToVariant: ukrainianToVariant
              ) else {
            return text
        }
        return String(text.map { table[$0] ?? $0 })
    }

    /// Try converting text from the given layout to all other layouts,
    /// returning each (Layout, convertedText) pair.
    public static func convertToAlternatives(_ text: String, from: Layout) -> [(Layout, String)] {
        return convertToAlternatives(
            text,
            from: from,
            ukrainianFromVariant: .standard,
            ukrainianToVariant: .standard
        )
    }

    /// Try converting text to all alternative layouts with explicit Ukrainian variant selection.
    public static func convertToAlternatives(
        _ text: String,
        from: Layout,
        ukrainianFromVariant: UkrainianKeyboardVariant,
        ukrainianToVariant: UkrainianKeyboardVariant
    ) -> [(Layout, String)] {
        var results = [(Layout, String)]()
        for target in Layout.allCases where target != from {
            let converted = convert(
                text,
                from: from,
                to: target,
                ukrainianFromVariant: ukrainianFromVariant,
                ukrainianToVariant: ukrainianToVariant
            )
            if converted != text {
                results.append((target, converted))
            }
        }
        return results
    }

    /// Whether `target` may be used when correcting text typed on `source`.
    /// Only Cyrillic ↔ Latin conversions are allowed. Latin text maps to exactly one Cyrillic
    /// layout: `currentCyrillic` when the user is on a Cyrillic layout (plus the other Cyrillic
    /// layouts of a hybrid active source), otherwise `preferredCyrillic`; with no history every
    /// allowed Cyrillic layout is eligible.
    public static func isEligibleTarget(
        _ target: Layout,
        source: Layout,
        allowed: Set<Layout>,
        current: Layout,
        activeSourceSupported: Set<Layout>,
        preferredCyrillic: Layout?
    ) -> Bool {
        guard allowed.contains(target) else { return false }
        guard target.isCyrillic else { return true }
        if source.isCyrillic { return false }
        if current.isCyrillic {
            if target == current { return true }
            return activeSourceSupported.contains(current) && activeSourceSupported.contains(target)
        }
        guard let preferred = preferredCyrillic, allowed.contains(preferred) else { return true }
        return target == preferred
    }
}

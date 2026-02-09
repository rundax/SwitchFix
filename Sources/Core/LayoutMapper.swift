import Foundation

public enum Layout: String, CaseIterable, Equatable {
    case english
    case ukrainian
    case russian

    /// The macOS input source identifier for this layout.
    public var inputSourceID: String {
        switch self {
        case .english: return "com.apple.keylayout.US"
        case .ukrainian: return "com.apple.keylayout.Ukrainian"
        case .russian: return "com.apple.keylayout.Russian"
        }
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

    // EN (QWERTY) → UK (Ukrainian) — standard macOS Ukrainian layout
    private static let enToUk: [Character: Character] = [
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

    // RU → UK mapping for characters that differ between Russian and Ukrainian layouts
    private static let ruToUk: [Character: Character] = [
        "ы": "і", "э": "є", "ъ": "ї", "ё": "ґ",
        "Ы": "І", "Э": "Є", "Ъ": "Ї", "Ё": "Ґ",
    ]

    // Pre-built reverse mappings
    private static let ruToEn: [Character: Character] = buildReverse(enToRu)
    private static let ukToEn: [Character: Character] = buildReverse(enToUk)
    private static let ukToRu: [Character: Character] = buildReverse(ruToUk)

    private static func buildReverse(_ map: [Character: Character]) -> [Character: Character] {
        var result = [Character: Character]()
        for (k, v) in map {
            result[v] = k
        }
        return result
    }

    /// Get the mapping table for converting from one layout to another.
    private static func mappingTable(from: Layout, to: Layout) -> [Character: Character]? {
        switch (from, to) {
        case (.english, .russian):   return enToRu
        case (.english, .ukrainian): return enToUk
        case (.russian, .english):   return ruToEn
        case (.ukrainian, .english): return ukToEn
        case (.russian, .ukrainian): return ruToUk
        case (.ukrainian, .russian): return ukToRu
        default: return nil
        }
    }

    /// Convert text from one layout to another.
    /// Characters without a mapping are left as-is.
    public static func convert(_ text: String, from: Layout, to: Layout) -> String {
        guard from != to, let table = mappingTable(from: from, to: to) else {
            return text
        }
        return String(text.map { table[$0] ?? $0 })
    }

    /// Try converting text from the given layout to all other layouts,
    /// returning each (Layout, convertedText) pair.
    public static func convertToAlternatives(_ text: String, from: Layout) -> [(Layout, String)] {
        var results = [(Layout, String)]()
        for target in Layout.allCases where target != from {
            let converted = convert(text, from: from, to: target)
            if converted != text {
                results.append((target, converted))
            }
        }
        return results
    }
}

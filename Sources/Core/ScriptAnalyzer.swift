import Foundation

public enum ScriptKind {
    case latin
    case cyrillic
    case mixed
    case unknown
}

public struct ScriptAnalyzer {
    public static let latinLowercaseRange: ClosedRange<UInt32> = 0x0061...0x007A
    public static let latinUppercaseRange: ClosedRange<UInt32> = 0x0041...0x005A
    public static let cyrillicRange: ClosedRange<UInt32> = 0x0400...0x052F

    /// Check if a string contains both Latin and Cyrillic characters.
    public static func containsMixedScripts(_ text: String) -> Bool {
        var hasLatin = false
        var hasCyrillic = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (value >= 0x0041 && value <= 0x007A) || (value >= 0x0061 && value <= 0x007A) { // Quick basic latin check (A-Z, a-z)
                hasLatin = true
            } else if (value >= 0x0400 && value <= 0x04FF) {
                hasCyrillic = true
            }
            if hasLatin && hasCyrillic { return true }
        }
        return false
    }

    public static func scriptKind(for text: String) -> ScriptKind {
        var hasLatin = false
        var hasCyrillic = false

        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            let value = scalar.value
            if latinLowercaseRange.contains(value) || latinUppercaseRange.contains(value) {
                hasLatin = true
            } else if cyrillicRange.contains(value) {
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

    public static func inferCyrillicLayout(for word: String, allowedLayouts: Set<Layout>) -> Layout? {
        let hasUkrainian = allowedLayouts.contains(.ukrainian)
        let hasRussian = allowedLayouts.contains(.russian)
        
        var isUk = false
        var isRu = false
        
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x0456, 0x0406, // і, І
                 0x0457, 0x0407, // ї, Ї
                 0x0454, 0x0404, // є, Є
                 0x0491, 0x0490: // ґ, Ґ
                isUk = true
            case 0x044B, 0x042B, // ы, Ы
                 0x044D, 0x042D, // э, Э
                 0x0451, 0x0401, // ё, Ё
                 0x044A, 0x042A: // ъ, Ъ
                isRu = true
            default: break
            }
        }

        if isUk && hasUkrainian { return .ukrainian }
        if isRu && hasRussian { return .russian }

        if hasUkrainian && !hasRussian { return .ukrainian }
        if hasRussian && !hasUkrainian { return .russian }
        if hasUkrainian { return .ukrainian }
        if hasRussian { return .russian }
        return nil
    }

    public static func resolvedSourceLayout(for word: String, currentLayout: Layout, allowedLayouts: Set<Layout>) -> Layout {
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
            return inferCyrillicLayout(for: word, allowedLayouts: allowedLayouts) ?? currentLayout
        case .mixed, .unknown:
            return currentLayout
        }
    }
}

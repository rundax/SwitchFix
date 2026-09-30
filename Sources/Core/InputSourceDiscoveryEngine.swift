import Foundation

public struct InputSourceDiscoveryEngine {
    public static func classify(provider: InputSourcePropertyProviding) -> DiscoveredInputSourceDescriptor? {
        if let type = provider.inputSourceType,
           type != "TISTypeKeyboardLayout" {
            return nil
        }

        var layouts = Set<Layout>()

        // Tier 1: ISO Languages from kTISPropertyInputSourceLanguages
        if let languages = provider.languages {
            for lang in languages {
                let code = lang.prefix(2).lowercased()
                if code == "uk" { layouts.insert(.ukrainian) }
                if code == "ru" { layouts.insert(.russian) }
                if code == "en" { layouts.insert(.english) }
            }
        }

        // Tier 2: Token & Name Heuristics
        let normalized = (provider.id + " " + provider.localizedName).lowercased()
        if normalized.contains("ukrain") || normalized.contains("ukr") || normalized.contains("-ua") {
            layouts.insert(.ukrainian)
        }
        if normalized.contains("russian") || normalized.contains("rus") || normalized.contains("-ru") {
            layouts.insert(.russian)
        }
        if normalized.contains("birman") {
            // Birman layout variants natively support Russian and Ukrainian typography
            layouts.insert(.russian)
            layouts.insert(.ukrainian)
        }
        if normalized.contains("colemak") || normalized.contains("dvorak") || normalized.contains("workman") || normalized.contains("qwerty") {
            layouts.insert(.english)
        }
        for layout in Layout.allCases {
            if layout.matches(sourceID: provider.id) {
                layouts.insert(layout)
            }
        }

        // Tier 3: Dynamic UCKeyTranslate Probing (Unshifted + Option/AltGr)
        let keyA = provider.translatedCharacter(keyCode: 0, modifierKeyState: 0).map { String($0).lowercased() }
        let keyS = provider.translatedCharacter(keyCode: 1, modifierKeyState: 0).map { String($0).lowercased() }
        let keyQ = provider.translatedCharacter(keyCode: 12, modifierKeyState: 0).map { String($0).lowercased() }
        let keyCloseBracket = provider.translatedCharacter(keyCode: 30, modifierKeyState: 0).map { String($0).lowercased() }
        let keyQuote = provider.translatedCharacter(keyCode: 39, modifierKeyState: 0).map { String($0).lowercased() }

        if keyQ == "й" && keyA == "ф" {
            // Definitive Cyrillic ЙЦУКЕН layout
            if keyS == "і" || keyQuote == "є" || keyCloseBracket == "ї" {
                layouts.insert(.ukrainian)
            }
            if keyS == "ы" || keyQuote == "э" || keyCloseBracket == "ъ" {
                layouts.insert(.russian)
            }

            // Probe Option / AltGr state (modifierKeyState: 0x08)
            let optS = provider.translatedCharacter(keyCode: 1, modifierKeyState: 0x08).map { String($0).lowercased() }
            let optQuote = provider.translatedCharacter(keyCode: 39, modifierKeyState: 0x08).map { String($0).lowercased() }
            let optCloseBracket = provider.translatedCharacter(keyCode: 30, modifierKeyState: 0x08).map { String($0).lowercased() }
            let optG = provider.translatedCharacter(keyCode: 5, modifierKeyState: 0x08).map { String($0).lowercased() }

            if optS == "і" || optQuote == "є" || optCloseBracket == "ї" || optG == "ґ" {
                layouts.insert(.ukrainian)
            }
            if optS == "ы" || optQuote == "э" || optCloseBracket == "ъ" {
                layouts.insert(.russian)
            }

            if layouts.isEmpty {
                // Fallback for unidentified Cyrillic
                layouts.insert(.ukrainian)
                layouts.insert(.russian)
            }
        } else if keyQ == "q" || keyA == "a" {
            layouts.insert(.english)
        }

        guard !layouts.isEmpty else { return nil }

        var ukrainianVariant: UkrainianKeyboardVariant? = nil
        if layouts.contains(.ukrainian) {
            let keySChar = provider.translatedCharacter(keyCode: 1, modifierKeyState: 0).map { String($0).lowercased() }
            let keyBChar = provider.translatedCharacter(keyCode: 11, modifierKeyState: 0).map { String($0).lowercased() }
            if keySChar == "и", keyBChar == "і" {
                ukrainianVariant = .legacy
            } else if keySChar == "і", keyBChar == "и" {
                ukrainianVariant = .standard
            } else if provider.localizedName.lowercased().contains("legacy") {
                ukrainianVariant = .legacy
            } else {
                ukrainianVariant = .standard
            }
        }

        let isCustom = !Layout.allCases.contains(where: { $0.matches(sourceID: provider.id) })

        return DiscoveredInputSourceDescriptor(
            id: provider.id,
            name: provider.localizedName,
            supportedLayouts: layouts,
            ukrainianVariant: ukrainianVariant,
            isCustom: isCustom
        )
    }

    public static func discover(providers: [InputSourcePropertyProviding]) -> [DiscoveredInputSourceDescriptor] {
        providers.compactMap { classify(provider: $0) }
    }
}

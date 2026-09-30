import Foundation

public protocol InputSourcePropertyProviding {
    var id: String { get }
    var localizedName: String { get }
    var inputSourceType: String? { get }
    var languages: [String]? { get }
    func translatedCharacter(keyCode: UInt16, modifierKeyState: UInt32) -> Character?
}

public struct DiscoveredInputSourceDescriptor: Equatable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let supportedLayouts: Set<Layout>
    public let ukrainianVariant: UkrainianKeyboardVariant?
    public let isCustom: Bool

    public init(
        id: String,
        name: String,
        supportedLayouts: Set<Layout>,
        ukrainianVariant: UkrainianKeyboardVariant? = nil,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.supportedLayouts = supportedLayouts
        self.ukrainianVariant = ukrainianVariant
        self.isCustom = isCustom
    }
}

public struct MockInputSourcePropertyReader: InputSourcePropertyProviding {
    public let id: String
    public let localizedName: String
    public let inputSourceType: String?
    public let languages: [String]?
    public var keyTranslations: [UInt32: [UInt16: Character]]

    public init(
        id: String,
        localizedName: String,
        inputSourceType: String? = "TISTypeKeyboardLayout",
        languages: [String]? = nil,
        keyTranslations: [UInt32: [UInt16: Character]] = [:]
    ) {
        self.id = id
        self.localizedName = localizedName
        self.inputSourceType = inputSourceType
        self.languages = languages
        self.keyTranslations = keyTranslations
    }

    public init(
        id: String,
        localizedName: String,
        inputSourceType: String? = "TISTypeKeyboardLayout",
        languages: [String]? = nil,
        unshiftedKeys: [UInt16: Character] = [:],
        optionKeys: [UInt16: Character] = [:]
    ) {
        var translations: [UInt32: [UInt16: Character]] = [:]
        if !unshiftedKeys.isEmpty {
            translations[0] = unshiftedKeys
        }
        if !optionKeys.isEmpty {
            translations[0x08] = optionKeys
        }
        self.init(
            id: id,
            localizedName: localizedName,
            inputSourceType: inputSourceType,
            languages: languages,
            keyTranslations: translations
        )
    }

    public func translatedCharacter(keyCode: UInt16, modifierKeyState: UInt32) -> Character? {
        keyTranslations[modifierKeyState]?[keyCode]
    }
}

import Dictionary

public enum AutomaticDictionaryReadiness {
    @discardableResult
    public static func prepare(_ layout: Layout) -> Bool {
        let language: Language
        switch layout {
        case .english: language = .english
        case .ukrainian: language = .ukrainian
        case .russian: language = .russian
        }
        return DictionaryLoader.shared.prewarm(language: language)
    }
}

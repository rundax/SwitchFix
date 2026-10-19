import Foundation

public enum SeedCorpusDefinitions {
    public static let developmentItems: [SeedItemDefinition] = [
        // 20 Repairs (10 EN->UK, 10 UK->EN)
        SeedItemDefinition(groupID: "dev-grp-001", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "привіт ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-002", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "робота ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-003", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "людина ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-004", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "дякую ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-005", category: "capitalized", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "Київ ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-006", category: "back-to-back", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "добрий день ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-007", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "дивимось ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-008", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "чудово ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-009", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "правда ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-010", category: "question", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "як справи ", isRepair: true),

        SeedItemDefinition(groupID: "dev-grp-011", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "hello ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-012", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "world ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-013", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "system ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-014", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "window ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-015", category: "capitalized", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "London ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-016", category: "back-to-back", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "good morning ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-017", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "expected ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-018", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "thanks ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-019", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "project ", isRepair: true),
        SeedItemDefinition(groupID: "dev-grp-020", category: "question", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "how are you ", isRepair: true),

        // 60 Preserves (30 English, 30 Ukrainian)
        SeedItemDefinition(groupID: "dev-grp-021", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "apple ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-022", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "swift ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-023", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "developer ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-024", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "terminal ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-025", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "release ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-026", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "keyboard ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-027", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "the ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-028", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "and ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-029", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "for ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-030", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "not ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-031", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "but ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-032", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "yes ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-033", category: "proper-noun", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "GitHub ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-034", category: "proper-noun", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "Unix ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-035", category: "proper-noun", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "Xcode ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-036", category: "proper-noun", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "macOS ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-037", category: "code-token", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "camelCase ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-038", category: "code-token", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "snake_case ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-039", category: "code-token", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "kUCKeyActionDown ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-040", category: "code-token", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "init() ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-041", category: "path", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "/usr/local/bin ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-042", category: "filename", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "Package.swift ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-043", category: "url", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "https://apple.com ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-044", category: "email", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "dev@example.org ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-045", category: "acronym", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "HTTP ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-046", category: "acronym", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "JSON ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-047", category: "acronym", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "UUID ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-048", category: "contraction", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "don't ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-049", category: "contraction", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "it's ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-050", category: "punctuation", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "result = true; ", isRepair: false),

        SeedItemDefinition(groupID: "dev-grp-051", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "яблуко ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-052", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "ринок ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-053", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "розробник ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-054", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "термінал ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-055", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "реліз ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-056", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "система ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-057", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "це ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-058", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "і ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-059", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "на ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-060", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "до ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-061", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "та ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-062", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "ми ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-063", category: "proper-noun", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "Львів ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-064", category: "proper-noun", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "Тарас ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-065", category: "proper-noun", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "Шевченко ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-066", category: "proper-noun", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "Дніпро ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-067", category: "apostrophe", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "сім'я ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-068", category: "apostrophe", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "м'ясо ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-069", category: "apostrophe", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "в'язати ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-070", category: "apostrophe", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "комп'ютер ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-071", category: "acronym", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "НАТО ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-072", category: "acronym", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "ООН ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-073", category: "acronym", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "США ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-074", category: "acronym", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "НБУ ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-075", category: "punctuation", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "добре! ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-076", category: "punctuation", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "(так) ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-077", category: "punctuation", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "слово: ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-078", category: "symbol", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "100% ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-079", category: "phrase", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "добрий ранок ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-080", category: "phrase", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "гарного дня ", isRepair: false),

        // 20 Abstains (10 English, 10 Ukrainian)
        SeedItemDefinition(groupID: "dev-grp-081", category: "ambiguous-short", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "to ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-082", category: "ambiguous-short", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "me ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-083", category: "ambiguous-short", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "do ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-084", category: "ambiguous-short", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "no ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-085", category: "ambiguous-short", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "or ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-086", category: "gibberish", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "asdfghjk ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-087", category: "gibberish", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "qwertyuiop ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-088", category: "isolated-char", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "a ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-089", category: "isolated-char", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "x ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-090", category: "isolated-symbol", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: ": ", isRepair: false),

        SeedItemDefinition(groupID: "dev-grp-091", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "то ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-092", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "не ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-093", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "чи ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-094", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "за ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-095", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "як ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-096", category: "gibberish", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "йцукенгш ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-097", category: "gibberish", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "фівапрол ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-098", category: "isolated-char", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "я ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-099", category: "isolated-symbol", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "; ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-100", category: "symbol", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "--- ", isRepair: false)
    ]

    public static let holdoutItems: [SeedItemDefinition] = [
        // 20 Repairs (10 EN->UK, 10 UK->EN)
        SeedItemDefinition(groupID: "holdout-grp-001", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "мова ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-002", category: "capitalized", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "Україна ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-003", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "дякуємо ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-004", category: "back-to-back", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "новий день ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-005", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "користувач ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-006", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "документ ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-007", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "можливо ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-008", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "бачимо ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-009", category: "single-word", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "вечір ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-010", category: "question", label: "repair", sourceLayout: "en", targetLayout: "uk", intendedText: "де ти ", isRepair: true),

        SeedItemDefinition(groupID: "holdout-grp-011", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "apple ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-012", category: "capitalized", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "Canada ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-013", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "welcome ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-014", category: "back-to-back", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "new file ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-015", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "browser ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-016", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "document ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-017", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "perhaps ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-018", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "looking ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-019", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "evening ", isRepair: true),
        SeedItemDefinition(groupID: "holdout-grp-020", category: "question", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "where are you ", isRepair: true),

        // 60 Preserves (30 English, 30 Ukrainian)
        SeedItemDefinition(groupID: "holdout-grp-021", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "orange ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-022", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "python ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-023", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "architect ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-024", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "console ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-025", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "update ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-026", category: "natural-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "display ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-027", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "an ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-028", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "in ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-029", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "at ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-030", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "so ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-031", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "if ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-032", category: "short-word", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "up ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-033", category: "proper-noun", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "GitLab ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-034", category: "proper-noun", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "Linux ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-035", category: "proper-noun", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "VisualCode ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-036", category: "proper-noun", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "iOS ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-037", category: "code-token", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "pascalCase ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-038", category: "code-token", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "kebab_case ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-039", category: "code-token", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "CFRelease ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-040", category: "code-token", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "deinit() ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-041", category: "path", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "/etc/hosts ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-042", category: "filename", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "README.md ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-043", category: "url", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "https://swift.org ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-044", category: "email", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "info@company.com ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-045", category: "acronym", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "REST ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-046", category: "acronym", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "HTML ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-047", category: "acronym", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "RAM ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-048", category: "contraction", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "won't ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-049", category: "contraction", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "that's ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-050", category: "punctuation", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "status == 0; ", isRepair: false),

        SeedItemDefinition(groupID: "holdout-grp-051", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "апельсин ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-052", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "мова ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-053", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "архітектор ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-054", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "консоль ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-055", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "оновлення ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-056", category: "natural-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "екран ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-057", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "бо ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-058", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "чи ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-059", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "у ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-060", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "в ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-061", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "от ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-062", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "ну ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-063", category: "proper-noun", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "Одеса ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-064", category: "proper-noun", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "Франко ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-065", category: "proper-noun", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "Леся ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-066", category: "proper-noun", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "Харків ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-067", category: "apostrophe", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "м'який ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-068", category: "apostrophe", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "п'ять ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-069", category: "apostrophe", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "солов'їний ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-070", category: "apostrophe", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "під'їзд ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-071", category: "acronym", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "МВФ ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-072", category: "acronym", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "ЮНЕСКО ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-073", category: "acronym", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "ЄС ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-074", category: "acronym", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "ЗСУ ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-075", category: "punctuation", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "чудово! ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-076", category: "punctuation", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "(ні) ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-077", category: "punctuation", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "висновок: ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-078", category: "symbol", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "50% ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-079", category: "phrase", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "добрий вечір ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-080", category: "phrase", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "на все добре ", isRepair: false),

        // 20 Abstains (10 English, 10 Ukrainian)
        SeedItemDefinition(groupID: "holdout-grp-081", category: "ambiguous-short", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "am ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-082", category: "ambiguous-short", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "is ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-083", category: "ambiguous-short", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "us ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-084", category: "ambiguous-short", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "be ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-085", category: "ambiguous-short", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "he ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-086", category: "gibberish", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "zxcvbnm ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-087", category: "gibberish", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "lkjhgfdsa ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-088", category: "isolated-char", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "b ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-089", category: "isolated-char", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: "y ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-090", category: "isolated-symbol", label: "abstain", sourceLayout: "en", targetLayout: "en", intendedText: ", ", isRepair: false),

        SeedItemDefinition(groupID: "holdout-grp-091", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "би ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-092", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "же ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-093", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "от ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-094", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "ну ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-095", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "що ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-096", category: "gibberish", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "ячсмитьб ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-097", category: "gibberish", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "полдзячс ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-098", category: "isolated-char", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "і ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-099", category: "isolated-symbol", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: ", ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-100", category: "symbol", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "=== ", isRepair: false)
    ]
}

/// One frozen corpus version: its trials and the README written next to them.
public struct SeedCorpusVersion {
    public let version: String
    public let created: String
    public let generator: String
    public let developmentItems: [SeedItemDefinition]
    public let holdoutItems: [SeedItemDefinition]
    public let readme: (_ sourceCommit: String, _ summaries: [String: SplitSummary]) -> String
}

extension SeedCorpusDefinitions {
    public static func version(_ name: String) -> SeedCorpusVersion? {
        switch name {
        case "v1": return v1
        case "v2": return v2
        default: return nil
        }
    }

    static let v1 = SeedCorpusVersion(
        version: "v1",
        created: "2026-10-19",
        generator: "manual-v1",
        developmentItems: developmentItems,
        holdoutItems: holdoutItems,
        readme: { sourceCommit, _ in
            """
            # Layout Benchmark Corpus v1

            Version: 1.0 (Frozen Seed Baseline)
            Specification: `docs/plans/03-comparative-false-positive-benchmark.md`
            Source commit: `\(sourceCommit)`

            ## Overview

            This directory contains the frozen 200-trial seed corpus for the SwitchFix comparative layout reliability benchmark:
            - `development.jsonl`: 100 trials used during development and regression testing
            - `holdout.jsonl`: 100 trials reserved for generalization evaluation
            - `manifest.json`: Cryptographic integrity hashes and split distributions

            ## Split Structure (Per Split)

            Each split contains exactly 100 trials:
            - **20 Repair** trials: Intentional layout errors requiring automatic repair (10 English → Ukrainian, 10 Ukrainian → English)
            - **60 Preserve** trials: Intentional correct text requiring preservation with no modifications (30 typed under ABC, 30 typed under Ukrainian)
            - **20 Abstain** trials: Ambiguous or unsupported inputs requiring no automatic action (10 typed under ABC, 10 typed under Ukrainian)

            Base group IDs (`groupID`) are completely disjoint across the development and holdout splits.

            ## Trial Schema & Provenance

            Every row in the JSONL files is an independent JSON object:
            - `schemaVersion`: 1
            - `id`: Unique identifier across all splits
            - `groupID`: Base entity / sentence group (disjoint across splits)
            - `split`: `"development"` or `"holdout"`
            - `languages`: Array of relevant language codes (e.g. `["en", "uk"]`)
            - `category`: Strata label (e.g. `single-word`, `capitalized`, `code-token`, `acronym`, `ambiguous-short`, etc.)
            - `label`: Target behavior (`repair`, `preserve`, or `abstain`)
            - `provenance`: Synthetic generation metadata with `"review": "pending-human"`
            - `initial`: Starting editor state (sourceID, language, text, caretUTF16, preferredCyrillic, keyboardType)
            - `events`: Array of physical key and boundary events (keyCode, modifiers, rendered)
            - `expected`: Target outcome (text, language, sourceID, allowedAutomaticActions, checkpoints)

            ## Deterministic Rendering

            Events are rendered using the frozen layout tables in `Benchmarks/layout-tables/v1/`. The `rendered` field in each event is verified against the table output for the given keyCode and modifiers.
            """
        }
    )

    /// v1 trials whose typed input or base text leaked across splits or carried contradictory
    /// labels, keyed by their v1 position, with the replacement that keeps the stratum.
    static let v2HoldoutReplacements: [Int: SeedItemDefinition] = [
        11: SeedItemDefinition(groupID: "holdout-grp-011-v2", category: "single-word", label: "repair", sourceLayout: "uk", targetLayout: "en", intendedText: "garden ", isRepair: true, id: "holdout-repair-011-v2"),
        58: SeedItemDefinition(groupID: "holdout-grp-058-v2", category: "short-word", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "ще ", isRepair: false, id: "holdout-preserve-058-v2"),
        93: SeedItemDefinition(groupID: "holdout-grp-093-v2", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "аж ", isRepair: false, id: "holdout-abstain-093-v2"),
        94: SeedItemDefinition(groupID: "holdout-grp-094-v2", category: "ambiguous-short", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "хоч ", isRepair: false, id: "holdout-abstain-094-v2"),
        98: SeedItemDefinition(groupID: "holdout-grp-098-v2", category: "isolated-char", label: "abstain", sourceLayout: "uk", targetLayout: "uk", intendedText: "є ", isRepair: false, id: "holdout-abstain-098-v2")
    ]

    /// Intentional tokens that are also real words in the other layout (Apple "Ukrainian" is
    /// the legacy variant: s=и, b=і). Labels come from the intended text, not a dictionary.
    static let v2DevelopmentCollisions: [SeedItemDefinition] = [
        SeedItemDefinition(groupID: "dev-grp-101", category: "cross-layout-collision", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "vs ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-102", category: "cross-layout-collision", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "yt ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-103", category: "cross-layout-collision", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "nfr ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-104", category: "cross-layout-collision", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "uhf ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-105", category: "cross-layout-collision", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "hbr ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-106", category: "cross-layout-collision", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "руку ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-106", category: "cross-layout-collision", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "руки ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-106", category: "cross-layout-collision", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "рук ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-107", category: "cross-layout-collision", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "кум ", isRepair: false),
        SeedItemDefinition(groupID: "dev-grp-108", category: "cross-layout-collision", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "нут ", isRepair: false)
    ]

    static let v2HoldoutCollisions: [SeedItemDefinition] = [
        SeedItemDefinition(groupID: "holdout-grp-101", category: "cross-layout-collision", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "lev ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-102", category: "cross-layout-collision", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "ns ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-103", category: "cross-layout-collision", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "gap ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-104", category: "cross-layout-collision", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "ufc ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-105", category: "cross-layout-collision", label: "preserve", sourceLayout: "en", targetLayout: "en", intendedText: "dsl ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-101", category: "cross-layout-collision", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "дум ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-106", category: "cross-layout-collision", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "дути ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-106", category: "cross-layout-collision", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "дув ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-107", category: "cross-layout-collision", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "пуд ", isRepair: false),
        SeedItemDefinition(groupID: "holdout-grp-108", category: "cross-layout-collision", label: "preserve", sourceLayout: "uk", targetLayout: "uk", intendedText: "дну ", isRepair: false)
    ]

    static let v2 = SeedCorpusVersion(
        version: "v2",
        created: "2026-10-19",
        generator: "manual-v2",
        developmentItems: developmentItems + v2DevelopmentCollisions,
        holdoutItems: holdoutItems.enumerated().map { v2HoldoutReplacements[$0.offset + 1] ?? $0.element } + v2HoldoutCollisions,
        readme: { sourceCommit, summaries in
            let dev = summaries["development"]
            let holdout = summaries["holdout"]
            return """
            # Layout Benchmark Corpus v2

            Specification: `docs/plans/03-comparative-false-positive-benchmark.md`
            Source commit: `\(sourceCommit)`
            Generator: `LayoutBenchmark generate-seed-corpus --version v2` (byte-deterministic; regenerating reproduces the manifest hashes)

            v2 supersedes v1 as the regression corpus. v1 stays frozen and unchanged for reproducing its baselines.

            ## Changes from v1

            1. **Leaks and contradictory labels removed.** In v1 the identical typed inputs `і` and `чи` appeared in both splits with opposite labels (preserve vs abstain), `apple` was a development preserve and a holdout reversed-mapping repair, and holdout labeled `от` and `ну` both preserve and abstain. Five holdout trials are replaced, keeping their stratum, under new IDs: `holdout-repair-011-v2` (`garden`), `holdout-preserve-058-v2` (`ще`), `holdout-abstain-093-v2` (`аж`), `holdout-abstain-094-v2` (`хоч`), `holdout-abstain-098-v2` (`є`).
            2. **Hard negatives added.** v1 negatives were all typed on the correct layout and never collided with a word in the other language, so a zero false-positive rate said little. Category `cross-layout-collision` adds 10 `preserve` trials per split, 5 typed on ABC and 5 on Ukrainian, each an intended token whose rendering on the other layout is a real word (for example `vs` → `ми`, `руку` → `here`). Inflections of one lemma and reversed mappings share a group.
            3. **Validation is stricter.** `validate` reports identical typed input with different labels anywhere, and typed input or base text shared across splits; `--strict` fails on any of them. v1 validates with 9 such warnings, v2 with none. Validation also checks manifest hashes, caret offsets and exact keyboard-type tables.

            ## Split Structure

            - Development: \(dev?.total ?? 0) trials (\(dev?.repair ?? 0) repair, \(dev?.preserve ?? 0) preserve, \(dev?.abstain ?? 0) abstain)
            - Holdout: \(holdout?.total ?? 0) trials (\(holdout?.repair ?? 0) repair, \(holdout?.preserve ?? 0) preserve, \(holdout?.abstain ?? 0) abstain)

            Every label is divided equally between trials typed on ABC and on Ukrainian. All trials are synthetic, rendered through the frozen `Benchmarks/layout-tables/v1` tables, and carry `"review": "pending-human"`; human review results become a new corpus version.

            ## Known limits

            - The `abstain` stratum is short words, gibberish and symbols typed on the correct layout; it does not yet contain genuinely ambiguous wrong-layout input.
            - Hard negatives are few (20 in total) and correlated within groups; treat their rate as a regression signal, not a false-positive claim.

            The trial schema is unchanged from v1 (see `Benchmarks/layout-corpus/v1/README.md`).
            """
        }
    )
}

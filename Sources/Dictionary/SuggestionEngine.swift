import Foundation

public struct SuggestionEngine {
    public static let shortWords: [Language: Set<String>] = [
        .english: [
            "a", "i", "an", "am", "is", "it", "to", "of", "in", "on", "at", "as", "by",
            "we", "he", "me", "my", "do", "if", "or", "no", "so", "us", "be", "go", "up", "vs"
        ],
        .ukrainian: [
            "в", "у", "і", "й", "та", "не", "на", "до", "за", "з", "із", "це", "я", "ми", "ти", "ви",
            "як", "чи", "що", "де", "бо", "то", "ті", "її", "їх", "ще", "ні",
            "б", "би", "ж", "же", "по", "те", "ту", "їй", "їм", "ну", "от"
        ],
        .russian: [
            "в", "и", "я", "мы", "ты", "он", "она", "не", "на", "до", "за", "из", "это",
            "б", "бы", "ж", "же", "по", "от", "к", "с", "со", "у", "о", "об", "ли", "ни", "но", "то", "те", "ну", "да", "вы", "их", "им", "ей", "её"
        ],
    ]

    public init() {}

    public func closestShortWord(to word: String, language: Language) -> String? {
        guard let candidates = SuggestionEngine.shortWords[language] else { return nil }
        var matches: [String] = []
        for candidate in candidates where candidate.count == word.count {
            var diff = 0
            for (a, b) in zip(word, candidate) {
                if a != b {
                    diff += 1
                    if diff > 1 { break }
                }
            }
            if diff <= 1 {
                matches.append(candidate)
                continue
            }

            let dist = damerauLevenshteinDistance(word, candidate, maxDistance: 1)
            if dist <= 1 {
                matches.append(candidate)
            }
        }
        if matches.count == 1 {
            return matches[0]
        }
        if let first = word.first {
            let firstMatches = matches.filter { $0.first == first }
            if firstMatches.count == 1 {
                return firstMatches[0]
            }
        }
        if let last = word.last {
            let lastMatches = matches.filter { $0.last == last }
            if lastMatches.count == 1 {
                return lastMatches[0]
            }
        }
        return nil
    }

    private func damerauLevenshteinDistance(_ a: String, _ b: String, maxDistance: Int) -> Int {
        var workspace = DamerauLevenshtein.Workspace()
        return DamerauLevenshtein.distance(a, b, maxDistance: maxDistance, workspace: &workspace)
    }
}

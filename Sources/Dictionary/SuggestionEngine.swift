import Foundation

public struct SuggestionEngine {
    private let loader = DictionaryLoader.shared

    public static let shortWords: [Language: Set<String>] = [
        .english: [
            "a", "i", "an", "am", "is", "it", "to", "of", "in", "on", "at", "as", "by",
            "we", "he", "me", "my", "do", "if", "or", "no", "so", "us", "be", "go", "up"
        ],
        .ukrainian: [
            "в", "у", "і", "й", "та", "не", "на", "до", "за", "з", "із", "це", "я", "ми", "ти", "ви",
            "як", "чи", "що", "де", "бо", "то", "ті", "її", "їх", "ще", "ні"
        ],
        .russian: [
            "в", "и", "я", "мы", "ты", "он", "она", "не", "на", "до", "за", "из", "это"
        ],
    ]

    public init() {}

    public func isSuggestionAcceptable(original: String, suggestion: String) -> Bool {
        let o = original.lowercased()
        let s = suggestion.lowercased()
        if o == s { return true }
        if s.count <= 1 { return false }
        if abs(o.count - s.count) > 1 { return false }
        return damerauLevenshteinDistance(o, s, maxDistance: 2) <= 2
    }

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

    public func dictionarySuggestion(for word: String, language: Language) -> String? {
        var best: String? = nil
        var bestScore = Int.max
        var workspace = DamerauLevenshtein.Workspace()
        let candidates = loader.suggestionCandidates(
            for: word,
            language: language,
            maxCandidates: 768,
            maxLengthDelta: 2
        )

        for candidate in candidates {
            let dist = damerauLevenshteinDistance(
                word,
                candidate,
                maxDistance: 2,
                workspace: &workspace
            )
            guard dist <= 2 else { continue }
            let lengthPenalty = abs(candidate.count - word.count)
            let score = dist * 10 + lengthPenalty

            if score < bestScore {
                bestScore = score
                best = candidate
                if dist == 0 && lengthPenalty == 0 { return best }
            }
        }

        return best
    }

    /// Damerau-Levenshtein distance with early exit.
    private func damerauLevenshteinDistance(
        _ a: String,
        _ b: String,
        maxDistance: Int,
        workspace: inout DamerauLevenshtein.Workspace
    ) -> Int {
        return DamerauLevenshtein.distance(a, b, maxDistance: maxDistance, workspace: &workspace)
    }

    private func damerauLevenshteinDistance(_ a: String, _ b: String, maxDistance: Int) -> Int {
        var workspace = DamerauLevenshtein.Workspace()
        return DamerauLevenshtein.distance(a, b, maxDistance: maxDistance, workspace: &workspace)
    }
}

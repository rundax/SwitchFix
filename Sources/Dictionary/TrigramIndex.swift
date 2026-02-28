import Foundation

final class TrigramIndex {
    private let postings: [String: [Int]]
    private let lengths: [Int]

    init(dictionary: DictionaryIndex, denyList: Set<String>, allowList: Set<String>) {
        var postingMap: [String: [Int]] = [:]
        var wordLengths = Array(repeating: 0, count: dictionary.wordCount)

        for id in 0..<dictionary.wordCount {
            guard let word = dictionary.word(at: id) else { continue }
            if denyList.contains(word) { continue }
            wordLengths[id] = word.count

            let grams = Self.trigrams(for: word)
            for gram in grams {
                postingMap[gram, default: []].append(id)
            }
        }

        // Ensure allow-list words can still participate in suggestions even if not in dictionary.
        // We only index those that exist in the dictionary dataset.
        for word in allowList {
            let grams = Self.trigrams(for: word)
            for gram in grams {
                if postingMap[gram] == nil {
                    postingMap[gram] = []
                }
            }
        }

        self.postings = postingMap
        self.lengths = wordLengths
    }

    func candidateIDs(
        for word: String,
        maxLengthDelta: Int,
        maxCandidates: Int
    ) -> [Int] {
        let grams = Self.trigrams(for: word)
        guard !grams.isEmpty else { return [] }

        var scores: [Int: Int] = [:]
        scores.reserveCapacity(maxCandidates * 2)

        for gram in grams {
            guard let ids = postings[gram] else { continue }
            for id in ids {
                scores[id, default: 0] += 1
            }
        }

        if scores.isEmpty {
            return []
        }

        let minLen = max(1, word.count - maxLengthDelta)
        let maxLen = word.count + maxLengthDelta

        var ranked: [(id: Int, score: Int)] = []
        ranked.reserveCapacity(min(maxCandidates * 2, scores.count))

        for (id, score) in scores {
            let len = lengths[id]
            if len < minLen || len > maxLen {
                continue
            }
            ranked.append((id: id, score: score))
        }

        ranked.sort {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            let dl = abs(lengths[$0.id] - word.count)
            let dr = abs(lengths[$1.id] - word.count)
            if dl != dr {
                return dl < dr
            }
            return $0.id < $1.id
        }

        if ranked.count > maxCandidates {
            ranked.removeLast(ranked.count - maxCandidates)
        }

        return ranked.map(\.id)
    }

    private static func trigrams(for word: String) -> Set<String> {
        let chars = Array(word)
        if chars.isEmpty { return [] }
        if chars.count < 3 { return [word] }

        var grams: Set<String> = []
        grams.reserveCapacity(chars.count)
        for i in 0...(chars.count - 3) {
            grams.insert(String(chars[i...i+2]))
        }
        return grams
    }
}

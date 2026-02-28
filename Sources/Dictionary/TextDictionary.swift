import Foundation

final class TextDictionary: DictionaryIndex {
    let wordCount: Int
    let bloomFilter: BloomFilter?

    private let words: [String]
    private let partitions: [UInt32: Range<Int>]

    init(words: [String]) {
        let sortedWords = Array(Set(words)).sorted()
        self.words = sortedWords
        self.wordCount = sortedWords.count

        var partitionMap: [UInt32: Range<Int>] = [:]
        var i = 0
        while i < sortedWords.count {
            guard let scalar = sortedWords[i].unicodeScalars.first?.value else {
                i += 1
                continue
            }
            var j = i + 1
            while j < sortedWords.count,
                  sortedWords[j].unicodeScalars.first?.value == scalar {
                j += 1
            }
            partitionMap[scalar] = i..<j
            i = j
        }
        self.partitions = partitionMap

        if sortedWords.isEmpty {
            self.bloomFilter = BloomFilter(expectedItems: 1, falsePositiveRate: 0.01)
        } else {
            let filter = BloomFilter(expectedItems: sortedWords.count, falsePositiveRate: 0.01)
            for word in sortedWords {
                filter.insert(word)
            }
            self.bloomFilter = filter
        }
    }

    convenience init(url: URL) {
        var collected: [String] = []

        if let data = try? Data(contentsOf: url),
           let content = String(data: data, encoding: .utf8) {
            content.enumerateLines { line, _ in
                let word = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !word.isEmpty {
                    collected.append(word)
                }
            }
        }

        self.init(words: collected)
    }

    func contains(_ word: String) -> Bool {
        guard let firstScalar = word.unicodeScalars.first?.value,
              let range = partitions[firstScalar] else {
            return false
        }

        var low = range.lowerBound
        var high = range.upperBound

        while low < high {
            let mid = low + (high - low) / 2
            let candidate = words[mid]
            if candidate < word {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low < range.upperBound && words[low] == word
    }

    func word(at index: Int) -> String? {
        guard index >= 0, index < words.count else {
            return nil
        }
        return words[index]
    }

    func partitionRange(for firstScalar: UInt32) -> Range<Int>? {
        return partitions[firstScalar]
    }
}

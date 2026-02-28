import Foundation

final class MappedDictionary: DictionaryIndex {
    let wordCount: Int
    let bloomFilter: BloomFilter?

    private let mappedData: Data
    private let header: DictionaryBinaryFormat.Header
    private let partitions: [UInt32: Range<Int>]
    private let offsetsStart: Int
    private let wordsStart: Int
    private let wordsLength: Int

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        guard let header = DictionaryBinaryFormat.parseHeader(from: data) else {
            return nil
        }

        let wordsStart = Int(header.wordsOffset)
        let wordsLength = Int(header.wordsLength)
        let wordsEnd = wordsStart + wordsLength

        let offsetsStart = Int(header.offsetsOffset)
        let offsetsCount = Int(header.wordCount) + 1
        let offsetsEnd = offsetsStart + (offsetsCount * MemoryLayout<UInt32>.size)

        guard wordsStart >= 0,
              wordsLength >= 0,
              wordsEnd <= data.count,
              offsetsStart >= 0,
              offsetsEnd <= data.count else {
            return nil
        }

        guard let partitionEntries = DictionaryBinaryFormat.readPartitionEntries(from: data, header: header) else {
            return nil
        }

        var partitionMap: [UInt32: Range<Int>] = [:]
        partitionMap.reserveCapacity(partitionEntries.count)
        let totalWordCount = Int(header.wordCount)

        for entry in partitionEntries {
            let start = Int(entry.start)
            let end = start + Int(entry.count)
            guard start >= 0, end >= start, end <= totalWordCount else {
                return nil
            }
            partitionMap[entry.scalar] = start..<end
        }

        var bloom: BloomFilter? = nil
        if header.hasBloom {
            let bloomStart = Int(header.bloomOffset)
            let bloomLength = Int(header.bloomLength)
            let bloomEnd = bloomStart + bloomLength
            guard bloomStart >= 0, bloomLength > 0, bloomEnd <= data.count else {
                return nil
            }
            let bytes = Array(data[bloomStart..<bloomEnd])
            bloom = BloomFilter(
                bitCount: Int(header.bloomBitCount),
                hashCount: Int(header.bloomHashCount),
                bits: bytes
            )
        }

        self.mappedData = data
        self.header = header
        self.wordCount = Int(header.wordCount)
        self.bloomFilter = bloom
        self.partitions = partitionMap
        self.offsetsStart = offsetsStart
        self.wordsStart = wordsStart
        self.wordsLength = wordsLength
    }

    func contains(_ word: String) -> Bool {
        guard let firstScalar = word.unicodeScalars.first?.value,
              let range = partitionRange(for: firstScalar) else {
            return false
        }

        var low = range.lowerBound
        var high = range.upperBound

        while low < high {
            let mid = low + (high - low) / 2
            guard let candidate = self.word(at: mid) else {
                return false
            }

            if candidate < word {
                low = mid + 1
            } else {
                high = mid
            }
        }

        guard low < range.upperBound,
              let candidate = self.word(at: low) else {
            return false
        }

        return candidate == word
    }

    func word(at index: Int) -> String? {
        guard index >= 0, index < wordCount else {
            return nil
        }

        let start = Int(readWordOffset(at: index))
        let end = Int(readWordOffset(at: index + 1))

        guard start >= 0,
              end >= start,
              end <= wordsLength else {
            return nil
        }

        let absoluteStart = wordsStart + start
        let absoluteEnd = wordsStart + end

        guard absoluteStart >= wordsStart,
              absoluteEnd <= wordsStart + wordsLength else {
            return nil
        }

        return String(decoding: mappedData[absoluteStart..<absoluteEnd], as: UTF8.self)
    }

    func partitionRange(for firstScalar: UInt32) -> Range<Int>? {
        return partitions[firstScalar]
    }

    private func readWordOffset(at index: Int) -> UInt32 {
        let offset = offsetsStart + index * MemoryLayout<UInt32>.size
        return DictionaryBinaryFormat.readUInt32(from: mappedData, at: offset)
    }
}

import Foundation

enum DictionaryBinaryFormat {
    static let magic: [UInt8] = Array("SFDICT2\u{0}".utf8)
    static let version: UInt32 = 2
    static let flagHasBloom: UInt32 = 1 << 0

    static let headerSize = 80
    static let partitionEntrySize = 12

    struct Header {
        let version: UInt32
        let flags: UInt32
        let wordCount: UInt32
        let partitionCount: UInt32
        let bloomBitCount: UInt32
        let bloomHashCount: UInt32
        let partitionsOffset: UInt64
        let offsetsOffset: UInt64
        let wordsOffset: UInt64
        let wordsLength: UInt64
        let bloomOffset: UInt64
        let bloomLength: UInt64

        var hasBloom: Bool {
            (flags & DictionaryBinaryFormat.flagHasBloom) != 0
        }
    }

    struct PartitionEntry {
        let scalar: UInt32
        let start: UInt32
        let count: UInt32
    }

    static func parseHeader(from data: Data) -> Header? {
        guard data.count >= headerSize else {
            return nil
        }

        guard Array(data[0..<magic.count]) == magic else {
            return nil
        }

        let version = readUInt32(from: data, at: 8)
        guard version == self.version else {
            return nil
        }

        return Header(
            version: version,
            flags: readUInt32(from: data, at: 12),
            wordCount: readUInt32(from: data, at: 16),
            partitionCount: readUInt32(from: data, at: 20),
            bloomBitCount: readUInt32(from: data, at: 24),
            bloomHashCount: readUInt32(from: data, at: 28),
            partitionsOffset: readUInt64(from: data, at: 32),
            offsetsOffset: readUInt64(from: data, at: 40),
            wordsOffset: readUInt64(from: data, at: 48),
            wordsLength: readUInt64(from: data, at: 56),
            bloomOffset: readUInt64(from: data, at: 64),
            bloomLength: readUInt64(from: data, at: 72)
        )
    }

    static func readPartitionEntries(
        from data: Data,
        header: Header
    ) -> [PartitionEntry]? {
        let start = Int(header.partitionsOffset)
        let count = Int(header.partitionCount)
        let byteCount = count * partitionEntrySize
        let end = start + byteCount

        guard start >= 0, end <= data.count else {
            return nil
        }

        var result: [PartitionEntry] = []
        result.reserveCapacity(count)

        var offset = start
        for _ in 0..<count {
            let scalar = readUInt32(from: data, at: offset)
            let rangeStart = readUInt32(from: data, at: offset + 4)
            let rangeCount = readUInt32(from: data, at: offset + 8)
            result.append(PartitionEntry(scalar: scalar, start: rangeStart, count: rangeCount))
            offset += partitionEntrySize
        }

        return result
    }

    static func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        precondition(offset + 4 <= data.count, "Out-of-bounds UInt32 read")
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    static func readUInt64(from data: Data, at offset: Int) -> UInt64 {
        precondition(offset + 8 <= data.count, "Out-of-bounds UInt64 read")
        let b0 = UInt64(data[offset])
        let b1 = UInt64(data[offset + 1]) << 8
        let b2 = UInt64(data[offset + 2]) << 16
        let b3 = UInt64(data[offset + 3]) << 24
        let b4 = UInt64(data[offset + 4]) << 32
        let b5 = UInt64(data[offset + 5]) << 40
        let b6 = UInt64(data[offset + 6]) << 48
        let b7 = UInt64(data[offset + 7]) << 56
        return b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
    }
}

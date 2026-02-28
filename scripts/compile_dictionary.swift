#!/usr/bin/env swift

import Foundation

struct BloomBuilder {
    private(set) var bits: [UInt8]
    let bitCount: Int
    let hashCount: Int

    init(expectedItems: Int, falsePositiveRate: Double) {
        let n = max(expectedItems, 1)
        let m = Int(ceil(-Double(n) * log(falsePositiveRate) / (log(2.0) * log(2.0))))
        let k = max(1, Int(round(Double(m) / Double(n) * log(2.0))))
        self.bitCount = m
        self.hashCount = k
        self.bits = [UInt8](repeating: 0, count: (m + 7) / 8)
    }

    mutating func insert(_ word: String) {
        let hashes = computeHashes(word)
        for idx in hashes {
            let byteIndex = idx / 8
            let bitIndex = idx % 8
            bits[byteIndex] |= (1 << bitIndex)
        }
    }

    private func computeHashes(_ word: String) -> [Int] {
        let data = Array(word.utf8)
        let h1 = fnv1a(data, seed: 0)
        let h2 = fnv1a(data, seed: 0x9e3779b9)
        var hashes: [Int] = []
        hashes.reserveCapacity(hashCount)
        for i in 0..<hashCount {
            let combined = h1 &+ (UInt64(i) &* h2)
            hashes.append(Int(combined % UInt64(bitCount)))
        }
        return hashes
    }

    private func fnv1a(_ data: [UInt8], seed: UInt64) -> UInt64 {
        var hash: UInt64 = 14695981039346656037 &+ seed
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }
}

struct PartitionEntry {
    let scalar: UInt32
    let start: UInt32
    let count: UInt32
}

enum BinaryFormat {
    static let magic = Array("SFDICT2\u{0}".utf8)
    static let version: UInt32 = 2
    static let flagHasBloom: UInt32 = 1 << 0
}

func usage() {
    print("Usage: scripts/compile_dictionary.swift --input <path> --output <path> [--false-positive-rate <rate>] [--no-bloom]")
}

func appendLE32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
    data.append(UInt8(truncatingIfNeeded: value >> 16))
    data.append(UInt8(truncatingIfNeeded: value >> 24))
}

func appendLE64(_ value: UInt64, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
    data.append(UInt8(truncatingIfNeeded: value >> 16))
    data.append(UInt8(truncatingIfNeeded: value >> 24))
    data.append(UInt8(truncatingIfNeeded: value >> 32))
    data.append(UInt8(truncatingIfNeeded: value >> 40))
    data.append(UInt8(truncatingIfNeeded: value >> 48))
    data.append(UInt8(truncatingIfNeeded: value >> 56))
}

func parseArgs() -> (input: URL, output: URL, falsePositiveRate: Double, includeBloom: Bool)? {
    var inputPath: String?
    var outputPath: String?
    var falsePositiveRate = 0.01
    var includeBloom = true

    var i = 1
    let args = CommandLine.arguments
    while i < args.count {
        switch args[i] {
        case "--input":
            i += 1
            if i < args.count { inputPath = args[i] }
        case "--output":
            i += 1
            if i < args.count { outputPath = args[i] }
        case "--false-positive-rate":
            i += 1
            if i < args.count, let parsed = Double(args[i]) {
                falsePositiveRate = parsed
            }
        case "--no-bloom":
            includeBloom = false
        case "-h", "--help":
            usage()
            exit(0)
        default:
            break
        }
        i += 1
    }

    guard let inPath = inputPath, let outPath = outputPath else {
        usage()
        return nil
    }

    return (
        input: URL(fileURLWithPath: inPath),
        output: URL(fileURLWithPath: outPath),
        falsePositiveRate: falsePositiveRate,
        includeBloom: includeBloom
    )
}

func loadWords(from input: URL) throws -> [String] {
    let content = try String(contentsOf: input, encoding: .utf8)
    var words: Set<String> = []
    words.reserveCapacity(500_000)

    content.enumerateLines { line, _ in
        let normalized = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
        if !normalized.isEmpty {
            words.insert(normalized)
        }
    }

    return words.sorted()
}

func buildPartitions(words: [String]) -> [PartitionEntry] {
    var result: [PartitionEntry] = []
    var i = 0

    while i < words.count {
        guard let scalar = words[i].unicodeScalars.first?.value else {
            i += 1
            continue
        }

        var j = i + 1
        while j < words.count, words[j].unicodeScalars.first?.value == scalar {
            j += 1
        }

        result.append(
            PartitionEntry(
                scalar: scalar,
                start: UInt32(i),
                count: UInt32(j - i)
            )
        )

        i = j
    }

    return result
}

func compileDictionary(
    input: URL,
    output: URL,
    falsePositiveRate: Double,
    includeBloom: Bool
) throws {
    let words = try loadWords(from: input)
    let partitions = buildPartitions(words: words)

    var offsets: [UInt32] = []
    offsets.reserveCapacity(words.count + 1)

    var wordsBlob = Data()
    wordsBlob.reserveCapacity(words.reduce(0) { $0 + $1.utf8.count })

    var bloom: BloomBuilder? = nil
    if includeBloom {
        bloom = BloomBuilder(expectedItems: words.count, falsePositiveRate: falsePositiveRate)
    }

    var cursor: UInt32 = 0
    offsets.append(cursor)

    for word in words {
        let bytes = Array(word.utf8)
        wordsBlob.append(contentsOf: bytes)
        cursor += UInt32(bytes.count)
        offsets.append(cursor)
        bloom?.insert(word)
    }

    let partitionsOffset = UInt64(80)
    let partitionsLength = UInt64(partitions.count * 12)
    let offsetsOffset = partitionsOffset + partitionsLength
    let offsetsLength = UInt64(offsets.count * 4)
    let wordsOffset = offsetsOffset + offsetsLength
    let wordsLength = UInt64(wordsBlob.count)
    let bloomOffset = wordsOffset + wordsLength
    let bloomBytes = bloom?.bits ?? []
    let bloomLength = UInt64(bloomBytes.count)

    var out = Data()
    out.reserveCapacity(Int(bloomOffset + bloomLength))

    out.append(contentsOf: BinaryFormat.magic)
    appendLE32(BinaryFormat.version, to: &out)
    appendLE32(includeBloom ? BinaryFormat.flagHasBloom : 0, to: &out)
    appendLE32(UInt32(words.count), to: &out)
    appendLE32(UInt32(partitions.count), to: &out)
    appendLE32(UInt32(bloom?.bitCount ?? 0), to: &out)
    appendLE32(UInt32(bloom?.hashCount ?? 0), to: &out)
    appendLE64(partitionsOffset, to: &out)
    appendLE64(offsetsOffset, to: &out)
    appendLE64(wordsOffset, to: &out)
    appendLE64(wordsLength, to: &out)
    appendLE64(bloomOffset, to: &out)
    appendLE64(bloomLength, to: &out)

    for p in partitions {
        appendLE32(p.scalar, to: &out)
        appendLE32(p.start, to: &out)
        appendLE32(p.count, to: &out)
    }

    for value in offsets {
        appendLE32(value, to: &out)
    }

    out.append(wordsBlob)
    out.append(contentsOf: bloomBytes)

    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try out.write(to: output, options: .atomic)

    print("Compiled \(words.count) words")
    print("Binary: \(output.path)")
    if includeBloom {
        print("Bloom: \(bloomBytes.count) bytes, k=\(bloom?.hashCount ?? 0)")
    }
}

guard let config = parseArgs() else {
    exit(1)
}

do {
    try compileDictionary(
        input: config.input,
        output: config.output,
        falsePositiveRate: config.falsePositiveRate,
        includeBloom: config.includeBloom
    )
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}

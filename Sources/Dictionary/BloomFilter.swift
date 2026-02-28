import Foundation

/// A space-efficient probabilistic data structure for set membership testing.
/// False positives are possible, but false negatives are not.
public class BloomFilter {
    private var bits: [UInt8]
    public let bitCount: Int
    public let hashCount: Int

    /// Create a BloomFilter with the specified number of bits and hash functions.
    /// For 50K words with ~1% false positive rate: bitCount ≈ 480,000, hashCount = 7
    public init(bitCount: Int, hashCount: Int) {
        self.bitCount = bitCount
        self.hashCount = hashCount
        let byteCount = (bitCount + 7) / 8
        self.bits = [UInt8](repeating: 0, count: byteCount)
    }

    /// Create a BloomFilter from a serialized bit-array.
    public init(bitCount: Int, hashCount: Int, bits: [UInt8]) {
        self.bitCount = bitCount
        self.hashCount = hashCount
        self.bits = bits
    }

    /// Create a BloomFilter optimized for a given number of items and false positive rate.
    public convenience init(expectedItems: Int, falsePositiveRate: Double = 0.01) {
        // m = -n * ln(p) / (ln(2))^2
        let m = Int(ceil(-Double(expectedItems) * log(falsePositiveRate) / (log(2.0) * log(2.0))))
        // k = (m/n) * ln(2)
        let k = max(1, Int(round(Double(m) / Double(expectedItems) * log(2.0))))
        self.init(bitCount: m, hashCount: k)
    }

    /// Insert a word into the filter.
    public func insert(_ word: String) {
        let hashes = computeHashes(word)
        for h in hashes {
            let index = h
            let byteIndex = index / 8
            let bitIndex = index % 8
            bits[byteIndex] |= (1 << bitIndex)
        }
    }

    /// Check if the word might be in the filter.
    /// Returns true if the word might exist (possible false positive),
    /// returns false if the word definitely does not exist.
    public func mightContain(_ word: String) -> Bool {
        let hashes = computeHashes(word)
        for h in hashes {
            let index = h
            let byteIndex = index / 8
            let bitIndex = index % 8
            if bits[byteIndex] & (1 << bitIndex) == 0 {
                return false
            }
        }
        return true
    }

    /// The approximate memory usage of this filter in bytes.
    public var memoryUsage: Int {
        return bits.count
    }

    /// Serialized bit-array for persistence.
    public var serializedBits: [UInt8] {
        return bits
    }

    // MARK: - Hashing

    /// Compute k hash values using the double-hashing technique:
    /// h_i(x) = h1(x) + i * h2(x)
    /// where h1 and h2 are two independent hash functions (FNV-1a variants).
    private func computeHashes(_ word: String) -> [Int] {
        let data = Array(word.utf8)
        let h1 = fnv1a(data, seed: 0)
        let h2 = fnv1a(data, seed: 0x9e3779b9)

        var hashes = [Int]()
        hashes.reserveCapacity(hashCount)
        for i in 0..<hashCount {
            let combined = h1 &+ (UInt64(i) &* h2)
            hashes.append(Int(combined % UInt64(bitCount)))
        }
        return hashes
    }

    /// FNV-1a hash function (64-bit) with optional seed.
    private func fnv1a(_ data: [UInt8], seed: UInt64) -> UInt64 {
        var hash: UInt64 = 14695981039346656037 &+ seed
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }
}

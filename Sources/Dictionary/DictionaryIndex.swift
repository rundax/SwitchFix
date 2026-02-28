import Foundation

protocol DictionaryIndex: AnyObject {
    var wordCount: Int { get }
    var bloomFilter: BloomFilter? { get }

    func contains(_ word: String) -> Bool
    func word(at index: Int) -> String?
    func partitionRange(for firstScalar: UInt32) -> Range<Int>?
}

import Foundation

public enum Language: String, CaseIterable {
    case english = "en_US"
    case ukrainian = "uk_UA"
    case russian = "ru_RU"
}

public class DictionaryLoader {
    private var filters: [Language: BloomFilter] = [:]
    private let lock = NSLock()

    public static let shared = DictionaryLoader()

    private init() {}

    /// Get or lazily load the BloomFilter for a given language.
    public func bloomFilter(for language: Language) -> BloomFilter {
        lock.lock()
        defer { lock.unlock() }

        if let existing = filters[language] {
            return existing
        }

        let filter = loadDictionary(for: language)
        filters[language] = filter
        return filter
    }

    private func loadDictionary(for language: Language) -> BloomFilter {
        let filter = BloomFilter(expectedItems: 50_000, falsePositiveRate: 0.01)

        guard let url = Bundle.module.url(forResource: language.rawValue, withExtension: "txt", subdirectory: "Resources") else {
            return filter
        }

        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return filter
        }

        // Read line by line to avoid loading entire word list into memory
        content.enumerateLines { line, _ in
            let word = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !word.isEmpty {
                filter.insert(word)
            }
        }

        return filter
    }
}

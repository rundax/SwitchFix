import Foundation

public enum Language: String, CaseIterable {
    case english = "en_US"
    case ukrainian = "uk_UA"
    case russian = "ru_RU"
}

public class DictionaryLoader {
    private var filters: [Language: BloomFilter] = [:]
    private var suggestionBuckets: [Language: [Character: [Int: [String]]]] = [:]
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

    /// Get or lazily load the suggestion buckets for a given language.
    /// Buckets are keyed by first letter and word length.
    public func suggestionBuckets(for language: Language) -> [Character: [Int: [String]]] {
        lock.lock()
        defer { lock.unlock() }

        if let existing = suggestionBuckets[language] {
            return existing
        }

        let filter = loadDictionary(for: language)
        filters[language] = filter
        return suggestionBuckets[language] ?? [:]
    }

    /// Locate the dictionary file, trying multiple bundle paths.
    /// SPM's Bundle.module works during development but may fail in .app bundles
    /// where the resource bundle is at Contents/Resources/SwitchFix_Dictionary.bundle.
    private func findDictionaryURL(for language: Language) -> URL? {
        // Helper: try both root and nested "Resources" (some bundles flatten copied directories)
        func lookup(in bundle: Bundle) -> URL? {
            if let url = bundle.url(forResource: language.rawValue, withExtension: "txt") {
                return url
            }
            if let url = bundle.url(forResource: language.rawValue, withExtension: "txt", subdirectory: "Resources") {
                return url
            }
            return nil
        }

        // 1. SPM's Bundle.module (works in development/debug)
        if let url = lookup(in: Bundle.module) {
            return url
        }

        // 2. Main bundle's resourceURL + SwitchFix_Dictionary.bundle (works in .app)
        if let resourceURL = Bundle.main.resourceURL {
            let bundlePath = resourceURL.appendingPathComponent("SwitchFix_Dictionary.bundle")
            if let resourceBundle = Bundle(url: bundlePath) {
                if let url = lookup(in: resourceBundle) {
                    return url
                }
            }
        }

        // 3. Alongside the executable (flat layout fallback)
        let execURL = Bundle.main.bundleURL.appendingPathComponent("SwitchFix_Dictionary.bundle")
        if let resourceBundle = Bundle(url: execURL) {
            if let url = lookup(in: resourceBundle) {
                return url
            }
        }

        NSLog("[SwitchFix] Dictionary: could not find %@.txt in any bundle location", language.rawValue)
        return nil
    }

    private func loadDictionary(for language: Language) -> BloomFilter {
        let filter = BloomFilter(expectedItems: 400_000, falsePositiveRate: 0.01)
        var buckets: [Character: [Int: [String]]] = [:]
        let maxSuggestionWordLength = 20
        let denyList = loadOverrideList(for: language, type: "deny")
        let allowList = loadOverrideList(for: language, type: "allow")

        guard let url = findDictionaryURL(for: language) else {
            return filter
        }

        NSLog("[SwitchFix] Dictionary: loading %@ from %@", language.rawValue, url.path)

        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return filter
        }

        // Read line by line to avoid loading entire word list into memory
        var wordCount = 0
        content.enumerateLines { line, _ in
            let word = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !word.isEmpty {
                if denyList.contains(word) {
                    return
                }
                filter.insert(word)
                if word.count <= maxSuggestionWordLength, let first = word.first {
                    var lengthMap = buckets[first] ?? [:]
                    var list = lengthMap[word.count] ?? []
                    list.append(word)
                    lengthMap[word.count] = list
                    buckets[first] = lengthMap
                }
                wordCount += 1
            }
        }

        if !allowList.isEmpty {
            for word in allowList {
                filter.insert(word)
                if word.count <= maxSuggestionWordLength, let first = word.first {
                    var lengthMap = buckets[first] ?? [:]
                    var list = lengthMap[word.count] ?? []
                    list.append(word)
                    lengthMap[word.count] = list
                    buckets[first] = lengthMap
                }
            }
        }

        suggestionBuckets[language] = buckets

        NSLog("[SwitchFix] Dictionary: loaded %d words for %@", wordCount, language.rawValue)
        return filter
    }

    private func loadOverrideList(for language: Language, type: String) -> Set<String> {
        let filename = "\(language.rawValue)_\(type)"

        func lookup(in bundle: Bundle) -> URL? {
            if let url = bundle.url(forResource: filename, withExtension: "txt", subdirectory: "overrides") {
                return url
            }
            if let url = bundle.url(forResource: filename, withExtension: "txt") {
                return url
            }
            return nil
        }

        var url: URL? = lookup(in: Bundle.module)

        if url == nil, let resourceURL = Bundle.main.resourceURL {
            let bundlePath = resourceURL.appendingPathComponent("SwitchFix_Dictionary.bundle")
            if let resourceBundle = Bundle(url: bundlePath) {
                url = lookup(in: resourceBundle)
            }
        }

        if url == nil {
            let execURL = Bundle.main.bundleURL.appendingPathComponent("SwitchFix_Dictionary.bundle")
            if let resourceBundle = Bundle(url: execURL) {
                url = lookup(in: resourceBundle)
            }
        }

        guard let finalURL = url,
              let data = try? Data(contentsOf: finalURL),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        var result: Set<String> = []
        content.enumerateLines { line, _ in
            let word = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !word.isEmpty {
                result.insert(word)
            }
        }
        return result
    }
}

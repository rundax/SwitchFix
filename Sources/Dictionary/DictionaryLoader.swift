import Foundation

public enum Language: String, CaseIterable {
    case english = "en_US"
    case ukrainian = "uk_UA"
    case russian = "ru_RU"
}

public class DictionaryLoader {
    private var indices: [Language: DictionaryIndex] = [:]
    private var fallbackBloomFilters: [Language: BloomFilter] = [:]
    private var trigramIndices: [Language: TrigramIndex] = [:]
    private var allowLists: [Language: Set<String>] = [:]
    private var denyLists: [Language: Set<String>] = [:]
    private let lock = NSLock()

    public static let shared = DictionaryLoader()

    private init() {}

    /// Prewarm a language dictionary. Suggestions stay lazy by default.
    public func prewarm(language: Language, includeSuggestions: Bool = false) {
        lock.lock()
        defer { lock.unlock() }

        let _ = ensureIndexLoaded(for: language)
        if includeSuggestions {
            let _ = ensureTrigramIndexLoaded(for: language)
        }
    }

    /// Test-only cache reset for reproducible benchmark runs.
    public func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        indices = [:]
        fallbackBloomFilters = [:]
        trigramIndices = [:]
        allowLists = [:]
        denyLists = [:]
    }

    /// Exposes the Bloom filter for compatibility with existing call-sites/tests.
    public func bloomFilter(for language: Language) -> BloomFilter {
        lock.lock()
        defer { lock.unlock() }

        let index = ensureIndexLoaded(for: language)
        if let filter = index.bloomFilter {
            return filter
        }

        if let existing = fallbackBloomFilters[language] {
            return existing
        }

        let built = buildFallbackBloomFilter(from: index, language: language)
        fallbackBloomFilters[language] = built
        return built
    }

    public func mightContain(_ word: String, language: Language) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let index = ensureIndexLoaded(for: language)
        let denyList = denyLists[language] ?? []
        if denyList.contains(word) {
            return false
        }

        let allowList = allowLists[language] ?? []
        if allowList.contains(word) {
            return true
        }

        if let filter = index.bloomFilter {
            return filter.mightContain(word)
        }

        return index.contains(word)
    }

    public func containsExact(_ word: String, language: Language) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let index = ensureIndexLoaded(for: language)

        let denyList = denyLists[language] ?? []
        if denyList.contains(word) {
            return false
        }

        let allowList = allowLists[language] ?? []
        if allowList.contains(word) {
            return true
        }

        return index.contains(word)
    }

    public func suggestionCandidates(
        for word: String,
        language: Language,
        maxCandidates: Int = 512,
        maxLengthDelta: Int = 2
    ) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        let index = ensureIndexLoaded(for: language)
        let trigram = ensureTrigramIndexLoaded(for: language)
        let denyList = denyLists[language] ?? []
        let allowList = allowLists[language] ?? []

        let candidateIDs = trigram.candidateIDs(
            for: word,
            maxLengthDelta: maxLengthDelta,
            maxCandidates: maxCandidates
        )

        var seen: Set<String> = []
        seen.reserveCapacity(candidateIDs.count + allowList.count)

        var result: [String] = []
        result.reserveCapacity(candidateIDs.count)

        for id in candidateIDs {
            guard let candidate = index.word(at: id) else { continue }
            if denyList.contains(candidate) { continue }
            if seen.insert(candidate).inserted {
                result.append(candidate)
            }
        }

        // Fallback for low-overlap typos: scan a bounded first-character partition.
        if let firstScalar = word.unicodeScalars.first?.value,
           let range = index.partitionRange(for: firstScalar),
           result.count < max(32, maxCandidates / 4) {
            for id in range {
                guard let candidate = index.word(at: id) else { continue }
                if abs(candidate.count - word.count) > maxLengthDelta { continue }
                if denyList.contains(candidate) { continue }
                if seen.insert(candidate).inserted {
                    result.append(candidate)
                    if result.count >= maxCandidates { break }
                }
            }
        }

        // Overlay allow-list words for misspelled custom vocabulary.
        for candidate in allowList {
            if abs(candidate.count - word.count) > maxLengthDelta { continue }
            if seen.insert(candidate).inserted {
                result.append(candidate)
            }
        }

        return result
    }

    private func ensureIndexLoaded(for language: Language) -> DictionaryIndex {
        if let existing = indices[language] {
            return existing
        }

        let allow = loadOverrideList(for: language, type: "allow")
        let deny = loadOverrideList(for: language, type: "deny")
        allowLists[language] = allow
        denyLists[language] = deny

        let index = loadDictionaryIndex(for: language)
        indices[language] = index

        NSLog("[SwitchFix] Dictionary: loaded %@ (words: %d, bloom: %@)",
              language.rawValue,
              index.wordCount,
              index.bloomFilter == nil ? "no" : "yes")

        return index
    }

    private func ensureTrigramIndexLoaded(for language: Language) -> TrigramIndex {
        if let existing = trigramIndices[language] {
            return existing
        }

        let index = ensureIndexLoaded(for: language)
        let deny = denyLists[language] ?? []
        let allow = allowLists[language] ?? []

        NSLog("[SwitchFix] Dictionary: building trigram index for %@", language.rawValue)
        let built = TrigramIndex(dictionary: index, denyList: deny, allowList: allow)
        trigramIndices[language] = built
        return built
    }

    private func loadDictionaryIndex(for language: Language) -> DictionaryIndex {
        if let binURL = findDictionaryURL(for: language, ext: "bin") {
            if let mapped = MappedDictionary(url: binURL) {
                NSLog("[SwitchFix] Dictionary: using mmap binary %@", binURL.path)
                return mapped
            }
            NSLog("[SwitchFix] Dictionary: failed to parse %@.bin, fallback to txt", language.rawValue)
        }

        if let txtURL = findDictionaryURL(for: language, ext: "txt") {
            NSLog("[SwitchFix] Dictionary: using text fallback %@", txtURL.path)
            return TextDictionary(url: txtURL)
        }

        NSLog("[SwitchFix] Dictionary: missing dictionary resources for %@", language.rawValue)
        return TextDictionary(words: [])
    }

    /// Locate a dictionary resource by extension, trying multiple bundle paths.
    private func findDictionaryURL(for language: Language, ext: String) -> URL? {
        func lookup(in bundle: Bundle) -> URL? {
            if let url = bundle.url(forResource: language.rawValue, withExtension: ext) {
                return url
            }
            if let url = bundle.url(forResource: language.rawValue, withExtension: ext, subdirectory: "Resources") {
                return url
            }
            return nil
        }

        if let url = lookup(in: Bundle.module) {
            return url
        }

        if let resourceURL = Bundle.main.resourceURL {
            let bundlePath = resourceURL.appendingPathComponent("SwitchFix_Dictionary.bundle")
            if let resourceBundle = Bundle(url: bundlePath),
               let url = lookup(in: resourceBundle) {
                return url
            }
        }

        let execURL = Bundle.main.bundleURL.appendingPathComponent("SwitchFix_Dictionary.bundle")
        if let resourceBundle = Bundle(url: execURL),
           let url = lookup(in: resourceBundle) {
            return url
        }

        return nil
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

    private func buildFallbackBloomFilter(from index: DictionaryIndex, language: Language) -> BloomFilter {
        let expected = max(index.wordCount, 1)
        let filter = BloomFilter(expectedItems: expected, falsePositiveRate: 0.01)

        for i in 0..<index.wordCount {
            guard let word = index.word(at: i) else { continue }
            if denyLists[language]?.contains(word) == true {
                continue
            }
            filter.insert(word)
        }

        if let allow = allowLists[language] {
            for word in allow {
                filter.insert(word)
            }
        }

        return filter
    }
}

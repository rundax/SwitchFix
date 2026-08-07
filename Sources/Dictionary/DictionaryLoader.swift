import Foundation
import os

public enum Language: String, CaseIterable {
    case english = "en_US"
    case ukrainian = "uk_UA"
    case russian = "ru_RU"
}

public class DictionaryLoader {
    private var indices: [Language: DictionaryIndex] = [:]
    private var unavailableLanguages: Set<Language> = []
    private var allowLists: [Language: Set<String>] = [:]
    private var denyLists: [Language: Set<String>] = [:]
    private var textFallbackEnabledForTesting = false
    private let lock = OSAllocatedUnfairLock()

    public static let shared = DictionaryLoader()

    private init() {}

    /// Prepare an immutable exact index before automatic monitoring starts.
    @discardableResult
    public func prewarm(language: Language) -> Bool {
        lock.withLock { ensureIndexLoaded(for: language) != nil }
    }

    /// Text dictionaries are intentionally available only to explicit test tooling.
    public func enableTextFallbackForTesting() {
        lock.withLock {
            textFallbackEnabledForTesting = true
            unavailableLanguages.removeAll()
        }
    }

    /// Test-only cache reset for reproducible benchmark runs.
    public func resetForTesting() {
        lock.withLock {
            indices = [:]
            unavailableLanguages = []
            allowLists = [:]
            denyLists = [:]
        }
    }

    /// Exposes the Bloom filter for compatibility with existing call-sites/tests.
    public func bloomFilter(for language: Language) -> BloomFilter {
        return lock.withLock {
            if let index = ensureIndexLoaded(for: language), let filter = index.bloomFilter {
                return filter
            }
            return BloomFilter(expectedItems: 1, falsePositiveRate: 0.01)
        }
    }

    public func mightContain(_ word: String, language: Language) -> Bool {
        return lock.withLock {
            guard let index = ensureIndexLoaded(for: language) else { return false }
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
    }

    public func containsExact(_ word: String, language: Language) -> Bool {
        return lock.withLock {
            guard let index = ensureIndexLoaded(for: language) else { return false }

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
    }

    private func ensureIndexLoaded(for language: Language) -> DictionaryIndex? {
        if let existing = indices[language] {
            return existing
        }
        if unavailableLanguages.contains(language) {
            return nil
        }

        let allow = loadOverrideList(for: language, type: "allow")
        let deny = loadOverrideList(for: language, type: "deny")
        allowLists[language] = allow
        denyLists[language] = deny

        guard let index = loadDictionaryIndex(for: language) else {
            unavailableLanguages.insert(language)
            NSLog("[SwitchFix] Dictionary: %@ unavailable; automatic correction target disabled", language.rawValue)
            return nil
        }
        indices[language] = index

        NSLog("[SwitchFix] Dictionary: loaded %@ (entries: %d, bloom: %@)",
              language.rawValue,
              index.wordCount,
              index.bloomFilter == nil ? "no" : "yes")

        return index
    }

    private func loadDictionaryIndex(for language: Language) -> DictionaryIndex? {
        if let binURL = findDictionaryURL(for: language, ext: "bin") {
            if let mapped = MappedDictionary(url: binURL) {
                NSLog("[SwitchFix] Dictionary: using mmap binary %@", binURL.path)
                return mapped
            }
            NSLog("[SwitchFix] Dictionary: failed to parse %@.bin", language.rawValue)
        }

        if textFallbackEnabledForTesting,
           let txtURL = findDictionaryURL(for: language, ext: "txt") {
            NSLog("[SwitchFix] Dictionary: using text fallback %@", txtURL.path)
            return TextDictionary(url: txtURL)
        }

        NSLog("[SwitchFix] Dictionary: missing or invalid binary resource for %@", language.rawValue)
        return nil
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

        if let resourceBundle = dictionaryResourceBundle(),
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

        let url = dictionaryResourceBundle().flatMap(lookup)

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

    private func dictionaryResourceBundle() -> Bundle? {
        let bundleName = "SwitchFix_Dictionary.bundle"
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            executableDirectory?.appendingPathComponent(bundleName)
        ]

        for case let candidate? in candidates {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return nil
    }

}

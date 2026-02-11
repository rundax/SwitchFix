import Foundation
import Core
import Dictionary

// Simple test runner — no XCTest dependency required
var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("  FAIL: \(message) (\(file):\(line))")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if a == b {
        passed += 1
    } else {
        failed += 1
        print("  FAIL: expected \(b), got \(a). \(message) (\(file):\(line))")
    }
}

func runSuite(_ name: String, _ block: () -> Void) {
    print("--- \(name) ---")
    block()
}

func dictionaryPath(for language: Language) -> String {
    let root = FileManager.default.currentDirectoryPath
    return "\(root)/Sources/Dictionary/Resources/\(language.rawValue).txt"
}

func forEachDictionaryWord(language: Language, _ block: (String) -> Void) {
    let path = dictionaryPath(for: language)
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("  WARN: could not read dictionary at \(path)")
        return
    }

    for line in content.split(whereSeparator: \.isNewline) {
        let word = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !word.isEmpty {
            block(word)
        }
    }
}

// =============================================================================
// LayoutMapper Tests
// =============================================================================

runSuite("LayoutMapper: EN → RU") {
    assertEqual(LayoutMapper.convert("ghbdtn", from: .english, to: .russian), "привет")
    assertEqual(LayoutMapper.convert("hello", from: .english, to: .russian), "руддщ")
    assertEqual(LayoutMapper.convert("Ghbdtn", from: .english, to: .russian), "Привет")
}

runSuite("LayoutMapper: RU → EN") {
    assertEqual(LayoutMapper.convert("руддщ", from: .russian, to: .english), "hello")
    assertEqual(LayoutMapper.convert("привет", from: .russian, to: .english), "ghbdtn")
}

runSuite("LayoutMapper: EN → UK") {
    assertEqual(LayoutMapper.convert("ghbdsn", from: .english, to: .ukrainian), "привіт")
}

runSuite("LayoutMapper: UK → EN") {
    assertEqual(LayoutMapper.convert("привіт", from: .ukrainian, to: .english), "ghbdsn")
    assertEqual(LayoutMapper.convert("пшерги", from: .ukrainian, to: .english), "github")
}

runSuite("LayoutMapper: Same layout") {
    assertEqual(LayoutMapper.convert("hello", from: .english, to: .english), "hello")
}

runSuite("LayoutMapper: Alternatives") {
    let results = LayoutMapper.convertToAlternatives("ghbdtn", from: .english)
    assert(results.contains(where: { $0.0 == .russian && $0.1 == "привет" }), "alternatives should include russian 'привет'")
}

runSuite("LayoutMapper: Special chars EN→RU") {
    assertEqual(LayoutMapper.convert(";", from: .english, to: .russian), "ж")
    assertEqual(LayoutMapper.convert("'", from: .english, to: .russian), "э")
    assertEqual(LayoutMapper.convert("`", from: .english, to: .russian), "ё")
}

runSuite("LayoutMapper: Special chars EN→UK") {
    assertEqual(LayoutMapper.convert("'", from: .english, to: .ukrainian), "є")
    assertEqual(LayoutMapper.convert("]", from: .english, to: .ukrainian), "ї")
    assertEqual(LayoutMapper.convert("`", from: .english, to: .ukrainian), "ґ")
}

runSuite("LayoutMapper: Unmapped chars preserved") {
    assertEqual(LayoutMapper.convert("hello123", from: .english, to: .russian), "руддщ123")
}

// =============================================================================
// BloomFilter Tests
// =============================================================================

runSuite("BloomFilter: Basic insert and lookup") {
    let bf = BloomFilter(expectedItems: 1000)
    bf.insert("hello")
    bf.insert("world")
    bf.insert("test")
    assert(bf.mightContain("hello"), "should contain 'hello'")
    assert(bf.mightContain("world"), "should contain 'world'")
    assert(bf.mightContain("test"), "should contain 'test'")
}

runSuite("BloomFilter: No false negatives") {
    let bf = BloomFilter(expectedItems: 5000)
    let words = ["apple", "banana", "cherry", "date", "elderberry",
                 "fig", "grape", "honeydew", "kiwi", "lemon",
                 "mango", "nectarine", "orange", "papaya", "quince"]
    for w in words { bf.insert(w) }
    var allFound = true
    for w in words {
        if !bf.mightContain(w) {
            allFound = false
            break
        }
    }
    assert(allFound, "all inserted words must be found (no false negatives)")
}

runSuite("BloomFilter: False positive rate") {
    let bf = BloomFilter(expectedItems: 1000, falsePositiveRate: 0.01)
    // Insert 1000 words
    for i in 0..<1000 {
        bf.insert("word_\(i)")
    }
    // Test 10000 words that were NOT inserted
    var falsePositives = 0
    for i in 1000..<11000 {
        if bf.mightContain("other_\(i)") {
            falsePositives += 1
        }
    }
    let fpRate = Double(falsePositives) / 10000.0
    assert(fpRate < 0.02, "false positive rate should be < 2%, got \(fpRate * 100)%")
    print("  (FP rate: \(String(format: "%.2f", fpRate * 100))%)")
}

runSuite("BloomFilter: Memory usage") {
    let bf = BloomFilter(expectedItems: 50_000, falsePositiveRate: 0.01)
    let memKB = bf.memoryUsage / 1024
    assert(memKB < 700, "memory for 50K words should be < 700KB, got \(memKB)KB")
    print("  (Memory: \(memKB)KB)")
}

// =============================================================================
// WordValidator Tests
// =============================================================================

runSuite("WordValidator: Short words whitelist") {
    let wv = WordValidator.shared
    assert(!wv.isValidWord("ab", language: .english), "unknown 2-char words should be rejected")
    assert(wv.isValidWord("я", language: .russian), "common 1-char words should be allowed")
    assert(wv.isValidWord("як", language: .ukrainian), "common 2-char words should be allowed")
}

runSuite("WordValidator: URL patterns skipped") {
    let wv = WordValidator.shared
    assert(!wv.isValidWord("https://example.com", language: .english), "URLs should be skipped")
    assert(!wv.isValidWord("www.test.com", language: .english), "URLs should be skipped")
}

runSuite("WordValidator: Email patterns skipped") {
    let wv = WordValidator.shared
    assert(!wv.isValidWord("user@example.com", language: .english), "emails should be skipped")
}

runSuite("WordValidator: Pure numbers skipped") {
    let wv = WordValidator.shared
    assert(!wv.isValidWord("12345", language: .english), "numbers should be skipped")
}

runSuite("WordValidator: camelCase skipped") {
    let wv = WordValidator.shared
    assert(!wv.isValidWord("camelCase", language: .english), "camelCase should be skipped")
}

runSuite("WordValidator: Valid English words") {
    let wv = WordValidator.shared
    assert(wv.isValidWord("hello", language: .english), "'hello' should be valid in English")
    assert(wv.isValidWord("world", language: .english), "'world' should be valid in English")
    assert(wv.isValidWord("the", language: .english), "'the' should be valid in English")
}

runSuite("WordValidator: English contractions") {
    let wv = WordValidator.shared
    assert(wv.isValidWord("doesn't", language: .english), "'doesn't' should be valid in English")
    assert(wv.isValidWord("we're", language: .english), "'we're' should be valid in English")
}

runSuite("WordValidator: Valid Russian words") {
    let wv = WordValidator.shared
    assert(wv.isValidWord("привет", language: .russian), "'привет' should be valid in Russian")
    assert(wv.isValidWord("мир", language: .russian), "'мир' should be valid in Russian")
}

runSuite("WordValidator: Valid Ukrainian words") {
    let wv = WordValidator.shared
    assert(wv.isValidWord("привіт", language: .ukrainian), "'привіт' should be valid in Ukrainian")
    assert(wv.isValidWord("світ", language: .ukrainian), "'світ' should be valid in Ukrainian")
}

runSuite("WordValidator: Ukrainian vs Russian names") {
    let wv = WordValidator.shared
    assert(wv.isValidWord("андрій", language: .ukrainian), "'андрій' should be valid in Ukrainian")
    assert(!wv.isValidWord("андрей", language: .ukrainian), "'андрей' should NOT be valid in Ukrainian")
}

runSuite("WordValidator: Invalid cross-language") {
    let wv = WordValidator.shared
    assert(!wv.isValidWord("ghbdtn", language: .english), "'ghbdtn' should NOT be valid in English")
    assert(!wv.isValidWord("руддщ", language: .russian), "'руддщ' should NOT be valid in Russian")
}

runSuite("WordValidator: Short word suggestions") {
    let wv = WordValidator.shared
    let result = wv.validate("чі", language: .ukrainian, allowSuggestion: true)
    assert(result.isValid && result.correctedWord == "чи", "should suggest 'чи' for 'чі'")
}

// =============================================================================
// LayoutDetector Tests
// =============================================================================

// Helper: Mock delegate that captures detection results
class MockDetectorDelegate: LayoutDetectorDelegate {
    var results: [DetectionResult] = []
    var boundaryCharacters: [String?] = []
    func layoutDetector(_ detector: LayoutDetector, didDetectWrongLayout result: DetectionResult, boundaryCharacter: String?) {
        results.append(result)
        boundaryCharacters.append(boundaryCharacter)
    }
}

runSuite("LayoutDetector: Detect EN→RU wrong layout") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    // Type "ghbdtn" (which is "привет" in wrong layout)
    for char in "ghbdtn" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer()

    assert(mockDelegate.results.count == 1, "should detect one wrong layout")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .ukrainian, "target should be Ukrainian")
        assertEqual(result.convertedWord, "привет", "converted should be 'привет'")
    }
}

runSuite("LayoutDetector: Acronym fallback preserves case") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "CR" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer()

    assert(mockDelegate.results.count == 1, "should detect acronym fallback")
    if let result = mockDelegate.results.first {
        assertEqual(result.convertedWord, "СК", "should preserve uppercase mapping")
    }
}

runSuite("LayoutDetector: Valid word does not trigger") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    // Type "hello" (valid English word)
    for char in "hello" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer()

    assertEqual(mockDelegate.results.count, 0, "valid word should not trigger detection")
}

runSuite("LayoutDetector: Mixed scripts ignored") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    // Mixed Latin+Cyrillic should be ignored
    for char in "heллo" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer()

    assertEqual(mockDelegate.results.count, 0, "mixed scripts should not trigger detection")
}

runSuite("LayoutDetector: Delete removes from buffer") {
    let detector = LayoutDetector()

    for char in "hello" {
        detector.addCharacter(String(char))
    }
    assertEqual(detector.currentBuffer, "hello")
    detector.deleteLastCharacter()
    assertEqual(detector.currentBuffer, "hell")
    detector.deleteLastCharacter()
    assertEqual(detector.currentBuffer, "hel")
}

runSuite("LayoutDetector: Reset clears state") {
    let detector = LayoutDetector()
    for char in "hello" {
        detector.addCharacter(String(char))
    }
    detector.reset()
    assertEqual(detector.currentBuffer, "", "buffer should be empty after reset")
}

// =============================================================================
// Synthetic Coverage Tests (EN ↔︎ UK)
// =============================================================================

runSuite("Synthetic: UK → EN coverage") {
    let filterCurrent = DictionaryLoader.shared.bloomFilter(for: .english)
    let filterTarget = DictionaryLoader.shared.bloomFilter(for: .ukrainian)
    var total = 0
    var convertible = 0
    var ambiguous = 0
    var invalidTarget = 0

    forEachDictionaryWord(language: .ukrainian) { word in
        total += 1
        let gibberish = LayoutMapper.convert(word, from: .ukrainian, to: .english)
        let currentValid = filterCurrent.mightContain(gibberish)
        let targetValid = filterTarget.mightContain(word)
        if !targetValid {
            invalidTarget += 1
            return
        }
        if currentValid {
            ambiguous += 1
        } else {
            convertible += 1
        }
    }

    let convertibleRate = total > 0 ? Double(convertible) / Double(total) : 0
    let ambiguousRate = total > 0 ? Double(ambiguous) / Double(total) : 0
    print("  total: \(total), convertible: \(convertible) (\(String(format: "%.2f", convertibleRate * 100))%)")
    print("  ambiguous: \(ambiguous) (\(String(format: "%.2f", ambiguousRate * 100))%), invalid target: \(invalidTarget)")
    assert(total > 0, "ukrainian dictionary should not be empty")
}

runSuite("Synthetic: EN → UK coverage") {
    let filterCurrent = DictionaryLoader.shared.bloomFilter(for: .ukrainian)
    let filterTarget = DictionaryLoader.shared.bloomFilter(for: .english)
    var total = 0
    var convertible = 0
    var ambiguous = 0
    var invalidTarget = 0

    forEachDictionaryWord(language: .english) { word in
        total += 1
        let gibberish = LayoutMapper.convert(word, from: .english, to: .ukrainian)
        let currentValid = filterCurrent.mightContain(gibberish)
        let targetValid = filterTarget.mightContain(word)
        if !targetValid {
            invalidTarget += 1
            return
        }
        if currentValid {
            ambiguous += 1
        } else {
            convertible += 1
        }
    }

    let convertibleRate = total > 0 ? Double(convertible) / Double(total) : 0
    let ambiguousRate = total > 0 ? Double(ambiguous) / Double(total) : 0
    print("  total: \(total), convertible: \(convertible) (\(String(format: "%.2f", convertibleRate * 100))%)")
    print("  ambiguous: \(ambiguous) (\(String(format: "%.2f", ambiguousRate * 100))%), invalid target: \(invalidTarget)")
    assert(total > 0, "english dictionary should not be empty")
}

// =============================================================================
// Summary
// =============================================================================

print("\n========================================")
print("Results: \(passed) passed, \(failed) failed")
if failed > 0 {
    print("TESTS FAILED")
    exit(1)
} else {
    print("ALL TESTS PASSED")
}

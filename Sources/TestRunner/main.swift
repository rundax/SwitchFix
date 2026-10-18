import Foundation
import Core
import Dictionary

DictionaryLoader.shared.enableTextFallbackForTesting()

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

func check(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    assert(condition, message, file: file, line: line)
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
    fflush(stdout)
    block()
    fflush(stdout)
}

func dictionaryPath(for language: Language) -> String {
    let root = FileManager.default.currentDirectoryPath
    return "\(root)/Sources/Dictionary/Resources/\(language.rawValue).txt"
}

func forEachDictionaryWord(language: Language, _ block: @escaping (String) -> Void) {
    let path = dictionaryPath(for: language)
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("  WARN: could not read dictionary at \(path)")
        return
    }

    content.enumerateLines { line, _ in
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

runSuite("LayoutMapper: codex EN ↔ UK") {
    assertEqual(LayoutMapper.convert("codex", from: .english, to: .ukrainian), "сщвуч")
    assertEqual(LayoutMapper.convert("сщвуч", from: .ukrainian, to: .english), "codex")
}

runSuite("LayoutMapper: Ukrainian variants") {
    assertEqual(
        LayoutMapper.convert(
            "seems",
            from: .english,
            to: .ukrainian,
            ukrainianFromVariant: .standard,
            ukrainianToVariant: .standard
        ),
        "іууьі",
        "standard Ukrainian should map 'seems' to 'іууьі'"
    )
    assertEqual(
        LayoutMapper.convert(
            "seems",
            from: .english,
            to: .ukrainian,
            ukrainianFromVariant: .standard,
            ukrainianToVariant: .legacy
        ),
        "иууьи",
        "legacy Ukrainian should map 'seems' to 'иууьи'"
    )
    assertEqual(
        LayoutMapper.convert(
            "иууьи",
            from: .ukrainian,
            to: .english,
            ukrainianFromVariant: .legacy,
            ukrainianToVariant: .standard
        ),
        "seems",
        "legacy Ukrainian text should map back to English correctly"
    )
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
    assert(wv.isValidWord("бы", language: .russian), "common 2-char words should be allowed")
    assert(wv.isValidWord("як", language: .ukrainian), "common 2-char words should be allowed")
    assert(wv.isValidWord("би", language: .ukrainian), "'би' should be allowed in Ukrainian")
    assert(wv.isValidWord("б", language: .ukrainian), "'б' should be allowed in Ukrainian")
    assert(wv.isValidWord("а", language: .ukrainian), "'а' should be allowed in Ukrainian")
    assert(wv.isValidWord("а", language: .russian), "'а' should be allowed in Russian")
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
    assert(wv.isValidWord("seems", language: .english), "'seems' should be valid in English")
    assert(wv.isValidWord("after", language: .english), "'after' should be valid in English")
    assert(wv.isValidWord("expected", language: .english), "'expected' should be valid in English")
    assert(wv.isValidWord("keys", language: .english), "'keys' should be valid in English")
    assert(wv.isValidWord("remove", language: .english), "'remove' should be valid in English")
    assert(wv.isValidWord("removes", language: .english), "'removes' should be valid in English")
    assert(wv.isValidWord("removing", language: .english), "'removing' should be valid in English")
    assert(wv.isValidWord("removed", language: .english), "'removed' should be valid in English")
    assert(wv.isValidWord("changes", language: .english), "'changes' should be valid in English")
    assert(wv.isValidWord("changing", language: .english), "'changing' should be valid in English")
    assert(wv.isValidWord("wholes", language: .english), "'wholes' should be valid in English")
    assert(wv.isValidWord("files", language: .english), "'files' should be valid in English")
    assert(wv.isValidWord("users", language: .english), "'users' should be valid in English")
    assert(wv.isValidWord("lines", language: .english), "'lines' should be valid in English")
    assert(wv.isValidWord("checks", language: .english), "'checks' should be valid in English")
    assert(wv.isValidWord("checking", language: .english), "'checking' should be valid in English")
    assert(wv.isValidWord("typed", language: .english), "'typed' should be valid in English")
    assert(wv.isValidWord("llm", language: .english), "'llm' should be valid in English")
    assert(wv.isValidWord("llms", language: .english), "'llms' should be valid in English")
    assert(wv.isValidWord("LLM", language: .english), "'LLM' should be valid in English")
    assert(wv.isValidWord("replace", language: .english), "'replace' should be valid in English")
    assert(wv.isValidWord("replaces", language: .english), "'replaces' should be valid in English")
    assert(wv.isValidWord("replaced", language: .english), "'replaced' should be valid in English")
    assert(wv.isValidWord("replacing", language: .english), "'replacing' should be valid in English")
    assert(wv.isValidWord("gsd", language: .english), "'gsd' should be valid in English")
    assert(wv.isValidWord("GSD", language: .english), "'GSD' should be valid in English")
    assert(wv.isValidWord("vs", language: .english), "'vs' should be valid in English")
    assert(wv.isValidWord("VS", language: .english), "'VS' should be valid in English")
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
    assert(wv.isValidWord("подивимось", language: .ukrainian), "'подивимось' should be valid in Ukrainian")
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

runSuite("WordValidator: Script mismatch rejected") {
    let wv = WordValidator.shared
    assert(!wv.isValidWord("феефсрштп", language: .english), "Cyrillic word should NOT be valid in English")
    assert(!wv.isValidWord("hello", language: .ukrainian), "Latin word should NOT be valid in Ukrainian")
}

runSuite("WordValidator: Short false positives avoided") {
    let wv = WordValidator.shared
    assert(!wv.isValidWord("дуе", language: .ukrainian), "'дуе' should NOT be treated as valid Ukrainian word")
    assert(!wv.isExactWord("фаеук", language: .ukrainian), "'фаеук' should NOT be an exact Ukrainian dictionary word")
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
        assertEqual(result.targetLayout, .russian, "target should be Russian")
        assertEqual(result.convertedWord, "привет", "converted should be 'привет'")
    }
}

runSuite("LayoutDetector: Long-word typo suggestions are disabled") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    for char in "pdhdp" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "should not run typo-tolerant whole-dictionary lookup")
}

runSuite("LayoutDetector: Avoid aggressive EN→UK typo suggestion") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    for char in "fethc" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "should not auto-correct 'fethc' to unrelated Ukrainian word")
}

runSuite("LayoutDetector: Do not suggest for vowel-rich English words") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "only" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "should not auto-correct 'only' to Ukrainian suggestions")
}

runSuite("LayoutDetector: Reject EN→UK bloom false positives") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "after" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "should not convert 'after' to non-exact Ukrainian word")
}

runSuite("LayoutDetector: Convert English 'Ot' to Ukrainian 'Ще' short word") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "Ot" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert short whitelisted Ukrainian word")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .ukrainian, "target should be Ukrainian")
        assertEqual(result.convertedWord, "Ще", "should convert to 'Ще'")
    }
}

runSuite("LayoutDetector: Convert Ukrainian 'фаеук' to English 'after'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "фаеук" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert wrong-layout Ukrainian buffer to English")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "after", "should convert to 'after'")
    }
}

runSuite("LayoutDetector: Convert English 'gjlsdsvjcm' to Ukrainian 'подивимось'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    detector.ukrainianToVariant = .legacy

    for char in "gjlsdsvjcm" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert to 'подивимось'")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .ukrainian, "target should be Ukrainian")
        assertEqual(result.convertedWord, "подивимось", "should convert to 'подивимось'")
    }
}

runSuite("LayoutDetector: Convert Ukrainian 'учзусеув' to English 'expected'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "учзусеув" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert to 'expected'")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "expected", "should convert to 'expected'")
    }
}

runSuite("LayoutDetector: Convert Ukrainian 'сщвуч' to English 'codex'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "сщвуч" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert to 'codex'")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "codex", "should convert to 'codex'")
    }
}

runSuite("LayoutDetector: Convert Ukrainian 'ершиЖ' to English 'this:'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "ершиЖ" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert legacy Ukrainian typed 'this:'")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "this:", "should preserve trailing colon")
    }
}

runSuite("LayoutDetector: Convert Ukrainian 'дуе' to English 'let'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "дуе" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should detect wrong layout for 'дуе'")
    if let result = mockDelegate.results.first {
        assertEqual(result.sourceLayout, .ukrainian, "source should be Ukrainian")
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "let", "should convert 'дуе' to 'let'")
    }
}

runSuite("LayoutDetector: Ukrainian variant fallback converts legacy word to English") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian
    detector.ukrainianFromVariant = .standard
    detector.ukrainianToVariant = .standard

    for char in "Иууьи" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should recover from wrong Ukrainian variant assumption")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "Seems", "should convert to 'Seems'")
    }
}

runSuite("LayoutDetector: Convert English ',s' to Ukrainian 'би'") {
    // 1. With ukrainianToVariant = .legacy (direct mapping)
    do {
        let detector = LayoutDetector()
        let mockDelegate = MockDetectorDelegate()
        detector.delegate = mockDelegate
        detector.currentLayout = .english
        detector.ukrainianToVariant = .legacy

        for char in ",s" {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")

        assertEqual(mockDelegate.results.count, 1, "should detect and convert ',s' to 'би'")
        if let result = mockDelegate.results.first {
            assertEqual(result.targetLayout, .ukrainian, "target should be Ukrainian")
            assertEqual(result.convertedWord, "би", "should convert ',s' to 'би'")
        }
    }

    // 2. With ukrainianToVariant = .standard (fallback mapping)
    do {
        let detector = LayoutDetector()
        let mockDelegate = MockDetectorDelegate()
        detector.delegate = mockDelegate
        detector.currentLayout = .english
        detector.ukrainianToVariant = .standard

        for char in ",s" {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")

        assertEqual(mockDelegate.results.count, 1, "should detect and convert ',s' to 'би' via variant fallback")
        if let result = mockDelegate.results.first {
            assertEqual(result.targetLayout, .ukrainian, "target should be Ukrainian")
            assertEqual(result.convertedWord, "би", "should convert ',s' to 'би'")
        }
    }
}

runSuite("LayoutDetector: English words with inflections are never converted to Ukrainian") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    detector.ukrainianToVariant = .legacy

    let testWords = ["keys", "remove", "removes", "removing", "removed", "changes", "wholes", "files", "users", "lines", "checks", "typed"]
    for word in testWords {
        mockDelegate.results.removeAll()
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
        assertEqual(mockDelegate.results.count, 0, "'\(word)' in English layout should NOT be corrected or converted")
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

runSuite("LayoutDetector: All-caps English token is not auto-corrected") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "GDPR" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "all-caps English acronym should not auto-correct to Cyrillic")
}

runSuite("LayoutDetector: Acronym fallback suppressed in strong current context") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    func typeWord(_ word: String) {
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
    }

    typeWord("another")
    typeWord("issue")
    typeWord("with")
    typeWord("DB")

    assertEqual(mockDelegate.results.count, 0, "acronym should not auto-correct inside strong English context")
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

runSuite("LayoutDetector: Ambiguous valid word waits for neighboring layout evidence") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    func typeWord(_ word: String) {
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
    }

    typeWord("еру")
    assertEqual(mockDelegate.results.count, 0, "valid Ukrainian 'еру' must not be rewritten in isolation")

    typeWord("middle")
    assertEqual(mockDelegate.results.count, 1, "neighboring English evidence should confirm the deferred word")
    if let result = mockDelegate.results.first {
        assertEqual(result.originalWord, "еру middle")
        assertEqual(result.convertedWord, "the middle")
        assertEqual(result.targetLayout, .english)
    }
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

runSuite("LayoutDetector: Suppress ambiguous short correction in Ukrainian context") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    func typeWord(_ word: String) {
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
    }

    typeWord("зараз")
    typeWord("ссилка")
    typeWord("на")
    typeWord("мейл")
    typeWord("ше")

    assertEqual(mockDelegate.results.count, 0, "short ambiguous word should not be auto-corrected inside a strong Ukrainian context")
}

runSuite("LayoutDetector: Isolated ambiguous short word can still correct") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "ше" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "isolated short wrong-layout word should still be corrected")
    if let result = mockDelegate.results.first {
        assertEqual(result.convertedWord, "it", "expected keyboard-layout conversion to English")
    }
}

runSuite("LayoutDetector: Merge suppressed short word when next word confirms layout") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian
    detector.ukrainianFromVariant = .legacy

    func typeWord(_ word: String) {
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
    }

    // Build a strong Ukrainian context first, so "ше" is suppressed as ambiguous.
    typeWord("зараз")
    typeWord("на")

    for char in "ше" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")
    assertEqual(mockDelegate.results.count, 0, "first ambiguous short word should stay pending")

    for char in "цщкли" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "detector should emit a single merged correction")
    if let result = mockDelegate.results.first {
        assertEqual(result.originalWord, "ше цщкли", "should delete both words in one correction")
        assertEqual(result.convertedWord, "it works", "should restore intended English phrase")
    }
}

runSuite("LayoutDetector: Convert Ukrainian 'Ш' followed by 'цфте' to English 'I want'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "Ш" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    for char in "цфте" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assert(mockDelegate.results.count >= 1, "should emit correction for Ш / цфте")
    if mockDelegate.results.count == 1 {
        let result = mockDelegate.results[0]
        assertEqual(result.originalWord, "Ш цфте")
        assertEqual(result.convertedWord, "I want")
    } else if mockDelegate.results.count == 2 {
        assertEqual(mockDelegate.results[0].convertedWord, "I")
        assertEqual(mockDelegate.results[1].convertedWord, "want")
    }
}

runSuite("LayoutDetector: Convert English 'f' followed by 'ns' to Ukrainian 'а ті' (standard)") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    detector.ukrainianToVariant = .standard

    for char in "f" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    for char in "ns" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assert(mockDelegate.results.count >= 1, "should emit correction for f / ns")
    if let result = mockDelegate.results.first {
        assertEqual(result.originalWord, "f ns")
        assertEqual(result.convertedWord, "а ті")
        assertEqual(result.targetLayout, .ukrainian)
    }
}

runSuite("LayoutDetector: Convert English 'f' followed by 'ns' to Ukrainian 'а ти' (legacy)") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    detector.ukrainianToVariant = .legacy

    for char in "f" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    for char in "ns" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assert(mockDelegate.results.count >= 1, "should emit correction for f / ns")
    if let result = mockDelegate.results.first {
        assertEqual(result.originalWord, "f ns")
        assertEqual(result.convertedWord, "а ти")
        assertEqual(result.targetLayout, .ukrainian)
    }
}

runSuite("LayoutDetector: Reset drops suppressed cross-context history") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian
    detector.ukrainianFromVariant = .legacy

    func typeWord(_ word: String) {
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
    }

    typeWord("зараз")
    typeWord("на")
    typeWord("ше")
    assertEqual(mockDelegate.results.count, 0, "ambiguous short word should be pending before reset")

    detector.reset()
    typeWord("цщкли")

    assertEqual(mockDelegate.results.count, 1, "new context should correct only its own word")
    if let result = mockDelegate.results.first {
        assertEqual(result.originalWord, "цщкли", "reset must not merge text from an earlier context")
        assertEqual(result.convertedWord, "works", "current-context conversion should remain intact")
    }
}

runSuite("LayoutDetector: Standalone ':' is never converted to 'Ж' without context") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    detector.addCharacter(":")
    detector.flushBuffer(boundaryCharacter: "\n")

    assertEqual(mockDelegate.results.count, 0, "standalone ':' without context must not be converted to 'Ж'")
}

runSuite("LayoutDetector: Standalone ':' in English context is not converted to 'Ж'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    func typeWord(_ word: String) {
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
    }

    typeWord("The")
    typeWord("goal")
    typeWord("is")

    detector.addCharacter(":")
    detector.flushBuffer(boundaryCharacter: "\n")

    assertEqual(mockDelegate.results.count, 0, "standalone ':' after English words must not be converted to 'Ж'")
}

runSuite("LayoutDetector: Standalone ':' in Ukrainian context can be converted to 'Ж'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    // Type "Wt" (wrong layout for "Це" in Ukrainian)
    for char in "Wt" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "'Wt' should be corrected to 'Це'")

    // Now type ":" in the resulting Ukrainian context
    detector.addCharacter(":")
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 2, "standalone ':' in Ukrainian context should be detected")
    if mockDelegate.results.count == 2 {
        assertEqual(mockDelegate.results[1].convertedWord, "Ж", "should convert to 'Ж'")
        assertEqual(mockDelegate.results[1].targetLayout, .ukrainian)
    }
}

runSuite("LayoutDetector: Standalone ';' is not converted to 'ж' without context") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    detector.addCharacter(";")
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "standalone ';' without context must not be converted to 'ж'")
}

runSuite("LayoutDetector: Standalone ',' is not converted to 'б' without context") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    detector.addCharacter(",")
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "standalone ',' without context must not be converted to 'б'")
}

runSuite("LayoutDetector: Do not replace isolated single char '-r' to '-к'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "-r" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "isolated '-r' without context must not be converted to '-к'")
}

runSuite("LayoutDetector: Do not replace isolated single char 'r' to 'к'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    detector.addCharacter("r")
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "isolated 'r' without context must not be converted to 'к'")
}

runSuite("LayoutDetector: Do not replace '-r' after English words (chars from -r)") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    func typeWord(_ word: String) {
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
    }

    typeWord("chars")
    typeWord("from")
    typeWord("-r")

    assertEqual(mockDelegate.results.count, 0, "'-r' after English words must not be converted to '-к'")
}

runSuite("LayoutDetector: Convert 'r' followed by Russian word 'dhfx' to 'к врач'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "r" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    for char in "dhfx" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assert(mockDelegate.results.count >= 1, "should emit correction for r / dhfx")
    if let result = mockDelegate.results.first {
        assertEqual(result.originalWord, "r dhfx")
        assertEqual(result.convertedWord, "к врач")
        assertEqual(result.targetLayout, .russian)
    }
}

runSuite("LayoutDetector: Convert 'r' to 'к' when target Russian context exists") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    // Type "gjitk" (wrong layout for "пошел" in Russian)
    for char in "gjitk" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "'gjitk' should be corrected to 'пошел'")

    // Now type "r" in the resulting Russian context
    detector.addCharacter("r")
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 2, "'r' in Russian context should be detected as 'к'")
    if mockDelegate.results.count == 2 {
        assertEqual(mockDelegate.results[1].convertedWord, "к")
        assertEqual(mockDelegate.results[1].targetLayout, .russian)
    }
}

runSuite("LayoutDetector: Convert English 'futynf' to Ukrainian 'агента'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    detector.activeSourceSupportedLayouts = [.english]
    detector.allowedLayouts = [.english, .ukrainian]

    for char in "futynf" {
        detector.addCharacter(String(char))
    }
    let result = detector.flushBuffer(boundaryCharacter: " ")
    assert(result != nil, "should detect 'futynf' as wrong layout")
    assertEqual(result?.targetLayout, .ukrainian)
    assertEqual(result?.convertedWord, "агента")
    assertEqual(result?.originalWord, "futynf")
    assert(result?.shouldSwitchLayout == true, "should switch layout to Ukrainian")
}

runSuite("LayoutDetector: Desynchronized layout-only switch for Ukrainian 'агента' in English layout") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    detector.activeSourceSupportedLayouts = [.english]
    detector.allowedLayouts = [.english, .ukrainian]

    for char in "агента" {
        detector.addCharacter(String(char))
    }
    let result = detector.flushBuffer(boundaryCharacter: " ")
    assert(result != nil, "should detect desynchronized Ukrainian word 'агента' in English layout")
    assertEqual(result?.sourceLayout, .english)
    assertEqual(result?.targetLayout, .ukrainian)
    assertEqual(result?.convertedWord, "агента")
    assertEqual(result?.originalWord, "агента")
    assert(result?.shouldSwitchLayout == true, "should switch layout to Ukrainian")
}

runSuite("LayoutDetector: English 'vs' is not converted to Ukrainian 'ми'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    detector.activeSourceSupportedLayouts = [.english]
    detector.allowedLayouts = [.english, .ukrainian]

    for char in "vs" {
        detector.addCharacter(String(char))
    }
    let result = detector.flushBuffer(boundaryCharacter: " ")
    assertEqual(mockDelegate.results.count, 0, "English 'vs' must not be converted to 'ми'")
    assert(result == nil, "'vs' should be kept as valid English")
}

// =============================================================================
// Custom Keyboard Layout & Hybrid Discovery Tests (Plan 005)
// =============================================================================

runSuite("InputSourceDiscoveryEngine: Tier 1 language metadata") {
    let ukProvider = MockInputSourcePropertyReader(
        id: "custom.keylayout.ukrainian",
        localizedName: "Custom Ukrainian",
        languages: ["uk-UA"]
    )
    let ukDesc = InputSourceDiscoveryEngine.classify(provider: ukProvider)
    assert(ukDesc != nil, "should classify provider with 'uk-UA' language")
    assertEqual(ukDesc?.supportedLayouts, Set([.ukrainian]), "should map to .ukrainian")
    assert(ukDesc?.isCustom == true, "should mark as custom")

    let ruProvider = MockInputSourcePropertyReader(
        id: "custom.keylayout.russian",
        localizedName: "Custom Russian",
        languages: ["ru-RU"]
    )
    let ruDesc = InputSourceDiscoveryEngine.classify(provider: ruProvider)
    assert(ruDesc != nil, "should classify provider with 'ru-RU' language")
    assertEqual(ruDesc?.supportedLayouts, Set([.russian]), "should map to .russian")

    let enProvider = MockInputSourcePropertyReader(
        id: "custom.keylayout.english",
        localizedName: "Custom English",
        languages: ["en-US"]
    )
    let enDesc = InputSourceDiscoveryEngine.classify(provider: enProvider)
    assertEqual(enDesc?.supportedLayouts, Set([.english]), "should map to .english")
}

runSuite("InputSourceDiscoveryEngine: Tier 2 token & name heuristics") {
    let birmanProvider = MockInputSourcePropertyReader(
        id: "org.sil.ukelele.keyboardlayout.ru-ua-birman",
        localizedName: "Russian - Ilya Birman Typography",
        languages: []
    )
    let birmanDesc = InputSourceDiscoveryEngine.classify(provider: birmanProvider)
    assert(birmanDesc != nil, "should classify Birman layout from tokens")
    assertEqual(birmanDesc?.supportedLayouts, Set([.russian, .ukrainian]), "Birman layout should support both Russian and Ukrainian")
    assert(birmanDesc?.isCustom == true, "Birman layout should be marked as custom")

    let colemakProvider = MockInputSourcePropertyReader(
        id: "com.custom.colemak",
        localizedName: "Colemak Mod-DH",
        languages: nil
    )
    let colemakDesc = InputSourceDiscoveryEngine.classify(provider: colemakProvider)
    assertEqual(colemakDesc?.supportedLayouts, Set([.english]), "Colemak should map to .english")

    let dvorakProvider = MockInputSourcePropertyReader(
        id: "org.unknown.keylayout.DvorakSpecial",
        localizedName: "Custom Dvorak",
        languages: nil
    )
    let dvorakDesc = InputSourceDiscoveryEngine.classify(provider: dvorakProvider)
    assertEqual(dvorakDesc?.supportedLayouts, Set([.english]), "Dvorak should map to .english")
}

runSuite("InputSourceDiscoveryEngine: Tier 3 UCKeyTranslate probing") {
    let unshifted: [UInt16: Character] = [
        0: "ф",
        1: "ы",
        12: "й",
        30: "ъ",
        39: "э"
    ]
    let option: [UInt16: Character] = [
        1: "і",
        5: "ґ",
        30: "ї",
        39: "є"
    ]
    let probedBirman = MockInputSourcePropertyReader(
        id: "com.unknown.layout.custom",
        localizedName: "Typographic Layout",
        languages: nil,
        unshiftedKeys: unshifted,
        optionKeys: option
    )
    let probedDesc = InputSourceDiscoveryEngine.classify(provider: probedBirman)
    assert(probedDesc != nil, "should classify layout with Cyrillic unshifted + Ukrainian Option keys")
    assertEqual(probedDesc?.supportedLayouts, Set([.russian, .ukrainian]), "should detect hybrid Russian + Ukrainian from probing")
}

runSuite("InputSourceDiscoveryEngine: Ukrainian variant detection") {
    let standardProvider = MockInputSourcePropertyReader(
        id: "custom.ukrainian.standard",
        localizedName: "Ukrainian Custom",
        languages: ["uk"],
        unshiftedKeys: [1: "і", 11: "и"]
    )
    let standardDesc = InputSourceDiscoveryEngine.classify(provider: standardProvider)
    assertEqual(standardDesc?.ukrainianVariant, .standard, "should detect standard variant")

    let legacyProvider = MockInputSourcePropertyReader(
        id: "custom.ukrainian.legacy",
        localizedName: "Ukrainian Legacy Custom",
        languages: ["uk"],
        unshiftedKeys: [1: "и", 11: "і"]
    )
    let legacyDesc = InputSourceDiscoveryEngine.classify(provider: legacyProvider)
    assertEqual(legacyDesc?.ukrainianVariant, .legacy, "should detect legacy variant")
}

runSuite("Hybrid Layout: Multi-language validation without correction (No Death Spiral)") {
    let detector = LayoutDetector()
    detector.activeSourceSupportedLayouts = [.russian, .ukrainian]
    detector.currentLayout = .russian
    detector.currentInputSourceID = "org.sil.ukelele.keyboardlayout.ru-ua-birman"
    detector.preferredSourceIDProvider = { layout in
        layout == .english ? "com.apple.keylayout.ABC" : "org.sil.ukelele.keyboardlayout.ru-ua-birman"
    }

    let ukrainianWords = ["привіт", "єдина", "справи", "сьогодні", "перевірка"]
    for word in ukrainianWords {
        for char in word {
            detector.addCharacter(String(char))
        }
        let result = detector.flushBuffer(boundaryCharacter: " ")
        assert(result == nil, "Ukrainian word '\(word)' on hybrid Birman layout must NOT be corrected or flickered")
    }

    let russianWords = ["привет", "хорошо", "погода", "сегодня", "проверка"]
    for word in russianWords {
        for char in word {
            detector.addCharacter(String(char))
        }
        let result = detector.flushBuffer(boundaryCharacter: " ")
        assert(result == nil, "Russian word '\(word)' on hybrid Birman layout must NOT be corrected")
    }
}

runSuite("Hybrid Layout: Mistype on Birman switches to ABC") {
    let detector = LayoutDetector()
    detector.activeSourceSupportedLayouts = [.russian, .ukrainian]
    detector.currentLayout = .russian
    detector.currentInputSourceID = "org.sil.ukelele.keyboardlayout.ru-ua-birman"
    detector.preferredSourceIDProvider = { layout in
        layout == .english ? "com.apple.keylayout.ABC" : "org.sil.ukelele.keyboardlayout.ru-ua-birman"
    }

    for char in "руддщ" {
        detector.addCharacter(String(char))
    }
    let result = detector.flushBuffer(boundaryCharacter: " ")
    assert(result != nil, "'руддщ' should be detected as wrong layout")
    assertEqual(result?.targetLayout, .english)
    assertEqual(result?.convertedWord, "hello")
    assert(result?.shouldSwitchLayout == true, "should switch to English")
}

runSuite("Hybrid Layout: Different layout on shared source still corrects") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.activeSourceSupportedLayouts = [.english, .ukrainian]
    detector.currentLayout = .english
    detector.currentInputSourceID = "test.hybrid"
    detector.allowedLayouts = [.ukrainian]
    detector.preferredSourceIDProvider = { _ in "test.hybrid" }

    for char in "ghbdsn" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "shared physical source must not suppress a different logical layout")
    assertEqual(mockDelegate.results.first?.targetLayout, .ukrainian)
    assertEqual(mockDelegate.results.first?.convertedWord, "привіт")
}

runSuite("Hybrid Layout: Self-switch suppression") {
    let detector = LayoutDetector()
    detector.activeSourceSupportedLayouts = [.russian, .ukrainian]
    detector.currentLayout = .russian
    detector.currentInputSourceID = "org.sil.ukelele.keyboardlayout.ru-ua-birman"
    detector.preferredSourceIDProvider = { _ in
        "org.sil.ukelele.keyboardlayout.ru-ua-birman"
    }

    assertEqual(detector.currentInputSourceID, detector.preferredSourceIDProvider?(.ukrainian))
}

runSuite("InputSourceDiscoveryEngine: Apple native Ukrainian layout ignores Option probing for Russian") {
    let appleUkProvider = MockInputSourcePropertyReader(
        id: "com.apple.keylayout.Ukrainian",
        localizedName: "Ukrainian",
        languages: ["uk"],
        unshiftedKeys: [0: "ф", 1: "і", 11: "и", 12: "й", 30: "ї", 39: "є"],
        optionKeys: [1: "ы", 5: "ґ", 30: "ъ", 39: "э"]
    )
    let desc = InputSourceDiscoveryEngine.classify(provider: appleUkProvider)
    assert(desc != nil, "should classify Apple Ukrainian layout")
    assertEqual(desc?.supportedLayouts, Set([.ukrainian]), "native Ukrainian must not claim Russian layout via Option probing")
    assertEqual(desc?.isCustom, false, "Apple native layout is not custom")
}

runSuite("InputSourceDiscoveryEngine: Apple native layout is classified by its primary language only") {
    // What macOS reports for "Ukrainian – Legacy": every language its script can write.
    let appleUkProvider = MockInputSourcePropertyReader(
        id: "com.apple.keylayout.Ukrainian",
        localizedName: "Ukrainian – Legacy",
        languages: ["uk", "be", "bg", "bs_Cyrl", "mk", "myv", "ru", "sr", "sr_Cyrl"],
        unshiftedKeys: [0: "ф", 1: "и", 11: "і", 12: "й", 30: "ї", 39: "є"]
    )
    let appleDesc = InputSourceDiscoveryEngine.classify(provider: appleUkProvider)
    assertEqual(appleDesc?.supportedLayouts, Set([.ukrainian]), "'ru' further down Apple's list must not make the Ukrainian layout a Russian one")
    assertEqual(appleDesc?.ukrainianVariant, .legacy, "legacy variant is still detected")

    let customProvider = MockInputSourcePropertyReader(
        id: "org.example.keylayout.cyrillic-duo",
        localizedName: "Cyrillic Duo",
        languages: ["uk", "ru"]
    )
    let customDesc = InputSourceDiscoveryEngine.classify(provider: customProvider)
    assertEqual(customDesc?.supportedLayouts, Set([.ukrainian, .russian]), "third-party layouts keep every language they declare")
}

runSuite("WordValidator: 'VNC' and 'vnc' are recognized as valid English words via allow override") {
    assert(WordValidator.shared.validate("vnc", language: .english).isValid, "'vnc' should be valid English")
    assert(WordValidator.shared.validate("VNC", language: .english).isValid, "'VNC' should be valid English")
}

runSuite("WordValidator: 'блін' is recognized as a valid Ukrainian word via allow override") {
    let result = WordValidator.shared.validate("блін", language: .ukrainian)
    assert(result.isValid, "'блін' should be a valid word in Ukrainian")
}

func flushWord(_ detector: LayoutDetector, _ word: String) -> DetectionResult? {
    detector.discardBuffer()
    for char in word {
        detector.addCharacter(String(char))
    }
    return detector.flushBuffer(boundaryCharacter: " ")
}

runSuite("LayoutDetector: Cyrillic source is never converted to another Cyrillic layout") {
    let detector = LayoutDetector()
    detector.currentLayout = .ukrainian
    detector.ukrainianFromVariant = .legacy
    detector.allowedLayouts = [.english, .ukrainian, .russian]
    assert(flushWord(detector, "блін") == nil, "'блін' must not be converted to Russian 'блин'")
    assert(flushWord(detector, "єто") == nil, "'єто' must not be converted to Russian 'это'")
    detector.currentLayout = .russian
    assert(flushWord(detector, "вы") == nil || flushWord(detector, "вы")?.targetLayout == .english,
           "Russian text must never become Ukrainian")
}

runSuite("LayoutMapper: Ukrainian <-> Russian conversion is the identity") {
    assertEqual(LayoutMapper.convert("єто", from: .ukrainian, to: .russian), "єто", "UK→RU must not convert")
    assertEqual(LayoutMapper.convert("вы", from: .russian, to: .ukrainian), "вы", "RU→UK must not convert")
    let targets = LayoutMapper.convertToAlternatives("вы", from: .russian).map { $0.0 }
    assertEqual(targets, [.english], "a Cyrillic source may only convert to English")
}

runSuite("LayoutDetector: Latin typed under Ukrainian layout is never replaced by Russian") {
    let detector = LayoutDetector()
    detector.currentLayout = .ukrainian
    detector.currentInputSourceID = "com.apple.keylayout.Ukrainian"
    detector.activeSourceSupportedLayouts = [.ukrainian]
    detector.allowedLayouts = [.english, .ukrainian, .russian]
    detector.preferredSourceIDProvider = { layout in layout == .ukrainian ? "com.apple.keylayout.Ukrainian" : nil }
    detector.preferredCyrillicLayout = .ukrainian
    assert(flushWord(detector, "ds") == nil, "'ds' under Ukrainian must not become Russian 'вы'")
    detector.preferredCyrillicLayout = nil
    assert(flushWord(detector, "ds") == nil, "'ds' under Ukrainian must not become Russian even without history")
}

runSuite("LayoutDetector: Latin text converts only to the last-used Cyrillic layout") {
    let detector = LayoutDetector()
    detector.currentLayout = .english
    detector.currentInputSourceID = "com.apple.keylayout.ABC"
    detector.activeSourceSupportedLayouts = [.english]
    detector.allowedLayouts = [.english, .ukrainian, .russian]
    detector.preferredSourceIDProvider = { _ in nil }

    detector.preferredCyrillicLayout = .ukrainian
    let ua = flushWord(detector, "ghbdsn")
    assertEqual(ua?.targetLayout, .ukrainian, "Latin 'ghbdsn' should convert to Ukrainian when UA was last used")
    assertEqual(ua?.convertedWord, "привіт", "converted word should be Ukrainian 'привіт'")

    detector.preferredCyrillicLayout = .russian
    let ru = flushWord(detector, "ghbdtn")
    assertEqual(ru?.targetLayout, .russian, "Latin 'ghbdtn' should convert to Russian when RU was last used")
    assertEqual(ru?.convertedWord, "привет", "converted word should be Russian 'привет'")

    detector.preferredCyrillicLayout = .ukrainian
    assert(flushWord(detector, "ds")?.targetLayout != .russian, "'ds' must not become Russian 'вы' when UA was last used")
}

// =============================================================================
// Run-level context: words typed back-to-back share one layout
// =============================================================================

runSuite("LayoutDetector: Ambiguous word outlives a short neighbour until the run resolves") {
    let detector = LayoutDetector()
    detector.currentLayout = .ukrainian

    assert(flushWord(detector, "філ") == nil, "valid Ukrainian 'філ' must not be rewritten in isolation")
    let me = flushWord(detector, "ьу")
    assertEqual(me?.originalWord, "ьу", "a lone two-letter word is too weak to drag the ambiguous word along")
    assertEqual(me?.convertedWord, "me")

    let more = flushWord(detector, "ьщку")
    assertEqual(more?.originalWord, "філ me ьщку", "the confirming word must reach back over everything on screen since the run began")
    assertEqual(more?.convertedWord, "ask me more")
    assertEqual(more?.targetLayout, .english)
    assert(more?.shouldSwitchLayout == true, "a resolved run switches the layout")
}

runSuite("LayoutDetector: Ambiguous words of any length are reachable") {
    let detector = LayoutDetector()
    detector.currentLayout = .ukrainian

    assert(flushWord(detector, "туче") == nil, "valid Ukrainian 'туче' must not be rewritten in isolation")
    let more = flushWord(detector, "ьщку")
    assertEqual(more?.originalWord, "туче ьщку")
    assertEqual(more?.convertedWord, "next more")
}

runSuite("LayoutDetector: Words already corrected are not retyped") {
    let detector = LayoutDetector()
    detector.currentLayout = .ukrainian
    detector.ukrainianFromVariant = .legacy

    assertEqual(flushWord(detector, "фил")?.convertedWord, "ask", "'фил' is not Ukrainian, so it converts on its own")
    let me = flushWord(detector, "ьу")
    assertEqual(me?.originalWord, "ьу", "the second word must not delete and retype the first")
    assert(me?.shouldSwitchLayout == true, "two agreeing short words switch the layout")

    let mixed = LayoutDetector()
    mixed.currentLayout = .ukrainian
    mixed.ukrainianFromVariant = .legacy
    assertEqual(flushWord(mixed, "фил")?.convertedWord, "ask")
    assert(flushWord(mixed, "еру") == nil, "'еру' stands as typed")
    let more = flushWord(mixed, "ьщку")
    assertEqual(more?.originalWord, "еру ьщку", "the sweep starts at the first word that changes, not at one already corrected")
    assertEqual(more?.convertedWord, "the more")
}

runSuite("LayoutDetector: Ambiguous word sides with the Ukrainian text before it") {
    let detector = LayoutDetector()
    detector.currentLayout = .ukrainian
    detector.ukrainianFromVariant = .legacy

    assert(flushWord(detector, "лист") == nil, "'лист' is plain Ukrainian")
    assert(flushWord(detector, "від") == nil, "'від' also reads as English 'dbl', but stands as typed")
    let google = flushWord(detector, "пщщпду")
    assertEqual(google?.originalWord, "пщщпду", "'від' follows a word that only makes sense in Ukrainian and must stay")
    assertEqual(google?.convertedWord, "google")
}

runSuite("LayoutDetector: Ambiguous word sides with the English text before it") {
    let detector = LayoutDetector()
    detector.currentLayout = .english

    assert(flushWord(detector, "check") == nil, "'check' is plain English")
    assert(flushWord(detector, "the") == nil, "'the' also reads as Ukrainian 'еру', but stands as typed")
    let hello = flushWord(detector, "ghbdsn")
    assertEqual(hello?.originalWord, "ghbdsn", "'the' follows a word that only makes sense in English and must stay")
    assertEqual(hello?.convertedWord, "привіт")
}

runSuite("LayoutDetector: Run sweep stops at Enter and at words it cannot place") {
    do {
        let detector = LayoutDetector()
        detector.currentLayout = .ukrainian
        detector.addCharacter("еру")
        assert(detector.flushBuffer(boundaryCharacter: "\n") == nil, "'еру' stands as typed")
        let middle = flushWord(detector, "ьшввду")
        assertEqual(middle?.originalWord, "ьшввду", "text before Enter may already be submitted and must not be rewritten")
        assertEqual(middle?.convertedWord, "middle")
    }
    do {
        let detector = LayoutDetector()
        detector.currentLayout = .ukrainian
        assert(flushWord(detector, "еру") == nil, "'еру' stands as typed")
        assert(flushWord(detector, "щщщщ") == nil, "'щщщщ' is a word in neither layout")
        let middle = flushWord(detector, "ьшввду")
        assertEqual(middle?.originalWord, "ьшввду", "the sweep must not jump over a word it cannot convert")
    }
}

// The same rules through the real InputEngine, where the delete count decides what the app loses.

final class CorrectionPlanLog: @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [CorrectionPlan] = []
    func add(_ plan: CorrectionPlan) { lock.lock(); plans.append(plan); lock.unlock() }
    func all() -> [CorrectionPlan] { lock.lock(); defer { lock.unlock() }; return plans }
}

enum TypedKey {
    case text(String)
    case space
    case backspace
}

func typeOnUkrainianLayout(_ keys: [TypedKey], variant: UkrainianKeyboardVariant) -> [CorrectionPlan] {
    let context = InputContextSnapshot(
        epoch: 1,
        frontmostPID: 100,
        appAllowed: true,
        layout: .ukrainian,
        inputSourceID: "com.apple.keylayout.Ukrainian",
        secureFocus: .notSecure
    )
    let store = CaptureStateStore(context: context, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let log = CorrectionPlanLog()
    let detector = LayoutDetector()
    detector.preferredSourceIDProvider = { _ in nil }
    let engine = InputEngine(
        captureState: store,
        initialContext: context,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        detector: detector,
        correctionEmission: { plan in
            log.add(plan)
            return true
        }
    )
    engine.updateDetectionConfiguration(
        allowedLayouts: [.english, .ukrainian],
        preferredCyrillicLayout: .ukrainian,
        activeSourceSupportedLayouts: [.ukrainian],
        ukrainianFromVariant: variant,
        ukrainianToVariant: variant
    )
    func send(_ kind: CapturedInput.Kind) {
        engine.enqueue(store.capture(
            timestamp: 0,
            kind: kind,
            keyCode: 0,
            flagsRawValue: 0,
            isAutorepeat: false,
            sourcePID: 1,
            sourceUserData: 0
        ))
    }
    // Detection and emission hop queues, and a correction is dropped if the next key beats it.
    func settle() {
        for _ in 0..<3 {
            let drained = DispatchSemaphore(value: 0)
            engine.drain { drained.signal() }
            drained.wait()
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
    for key in keys {
        switch key {
        case .text(let text):
            for character in text { send(.character(String(character))) }
        case .space:
            send(.boundary(" "))
            settle()
        case .backspace:
            send(.delete)
        }
    }
    return log.all()
}

runSuite("InputEngine: First word typed after backspacing is corrected once the run resolves") {
    let plans = typeOnUkrainianLayout(
        [.backspace, .backspace, .text("фил"), .space, .text("ьу"), .space, .text("йгуиешщти"), .space],
        variant: .legacy
    )
    assertEqual(plans.count, 2, "'ask' may be a fragment and must wait; 'me' and 'questions' each trigger a correction")
    assertEqual(plans.first?.originalText, "ьу")
    assertEqual(plans.last?.originalText, "фил me йгуиешщти")
    assertEqual(plans.last?.correctedText, "ask me questions")
    assertEqual(plans.last?.deleteCount, 17, "three words, two spaces between them and the trailing space")
    assertEqual(plans.last?.targetLayout, .english)
}

runSuite("InputEngine: Run sweep deletes exactly what is on screen") {
    let plans = typeOnUkrainianLayout(
        [.text("філ"), .space, .text("ьу"), .space, .text("ьщку"), .space],
        variant: .standard
    )
    assertEqual(plans.last?.correctedText, "ask me more")
    assertEqual(plans.last?.replacementText, "ask me more ")
    assertEqual(plans.last?.deleteCount, 12)
}

runSuite("InputEngine: Backspacing into a deferred word never deletes the text before it") {
    // Screen after the last space: "еруь " — five characters.
    let plans = typeOnUkrainianLayout(
        [.text("еру"), .space, .backspace, .text("ь"), .space],
        variant: .standard
    )
    assertEqual(plans.count, 1)
    assertEqual(plans.first?.originalText, "еруь", "the reopened word must not also be counted as an earlier word")
    assertEqual(plans.first?.correctedText, "them")
    assertEqual(plans.first?.deleteCount, 5)
}

runSuite("InputEngine: A second space ends the run") {
    // Screen after the last space: "еру  ьшввду " — the journal holds no token for the extra space.
    let plans = typeOnUkrainianLayout(
        [.text("еру"), .space, .space, .text("ьшввду"), .space],
        variant: .standard
    )
    assertEqual(plans.count, 1)
    assertEqual(plans.first?.originalText, "ьшввду", "a span that skips a character would delete one too few")
    assertEqual(plans.first?.deleteCount, 7)
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
// Personal Exceptions (Plan 02 Slice 1)
// =============================================================================

runSuite("PersonalExceptions: Normalization & Canonicalization") {
    // Case variants
    assertEqual(PersonalExceptionsPolicy.canonicalize("Apple"), "apple", "lowercase Apple")
    assertEqual(PersonalExceptionsPolicy.canonicalize("APPLE"), "apple", "lowercase APPLE")
    assertEqual(PersonalExceptionsPolicy.canonicalize("КиЇв"), "київ", "lowercase Ukrainian letters")

    // NFC / NFD canonical composition
    let decomposed = "e\u{0301}"
    let precomposed = "é"
    assertEqual(PersonalExceptionsPolicy.canonicalize(decomposed), precomposed, "NFD must compose to NFC")
    assertEqual(PersonalExceptionsPolicy.canonicalize(precomposed), precomposed, "NFC must stay NFC")

    // All three apostrophes: ASCII, U+2019, U+02BC
    assertEqual(PersonalExceptionsPolicy.canonicalize("don't"), "don't", "ASCII apostrophe")
    assertEqual(PersonalExceptionsPolicy.canonicalize("don’t"), "don't", "U+2019 curly apostrophe")
    assertEqual(PersonalExceptionsPolicy.canonicalize("сімʼя"), "сім'я", "U+02BC modifier letter apostrophe")
    assertEqual(PersonalExceptionsPolicy.canonicalize("м’ясо"), "м'ясо", "Ukrainian curly apostrophe")
    assertEqual(PersonalExceptionsPolicy.canonicalize("мʼясо"), "м'ясо", "Ukrainian modifier letter apostrophe")

    // Diacritics preserved (no accent stripping)
    assertEqual(PersonalExceptionsPolicy.canonicalize("café"), "café", "diacritics must not be stripped")
    assert(PersonalExceptionsPolicy.canonicalize("café") != "cafe", "café is distinct from cafe")

    // Hyphens and backticks remain distinct
    assertEqual(PersonalExceptionsPolicy.canonicalize("foo-bar"), "foo-bar", "hyphen preserved")
    assertEqual(PersonalExceptionsPolicy.canonicalize("foo`bar"), "foo`bar", "backtick preserved")
    assert(PersonalExceptionsPolicy.canonicalize("foo-bar") != PersonalExceptionsPolicy.canonicalize("foo`bar"), "hyphen and backtick are distinct")
    assert(PersonalExceptionsPolicy.canonicalize("foo'bar") != PersonalExceptionsPolicy.canonicalize("foo-bar"), "apostrophe and hyphen are distinct")
}

runSuite("PersonalExceptions: Validation rules & boundaries") {
    // Valid words
    check(PersonalExceptionsPolicy.validate(candidate: "apple") == .success("apple"), "valid word apple")
    check(PersonalExceptionsPolicy.validate(candidate: "don't") == .success("don't"), "valid word don't")
    check(PersonalExceptionsPolicy.validate(candidate: "v2") == .success("v2"), "valid word v2")
    check(PersonalExceptionsPolicy.validate(candidate: "сім'я") == .success("сім'я"), "valid word сім'я")
    check(PersonalExceptionsPolicy.validate(candidate: "foo-bar") == .success("foo-bar"), "valid word foo-bar")
    check(PersonalExceptionsPolicy.validate(candidate: "foo`bar") == .success("foo`bar"), "valid word foo`bar")
    check(PersonalExceptionsPolicy.validate(candidate: "  swift  ") == .success("swift"), "whitespace trimmed before validation")

    // Empty
    check(PersonalExceptionsPolicy.validate(candidate: "") == .failure(.empty), "empty rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "   ") == .failure(.empty), "whitespace-only rejected")

    // Length ceilings: 64 Characters, 256 bytes
    let word64 = String(repeating: "a", count: 64)
    check(PersonalExceptionsPolicy.validate(candidate: word64) == .success(word64), "64 chars accepted")
    let word65 = String(repeating: "a", count: 65)
    check(PersonalExceptionsPolicy.validate(candidate: word65) == .failure(.tooLong(65)), "65 chars rejected")

    // No letters
    check(PersonalExceptionsPolicy.validate(candidate: "12345") == .failure(.noLetters), "pure digits rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "-") == .failure(.noLetters), "pure punctuation rejected")

    // Invalid characters
    check(PersonalExceptionsPolicy.validate(candidate: "foo bar") == .failure(.invalidCharacter(" ")), "space rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "foo\nbar") == .failure(.invalidCharacter("\n")), "newline rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "foo🎉") == .failure(.invalidCharacter("🎉")), "emoji rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "https://apple.com") == .failure(.invalidCharacter(":")), "url rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "/usr/bin") == .failure(.invalidCharacter("/")), "path rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "user@domain") == .failure(.invalidCharacter("@")), "@ rejected")

    // Punctuation positioning
    check(PersonalExceptionsPolicy.validate(candidate: "-foo") == .failure(.invalidPunctuationPosition), "leading hyphen rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "'foo") == .failure(.invalidPunctuationPosition), "leading apostrophe rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "foo-") == .failure(.invalidPunctuationPosition), "trailing hyphen rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "foo'") == .failure(.invalidPunctuationPosition), "trailing apostrophe rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "foo--bar") == .failure(.invalidPunctuationPosition), "adjacent hyphens rejected")
    check(PersonalExceptionsPolicy.validate(candidate: "foo''bar") == .failure(.invalidPunctuationPosition), "adjacent apostrophes rejected")
}

runSuite("PersonalExceptions: Key derivation & matching") {
    // Key derivation from tokens
    assertEqual(PersonalExceptionsPolicy.deriveMatchingKey(from: "foo"), "foo", "derive plain foo")
    assertEqual(PersonalExceptionsPolicy.deriveMatchingKey(from: "foo,"), "foo", "derive foo,")
    assertEqual(PersonalExceptionsPolicy.deriveMatchingKey(from: "foo."), "foo", "derive foo.")
    assertEqual(PersonalExceptionsPolicy.deriveMatchingKey(from: "\"foo"), "foo", "derive \"foo")
    assertEqual(PersonalExceptionsPolicy.deriveMatchingKey(from: "foo!?"), "foo", "derive foo!?")
    assertEqual(PersonalExceptionsPolicy.deriveMatchingKey(from: "don't"), "don't", "derive don't with internal apostrophe")
    assertEqual(PersonalExceptionsPolicy.deriveMatchingKey(from: "don’t"), "don't", "derive don’t with curly apostrophe")
    assertEqual(PersonalExceptionsPolicy.deriveMatchingKey(from: "сімʼя"), "сім'я", "derive сімʼя with U+02BC")
    assertEqual(PersonalExceptionsPolicy.deriveMatchingKey(from: "kj,"), "kj", "derive kj, -> kj (documented collision)")

    // Matching policy
    let policy = PersonalExceptionsPolicy(words: ["foo", "don't", "сім'я", "cafe"])
    check(policy.matches(rawToken: "foo"), "exact match foo")
    check(policy.matches(rawToken: "Foo"), "case variant Foo matches")
    check(policy.matches(rawToken: "FOO"), "all-caps FOO matches")
    check(policy.matches(rawToken: "foo,"), "token with comma foo, matches")
    check(policy.matches(rawToken: "foo."), "token with period foo. matches")
    check(policy.matches(rawToken: "\"foo"), "token with leading quote \"foo matches")
    check(policy.matches(rawToken: "don't"), "don't matches")
    check(policy.matches(rawToken: "don’t"), "don’t with curly apostrophe matches")
    check(policy.matches(rawToken: "сімʼя"), "сімʼя with modifier apostrophe matches")

    // Non-matches (no substring, no prefix, distinct tokens)
    check(!policy.matches(rawToken: "foobar"), "prefix foobar must not match foo")
    check(!policy.matches(rawToken: "foo-bar"), "hyphenated foo-bar must not match foo")
    check(!policy.matches(rawToken: "bar"), "unrelated word must not match")
    check(!policy.matches(rawToken: "café"), "café must not match cafe (accents distinct)")
}

runSuite("PersonalExceptions: Store persistence & isolation") {
    autoreleasepool {
        let suiteName = "com.switchfix.tests.personal-exceptions.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            isolatedDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = PersonalExceptionsStore(defaults: isolatedDefaults)

        // Empty startup
        let initialPolicy = store.loadPolicy()
        check(initialPolicy.isEmpty, "initial store must be empty")
        check(initialPolicy.count == 0, "initial count is 0")

        // Add words
        let add1 = store.add(candidate: "Apple")
        check(add1 == .success(PersonalExceptionsPolicy(words: ["apple"]), addedWord: "apple"), "add Apple succeeds as canonical apple")
        let add2 = store.add(candidate: "don’t")
        check(add2 == .success(PersonalExceptionsPolicy(words: ["apple", "don't"]), addedWord: "don't"), "add don’t succeeds as don't")

        // Duplicate Add
        let addDup = store.add(candidate: "apple")
        check(addDup == .duplicate("apple"), "duplicate add returns duplicate status")

        // Reload from new instance (restart simulation)
        let reloadedStore = PersonalExceptionsStore(defaults: isolatedDefaults)
        let reloadedPolicy = reloadedStore.loadPolicy()
        check(reloadedPolicy.count == 2, "reloaded policy has 2 words")
        check(reloadedPolicy.contains("apple"), "reloaded contains apple")
        check(reloadedPolicy.contains("don't"), "reloaded contains don't")

        // Remove word
        let removedPolicy = store.remove(word: "Apple")
        check(removedPolicy.count == 1, "policy after removal has 1 word")
        check(!removedPolicy.contains("apple"), "apple was removed")
        check(removedPolicy.contains("don't"), "don't remains")

        // Malformed defaults handling
        // 1. Wrong schemaVersion
        isolatedDefaults.set(["schemaVersion": 99, "words": ["corrupted"]], forKey: PersonalExceptionsStore.preferenceKey)
        check(store.loadPolicy().isEmpty, "unknown schemaVersion must default to empty policy")

        // 2. Oversized envelope (> 1,000 items)
        var oversizedWords: [String] = []
        for i in 0..<1001 {
            oversizedWords.append("word\(i)")
        }
        isolatedDefaults.set(["schemaVersion": 1, "words": oversizedWords], forKey: PersonalExceptionsStore.preferenceKey)
        check(store.loadPolicy().isEmpty, "oversized envelope (> 1,000) must default to empty policy")

        // 3. Invalid member inside bounded envelope is skipped, valid members loaded
        isolatedDefaults.set(["schemaVersion": 1, "words": ["valid", "invalid emoji 🎉", "another-valid", "1234"]], forKey: PersonalExceptionsStore.preferenceKey)
        let filteredPolicy = store.loadPolicy()
        check(filteredPolicy.count == 2, "filtered policy should load 2 valid words")
        check(filteredPolicy.contains("valid"), "contains valid")
        check(filteredPolicy.contains("another-valid"), "contains another-valid")
        isolatedDefaults.removePersistentDomain(forName: suiteName)
    }
}

runSuite("PersonalExceptions: Detector current word and layout-only suppression") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    detector.personalExceptions = PersonalExceptionsPolicy(words: ["ghbdsn", "futynf"])

    // "ghbdsn" is normally corrected from EN -> UK ("привіт"). Because it is protected, it must NOT correct.
    for char in "ghbdsn" {
        detector.addCharacter(String(char))
    }
    let res = detector.flushBuffer(boundaryCharacter: " ")
    check(res == nil, "protected word 'ghbdsn' must return nil detection")
    check(mockDelegate.results.isEmpty, "protected word must emit no delegate results")

    // Layout-only prediction suppression: "futynf" is valid Ukrainian ("агента") typed in English layout.
    // It would normally emit a layout-only switch. Because it is protected, it must NOT switch!
    for char in "futynf" {
        detector.addCharacter(String(char))
    }
    let resLayout = detector.flushBuffer(boundaryCharacter: " ")
    check(resLayout == nil, "protected layout-only word 'futynf' must return nil")
    check(mockDelegate.results.isEmpty, "protected layout-only word must emit no switch")
}

runSuite("PersonalExceptions: Detector backward sweep barriers") {
    // 1. Run sweep stops before protected earlier word
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    detector.personalExceptions = PersonalExceptionsPolicy(words: ["ghbdsn"])

    // Type protected word "ghbdsn " (would be "привіт")
    for char in "ghbdsn" { detector.addCharacter(String(char)) }
    _ = detector.flushBuffer(boundaryCharacter: " ")
    check(mockDelegate.results.isEmpty, "first word is protected")

    // Type "hj,jnf " (wrong layout for Ukrainian "робота")
    for char in "hj,jnf" { detector.addCharacter(String(char)) }
    let res = detector.flushBuffer(boundaryCharacter: " ")
    check(res != nil, "second word should correct")
    if let r = res {
        // Must only correct "hj,jnf" -> "робота", NOT sweep across "ghbdsn"!
        assertEqual(r.originalWord, "hj,jnf", "sweep must not cross protected word 'ghbdsn'")
        assertEqual(r.convertedWord, "робота", "converted text must be only 'робота'")
    }

    // 2. Already converted token in journal is protected if its display or typed matches exception
    let detector2 = LayoutDetector()
    detector2.currentLayout = .english
    for char in "hj,jnf" { detector2.addCharacter(String(char)) }
    _ = detector2.flushBuffer(boundaryCharacter: " ")
    detector2.personalExceptions = PersonalExceptionsPolicy(words: ["робота"])

    for char in "ghbdsn" { detector2.addCharacter(String(char)) }
    let res2 = detector2.flushBuffer(boundaryCharacter: " ")
    check(res2 != nil, "second word should correct")
    if let r = res2 {
        assertEqual(r.originalWord, "ghbdsn", "sweep must stop before converted protected word 'робота'")
    }
}

runSuite("PersonalExceptions: Explicit triggers bypass protection") {
    let detector = LayoutDetector()
    detector.currentLayout = .english
    detector.personalExceptions = PersonalExceptionsPolicy(words: ["ghbdsn"])

    // Hotkey trigger bypasses personal exceptions
    detector.currentTrigger = .hotkey
    for char in "ghbdsn" { detector.addCharacter(String(char)) }
    let resHotkey = detector.flushBuffer(boundaryCharacter: nil)
    check(resHotkey != nil, "hotkey trigger must bypass personal exceptions")
    assertEqual(resHotkey?.convertedWord, "привіт", "hotkey must convert protected word")

    // LayoutSwitch trigger bypasses personal exceptions
    detector.currentTrigger = .layoutSwitch
    for char in "ghbdsn" { detector.addCharacter(String(char)) }
    let resSwitch = detector.flushBuffer(boundaryCharacter: nil)
    check(resSwitch != nil, "layoutSwitch trigger must bypass personal exceptions")
}

// =============================================================================
// Performance
// =============================================================================

runDictionaryPerformanceSuites()

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

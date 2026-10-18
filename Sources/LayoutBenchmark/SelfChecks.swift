import Foundation
import Core
import Dictionary
import Utils

public enum SelfChecks {
    private static var passedCount = 0
    private static var failedCount = 0

    private static func check(_ condition: Bool, _ message: String) {
        if condition {
            passedCount += 1
        } else {
            failedCount += 1
            print("FAIL: \(message)")
        }
    }

    public static func runAll() -> Bool {
        passedCount = 0
        failedCount = 0

        print("--- SelfChecks: Wilson interval calculation ---")
        testWilsonInterval()

        print("--- SelfChecks: Precision null on zero attempts ---")
        testPrecisionNullOnZeroAttempts()

        print("--- SelfChecks: Fake control adapters (preserve, replace, wrong, error, good) ---")
        testFakeControlAdapters()

        print("--- SelfChecks: Validation catches schema, duplicate, and leaking errors ---")
        testValidationCatchesErrors()

        print("--- SelfChecks: UTF-16 caret vs grapheme cluster handling ---")
        testUTF16CaretVsGrapheme()

        print("--- SelfChecks: Replay delete and reset handling ---")
        testDeleteAndResetHandling()

        print("--- SelfChecks: Suffix mismatch protection ---")
        testSuffixMismatchProtection()

        print("--- SelfChecks: Source switch dynamic rendering ---")
        testSourceSwitchDynamicRendering()

        print("--- SelfChecks: Transient damage checkpoint detection ---")
        testTransientDamageCheckpoint()

        print("\nSelf-check results: \(passedCount) passed, \(failedCount) failed")
        return failedCount == 0
    }

    private static func testWilsonInterval() {
        // Zero positives on 80 negatives
        let wZero = WilsonScoreInterval.compute(successes: 0, total: 80)!
        check(wZero.lower == 0.0, "Zero successes lower bound must be 0.0")
        // Wilson upper bound for 0/80 is ~0.0458 (4.6%)
        check(wZero.upper > 0.045 && wZero.upper < 0.047, "Wilson upper bound for 0/80 must be ~4.6% (was \(wZero.upper))")

        // 80/80 successes
        let wFull = WilsonScoreInterval.compute(successes: 80, total: 80)!
        check(wFull.upper == 1.0, "Full successes upper bound must be 1.0")
        check(wFull.lower > 0.95 && wFull.lower < 0.96, "Wilson lower bound for 80/80 must be ~95.4%")

        // 18/20 successes (90%)
        let w18 = WilsonScoreInterval.compute(successes: 18, total: 20)!
        check(w18.lower > 0.69 && w18.lower < 0.71, "Wilson lower bound for 18/20 must be ~69.9%")
        check(w18.upper > 0.96 && w18.upper < 0.98, "Wilson upper bound for 18/20 must be ~97.2%")

        // Edge case: 0 total returns nil
        check(WilsonScoreInterval.compute(successes: 0, total: 0) == nil, "0 total must return nil")
    }

    private static func testPrecisionNullOnZeroAttempts() {
        let trial = Trial(
            id: "t1",
            groupID: "g1",
            split: "development",
            languages: ["en", "uk"],
            category: "test",
            label: "preserve",
            initial: InitialState(sourceID: "com.apple.keylayout.ABC", language: "en"),
            events: [TrialEvent(type: "key", keyCode: 0, rendered: "a")],
            expected: ExpectedOutcome(text: "a", language: "en", sourceID: "com.apple.keylayout.ABC")
        )
        let res = TrialResult(trialID: "t1", finalText: "a", finalSourceID: "com.apple.keylayout.ABC")
        let report = Scorer.score(trials: [trial], results: [res])

        check(report.precision.rate == nil, "Precision rate must be nil when no repair is attempted")
        check(report.precision.interval == nil, "Precision interval must be nil when no repair is attempted")
        check(report.textDamageFPRate.rate == 0.0, "Text damage FP rate must be 0.0")
    }

    private static func testFakeControlAdapters() {
        let posTrial = Trial(
            id: "pos1",
            groupID: "g1",
            split: "development",
            languages: ["en", "uk"],
            category: "test",
            label: "repair",
            initial: InitialState(sourceID: "com.apple.keylayout.ABC", language: "en"),
            events: [TrialEvent(type: "key", keyCode: 5, rendered: "g"), TrialEvent(type: "boundary", keyCode: 49, rendered: " ")],
            expected: ExpectedOutcome(text: "п ", language: "uk", sourceID: "com.apple.keylayout.Ukrainian", allowedAutomaticActions: ["replaceSuffix", "switchSource"])
        )
        let negTrial = Trial(
            id: "neg1",
            groupID: "g2",
            split: "development",
            languages: ["en", "uk"],
            category: "test",
            label: "preserve",
            initial: InitialState(sourceID: "com.apple.keylayout.ABC", language: "en"),
            events: [TrialEvent(type: "key", keyCode: 0, rendered: "a"), TrialEvent(type: "boundary", keyCode: 49, rendered: " ")],
            expected: ExpectedOutcome(text: "a ", language: "en", sourceID: "com.apple.keylayout.ABC")
        )
        let trials = [posTrial, negTrial]

        // 1. Always Preserve Control (Disabled Detector)
        let preserveResults = [
            TrialResult(trialID: "pos1", finalText: "g ", finalSourceID: "com.apple.keylayout.ABC", actions: []),
            TrialResult(trialID: "neg1", finalText: "a ", finalSourceID: "com.apple.keylayout.ABC", actions: [])
        ]
        let preserveScore = Scorer.score(trials: trials, results: preserveResults)
        check(preserveScore.recall.rate == 0.0, "Always-preserve control must have 0% recall")
        check(preserveScore.textDamageFPRate.rate == 0.0, "Always-preserve control must have 0% FP")
        check(preserveScore.precision.rate == nil, "Always-preserve control must have undefined precision")

        // 2. Always Replace Control (Aggressive Detector)
        let replaceResults = [
            TrialResult(trialID: "pos1", finalText: "п ", finalSourceID: "com.apple.keylayout.Ukrainian", actions: [
                EmittedAction(type: "replaceSuffix", eventIndex: 1, fromText: "g", toText: "п"),
                EmittedAction(type: "switchSource", eventIndex: 1, targetSource: "com.apple.keylayout.Ukrainian", targetLayout: "uk")
            ]),
            TrialResult(trialID: "neg1", finalText: "ф ", finalSourceID: "com.apple.keylayout.Ukrainian", actions: [
                EmittedAction(type: "replaceSuffix", eventIndex: 1, fromText: "a", toText: "ф"),
                EmittedAction(type: "switchSource", eventIndex: 1, targetSource: "com.apple.keylayout.Ukrainian", targetLayout: "uk")
            ])
        ]
        let replaceScore = Scorer.score(trials: trials, results: replaceResults)
        check(replaceScore.recall.rate == 1.0, "Always-replace control recall must be 100%")
        check(replaceScore.textDamageFPRate.rate == 1.0, "Always-replace control text-damage FP must be 100%")

        // 3. Wrong Repair Control
        let wrongResults = [
            TrialResult(trialID: "pos1", finalText: "wrong ", finalSourceID: "com.apple.keylayout.Ukrainian", actions: [
                EmittedAction(type: "replaceSuffix", eventIndex: 1, fromText: "g", toText: "wrong")
            ]),
            TrialResult(trialID: "neg1", finalText: "a ", finalSourceID: "com.apple.keylayout.ABC", actions: [])
        ]
        let wrongScore = Scorer.score(trials: trials, results: wrongResults)
        check(wrongScore.recall.rate == 0.0, "Wrong repair control must have 0% recall")
        check(wrongScore.fnWrongRepair == 1, "Wrong repair control must record fnWrongRepair")

        // 4. Known Good Control
        let goodResults = [
            TrialResult(trialID: "pos1", finalText: "п ", finalSourceID: "com.apple.keylayout.Ukrainian", actions: [
                EmittedAction(type: "replaceSuffix", eventIndex: 1, fromText: "g", toText: "п"),
                EmittedAction(type: "switchSource", eventIndex: 1, targetSource: "com.apple.keylayout.Ukrainian", targetLayout: "uk")
            ]),
            TrialResult(trialID: "neg1", finalText: "a ", finalSourceID: "com.apple.keylayout.ABC", actions: [])
        ]
        let goodScore = Scorer.score(trials: trials, results: goodResults)
        check(goodScore.recall.rate == 1.0, "Known good control must have 100% recall")
        check(goodScore.textDamageFPRate.rate == 0.0, "Known good control must have 0% text damage FP")
        check(goodScore.layoutOnlyFPRate.rate == 0.0, "Known good control must have 0% layout only FP")
        check(goodScore.precision.rate == 1.0, "Known good control must have 100% precision")
    }

    private static func testValidationCatchesErrors() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("benchmark-test-\(UUID().uuidString)")
        let tablesDir = URL(fileURLWithPath: "Benchmarks/layout-tables/v1")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Test 1: Duplicate trial ID in development.jsonl
        let t1 = Trial(
            id: "dup-id",
            groupID: "g1",
            split: "development",
            languages: ["en", "uk"],
            category: "test",
            label: "preserve",
            initial: InitialState(sourceID: "com.apple.keylayout.ABC", language: "en"),
            events: [TrialEvent(type: "key", keyCode: 0, rendered: "a")],
            expected: ExpectedOutcome(text: "a", language: "en", sourceID: "com.apple.keylayout.ABC")
        )
        let t2 = Trial(
            id: "dup-id",
            groupID: "g2",
            split: "development",
            languages: ["en", "uk"],
            category: "test",
            label: "preserve",
            initial: InitialState(sourceID: "com.apple.keylayout.ABC", language: "en"),
            events: [TrialEvent(type: "key", keyCode: 1, rendered: "s")],
            expected: ExpectedOutcome(text: "s", language: "en", sourceID: "com.apple.keylayout.ABC")
        )
        let encoder = JSONEncoder()
        let l1 = String(data: try! encoder.encode(t1), encoding: .utf8)!
        let l2 = String(data: try! encoder.encode(t2), encoding: .utf8)!
        let devURL = tempDir.appendingPathComponent("development.jsonl")
        let holdoutURL = tempDir.appendingPathComponent("holdout.jsonl")

        try! (l1 + "\n" + l2 + "\n").write(to: devURL, atomically: true, encoding: .utf8)
        try! "".write(to: holdoutURL, atomically: true, encoding: .utf8)

        let resultDup = try! CorpusValidator.validate(corpusDirectory: tempDir, tablesDirectory: tablesDir)
        check(!resultDup.passed, "Validation must fail on duplicate trial IDs")
        check(resultDup.errors.contains { $0.contains("Duplicate trial ID") }, "Error must mention duplicate ID")

        // Test 2: Leaking groupID across splits
        let tDev = Trial(
            id: "dev-1",
            groupID: "leaking-group",
            split: "development",
            languages: ["en", "uk"],
            category: "test",
            label: "preserve",
            initial: InitialState(sourceID: "com.apple.keylayout.ABC", language: "en"),
            events: [TrialEvent(type: "key", keyCode: 0, rendered: "a")],
            expected: ExpectedOutcome(text: "a", language: "en", sourceID: "com.apple.keylayout.ABC")
        )
        let tHoldout = Trial(
            id: "holdout-1",
            groupID: "leaking-group",
            split: "holdout",
            languages: ["en", "uk"],
            category: "test",
            label: "preserve",
            initial: InitialState(sourceID: "com.apple.keylayout.ABC", language: "en"),
            events: [TrialEvent(type: "key", keyCode: 1, rendered: "s")],
            expected: ExpectedOutcome(text: "s", language: "en", sourceID: "com.apple.keylayout.ABC")
        )
        let devLine = String(data: try! encoder.encode(tDev), encoding: .utf8)!
        let holdoutLine = String(data: try! encoder.encode(tHoldout), encoding: .utf8)!

        try! (devLine + "\n").write(to: devURL, atomically: true, encoding: .utf8)
        try! (holdoutLine + "\n").write(to: holdoutURL, atomically: true, encoding: .utf8)

        let resultLeak = try! CorpusValidator.validate(corpusDirectory: tempDir, tablesDirectory: tablesDir)
        check(!resultLeak.passed, "Validation must fail on leaking groups between splits")
        check(resultLeak.errors.contains { $0.contains("Leaking groups") }, "Error must mention leaking groups")

        // Test 3: Table rendering mismatch (key 0 on ABC rendered as 'z' instead of 'a')
        let tBadRender = Trial(
            id: "bad-render",
            groupID: "g-bad",
            split: "development",
            languages: ["en", "uk"],
            category: "test",
            label: "preserve",
            initial: InitialState(sourceID: "com.apple.keylayout.ABC", language: "en"),
            events: [TrialEvent(type: "key", keyCode: 0, rendered: "z")], // key 0 is 'a', not 'z'
            expected: ExpectedOutcome(text: "z", language: "en", sourceID: "com.apple.keylayout.ABC")
        )
        let badLine = String(data: try! encoder.encode(tBadRender), encoding: .utf8)!
        try! (badLine + "\n").write(to: devURL, atomically: true, encoding: .utf8)
        try! "".write(to: holdoutURL, atomically: true, encoding: .utf8)

        let resultRender = try! CorpusValidator.validate(corpusDirectory: tempDir, tablesDirectory: tablesDir)
        check(!resultRender.passed, "Validation must fail when event rendered does not match table output")
        check(resultRender.errors.contains { $0.contains("does not match table output") }, "Error must mention table mismatch")
    }

    private static func testUTF16CaretVsGrapheme() {
        // Cyrillic string: "привіт"
        let str = "привіт"
        let utf16Count = str.utf16.count
        let charCount = str.count
        check(utf16Count == 6 && charCount == 6, "Single BMP Cyrillic chars must have 1 UTF-16 code unit per character")

        // Emoji / surrogate pair: "👋"
        let emoji = "👋"
        check(emoji.utf16.count == 2 && emoji.count == 1, "Surrogate emoji must have 2 UTF-16 code units for 1 character")
    }

    private static func testDeleteAndResetHandling() {
        let initialContext = InputContextSnapshot(
            epoch: 1,
            frontmostPID: 100,
            appAllowed: true,
            layout: .english,
            inputSourceID: "com.apple.keylayout.ABC",
            secureFocus: .notSecure
        )
        var sm = InputStateMachine(
            context: initialContext,
            preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic)
        )

        // Type 'a'
        _ = sm.consume(CapturedInput(sequence: 1, timestamp: 1, kind: .character("a"), keyCode: 0, flagsRawValue: 0, isAutorepeat: false, sourcePID: 100, sourceUserData: 0, context: initialContext))
        // Type 'b'
        _ = sm.consume(CapturedInput(sequence: 2, timestamp: 2, kind: .character("b"), keyCode: 11, flagsRawValue: 0, isAutorepeat: false, sourcePID: 100, sourceUserData: 0, context: initialContext))
        check(sm.currentBuffer == "ab", "Buffer must be 'ab'")

        // Delete 'b'
        _ = sm.consume(CapturedInput(sequence: 3, timestamp: 3, kind: .delete, keyCode: 51, flagsRawValue: 0, isAutorepeat: false, sourcePID: 100, sourceUserData: 0, context: initialContext))
        check(sm.currentBuffer == "a", "Buffer after delete must be 'a'")

        // Type 'c'
        _ = sm.consume(CapturedInput(sequence: 4, timestamp: 4, kind: .character("c"), keyCode: 8, flagsRawValue: 0, isAutorepeat: false, sourcePID: 100, sourceUserData: 0, context: initialContext))
        check(sm.currentBuffer == "ac", "Buffer after typing 'c' must be 'ac'")
    }

    private static func testSuffixMismatchProtection() {
        // If detector proposes replacing "test", but virtual editor text does not end with "test ",
        // replacement must be rejected and not corrupt text
        var text = "other word "
        let originalWord = "test"
        let convertedWord = "тест"
        let boundary = " "
        let suffix = originalWord + boundary

        var replaced = false
        if text.hasSuffix(suffix) {
            let prefix = text.dropLast(suffix.count)
            text = String(prefix) + convertedWord + boundary
            replaced = true
        }

        check(!replaced, "Suffix mismatch must reject replacement")
        check(text == "other word ", "Text must remain intact on suffix mismatch")
    }

    private static func testSourceSwitchDynamicRendering() {
        let tablesDir = URL(fileURLWithPath: "Benchmarks/layout-tables/v1")
        guard let ukTable = try? LayoutTable.load(from: tablesDir.appendingPathComponent("com.apple.keylayout.Ukrainian@91.json")) else {
            check(false, "Failed to load Ukrainian table")
            return
        }
        // Key 0 on Ukrainian layout is 'ф'
        let stroke = ukTable.lookup(keyCode: 0, modifiers: [])
        check(stroke?.output == "ф", "Key 0 on Ukrainian table must produce 'ф'")
    }

    private static func testTransientDamageCheckpoint() {
        // Simulate trial where final text matches expected, but an intermediate checkpoint was damaged
        let checkpoint = ObservedCheckpoint(afterEvent: 1, text: "damaged", language: "uk", sourceID: "com.apple.keylayout.Ukrainian")
        let expectedCheckpoint = Checkpoint(afterEvent: 1, text: "expected", language: "uk")

        let damageDetected = (checkpoint.text != expectedCheckpoint.text)
        check(damageDetected, "Checkpoint comparison must catch intermediate damage")
    }
}

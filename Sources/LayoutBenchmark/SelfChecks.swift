import Foundation
import Core
import Dictionary
import Utils

/// Checks of the benchmark's own machinery. Each check drives the real scorer, validator,
/// editor, renderer or adapter; none re-implements the logic it is checking.
public enum SelfChecks {
    private static var passedCount = 0
    private static var failedCount = 0

    private static let abc = "com.apple.keylayout.ABC"
    private static let ukrainian = "com.apple.keylayout.Ukrainian"
    private static let tablesDir = URL(fileURLWithPath: "Benchmarks/layout-tables/v1")

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

        print("--- SelfChecks: Control adapters (preserve, replace, wrong, error, missing, unsupported, good) ---")
        testControlAdapters()

        print("--- SelfChecks: Checkpoint damage, layout-only and unsafe actions are scored ---")
        testCheckpointAndActionScoring()

        print("--- SelfChecks: Baseline gate ---")
        testBaselineGate()

        print("--- SelfChecks: Validation catches schema, duplicate, leaking and label errors ---")
        testValidationCatchesErrors()
        testActualInputChecksums()

        print("--- SelfChecks: UTF-16 caret versus grapheme handling ---")
        testCaretAndGraphemes()

        print("--- SelfChecks: Virtual editor suffix mismatch ---")
        testSuffixMismatch()

        print("--- SelfChecks: Source switch rendering ---")
        testSourceSwitchRendering()

        guard let tables = try? loadTables(from: tablesDir) else {
            check(false, "Frozen layout tables must load from \(tablesDir.path)")
            return finish()
        }
        let adapter = SwitchFixAdapter(tables: tables)
        check(adapter.prewarm(), "Adapter dictionaries must be ready")

        print("--- SelfChecks: Source environment comes from the trial and the app's discovery ---")
        testSourceEnvironment(tables: tables)

        print("--- SelfChecks: Replay of delete, switch feedback and unsupported trials ---")
        testAdapterReplay(adapter: adapter, tables: tables)

        print("--- SelfChecks: Replay agrees with InputEngine using its real detector ---")
        testEngineCrossCheck(adapter: adapter, tables: tables)

        return finish()
    }

    private static func finish() -> Bool {
        print("\nSelf-check results: \(passedCount) passed, \(failedCount) failed")
        return failedCount == 0
    }

    // MARK: - Fixtures

    private static func trial(
        _ id: String,
        label: String,
        events: [TrialEvent],
        expected text: String,
        expectedSource: String? = nil,
        language: String = "en",
        initialText: String = "",
        caret: Int? = nil,
        checkpoints: [Checkpoint] = []
    ) -> Trial {
        let source = language == "en" ? abc : ukrainian
        let expectedSourceID = expectedSource ?? source
        return Trial(
            id: id,
            groupID: "g-\(id)",
            split: "development",
            languages: ["en", "uk"],
            category: "test",
            label: label,
            initial: InitialState(sourceID: source, language: language, text: initialText, caretUTF16: caret ?? initialText.utf16.count, preferredCyrillic: "uk", keyboardType: 91),
            events: events,
            expected: ExpectedOutcome(
                text: text,
                language: expectedSourceID == ukrainian ? "uk" : "en",
                sourceID: expectedSourceID,
                allowedAutomaticActions: label == "repair" ? ["replaceSuffix", "switchSource"] : [],
                checkpoints: checkpoints
            )
        )
    }

    private static func generated(_ text: String, label: String, from: String, to: String, id: String) -> Trial? {
        guard let abcTable = try? LayoutTable.load(from: tablesDir.appendingPathComponent("\(abc)@91.json")),
              let ukTable = try? LayoutTable.load(from: tablesDir.appendingPathComponent("\(ukrainian)@91.json")) else {
            return nil
        }
        let item = SeedItemDefinition(groupID: "g-\(id)", category: "self-check", label: label, sourceLayout: from, targetLayout: to, intendedText: text, isRepair: label == "repair")
        return try? SeedCorpusGenerator.generateTrial(id: id, item: item, split: "development", abcTable: abcTable, ukTable: ukTable)
    }

    private static let replace = EmittedAction(type: "replaceSuffix", eventIndex: 1, fromText: "g", toText: "п")
    private static let switchToUkrainian = EmittedAction(type: "switchSource", eventIndex: 1, targetSource: ukrainian, targetLayout: "uk")

    private static var positive: Trial {
        trial("pos1", label: "repair", events: [TrialEvent(type: "key", keyCode: 5, rendered: "g"), TrialEvent(type: "boundary", keyCode: 49, rendered: " ")], expected: "п ", expectedSource: ukrainian)
    }

    private static var negative: Trial {
        trial("neg1", label: "preserve", events: [TrialEvent(type: "key", keyCode: 0, rendered: "a"), TrialEvent(type: "boundary", keyCode: 49, rendered: " ")], expected: "a ")
    }

    // MARK: - Scoring

    private static func testWilsonInterval() {
        let wZero = WilsonScoreInterval.compute(successes: 0, total: 80)!
        check(wZero.lower == 0.0, "Zero successes lower bound must be 0.0")
        check(wZero.upper > 0.045 && wZero.upper < 0.047, "Wilson upper bound for 0/80 must be ~4.6% (was \(wZero.upper))")

        let wFull = WilsonScoreInterval.compute(successes: 80, total: 80)!
        check(wFull.upper == 1.0, "Full successes upper bound must be 1.0")
        check(wFull.lower > 0.95 && wFull.lower < 0.96, "Wilson lower bound for 80/80 must be ~95.4%")

        let w18 = WilsonScoreInterval.compute(successes: 18, total: 20)!
        check(w18.lower > 0.69 && w18.lower < 0.71, "Wilson lower bound for 18/20 must be ~69.9%")
        check(w18.upper > 0.96 && w18.upper < 0.98, "Wilson upper bound for 18/20 must be ~97.2%")

        check(WilsonScoreInterval.compute(successes: 0, total: 0) == nil, "0 total must return nil")
    }

    private static func testPrecisionNullOnZeroAttempts() {
        let report = Scorer.score(trials: [negative], results: [TrialResult(trialID: "neg1", finalText: "a ", finalSourceID: abc)])
        check(report.precision.rate == nil, "Precision rate must be nil when no repair is attempted")
        check(report.precision.interval == nil, "Precision interval must be nil when no repair is attempted")
        check(report.textDamageFPRate.rate == 0.0, "Text damage FP rate must be 0.0")
        check(report.complete, "A run with every observation present is complete")
    }

    private static func testControlAdapters() {
        let trials = [positive, negative]

        let preserve = Scorer.score(trials: trials, results: [
            TrialResult(trialID: "pos1", finalText: "g ", finalSourceID: abc),
            TrialResult(trialID: "neg1", finalText: "a ", finalSourceID: abc)
        ])
        check(preserve.recall.rate == 0.0, "Always-preserve control must have 0% recall")
        check(preserve.textDamageFPRate.rate == 0.0, "Always-preserve control must have 0% FP")
        check(preserve.precision.rate == nil, "Always-preserve control must have undefined precision")

        let aggressive = Scorer.score(trials: trials, results: [
            TrialResult(trialID: "pos1", finalText: "п ", finalSourceID: ukrainian, actions: [replace, switchToUkrainian]),
            TrialResult(trialID: "neg1", finalText: "ф ", finalSourceID: ukrainian, actions: [replace, switchToUkrainian])
        ])
        check(aggressive.recall.rate == 1.0, "Always-replace control recall must be 100%")
        check(aggressive.textDamageFPRate.rate == 1.0, "Always-replace control text-damage FP must be 100%")
        check(aggressive.precision.rate == 0.5, "Always-replace precision counts the negative intervention")

        let wrong = Scorer.score(trials: trials, results: [
            TrialResult(trialID: "pos1", finalText: "wrong ", finalSourceID: ukrainian, actions: [replace]),
            TrialResult(trialID: "neg1", finalText: "a ", finalSourceID: abc)
        ])
        check(wrong.recall.rate == 0.0, "Wrong repair control must have 0% recall")
        check(wrong.fnWrongRepair == 1, "Wrong repair control must record fnWrongRepair")
        check(wrong.precision.rate == 0.0, "A wrong repair is an attempt without success")

        let errors = Scorer.score(trials: trials, results: [
            TrialResult(trialID: "pos1", status: "error", finalText: "", finalSourceID: "", errorMessage: "boom"),
            TrialResult(trialID: "neg1", status: "error", finalText: "", finalSourceID: "", errorMessage: "boom")
        ])
        check(!errors.complete, "An error control must leave the run incomplete")
        check(errors.errorTrials == 2 && errors.fnError == 1, "Errors are counted, the positive one as a failed repair")
        check(errors.trueNegatives == 0 && errors.textDamageFPs == 0, "An erroring negative is neither preserved nor damaged")
        check(errors.nNegative == 1 && errors.nPositive == 1, "Errors stay in the denominators")
        check(errors.recall.rate == 0.0 && errors.precision.rate == nil, "Errors earn no recall or precision")

        let missing = Scorer.score(trials: trials, results: [])
        check(!missing.complete && missing.missingTrials == 2, "Missing observations leave the run incomplete")
        check(missing.trueNegatives == 0 && missing.nNegative == 1, "A missing negative cannot count as preserved")
        check(missing.trialOutcomes["neg1"] == .negativeError, "A missing negative is recorded as an error outcome")

        let unsupported = Scorer.score(trials: trials, results: [
            TrialResult(trialID: "pos1", status: "unsupported", finalText: "", finalSourceID: ""),
            TrialResult(trialID: "neg1", status: "unsupported", finalText: "", finalSourceID: "")
        ])
        check(unsupported.unsupportedTrials == 2 && unsupported.nPositive == 0 && unsupported.nNegative == 0, "Unsupported trials leave every denominator")
        check(unsupported.recall.rate == nil && unsupported.coverage.rate == 0.0, "Unsupported trials report coverage, not quality")

        let good = Scorer.score(trials: trials, results: [
            TrialResult(trialID: "pos1", finalText: "п ", finalSourceID: ukrainian, actions: [replace, switchToUkrainian]),
            TrialResult(trialID: "neg1", finalText: "a ", finalSourceID: abc)
        ])
        check(good.recall.rate == 1.0, "Known good control must have 100% recall")
        check(good.textDamageFPRate.rate == 0.0, "Known good control must have 0% text damage FP")
        check(good.layoutOnlyFPRate.rate == 0.0, "Known good control must have 0% layout only FP")
        check(good.precision.rate == 1.0, "Known good control must have 100% precision")
        check(good.complete && good.coverage.rate == 1.0, "Known good control is complete with full coverage")
    }

    private static func testCheckpointAndActionScoring() {
        let checkpointed = trial(
            "pos-cp",
            label: "repair",
            events: [TrialEvent(type: "key", keyCode: 5, rendered: "g"), TrialEvent(type: "boundary", keyCode: 49, rendered: " ")],
            expected: "п ",
            expectedSource: ukrainian,
            checkpoints: [Checkpoint(afterEvent: 2, text: "п ", language: "uk")]
        )
        let late = TrialResult(
            trialID: "pos-cp",
            finalText: "п ",
            finalSourceID: ukrainian,
            actions: [replace, switchToUkrainian],
            checkpoints: [ObservedCheckpoint(afterEvent: 2, text: "g ", language: "en", sourceID: abc)]
        )
        check(Scorer.classify(trial: checkpointed, result: late) == .fnTransientDamage, "A repair that misses its checkpoint is not a true positive")

        let guarded = trial(
            "neg-cp",
            label: "preserve",
            events: [TrialEvent(type: "key", keyCode: 0, rendered: "a"), TrialEvent(type: "boundary", keyCode: 49, rendered: " ")],
            expected: "a ",
            checkpoints: [Checkpoint(afterEvent: 1, text: "a", language: "en")]
        )
        let restored = TrialResult(
            trialID: "neg-cp",
            finalText: "a ",
            finalSourceID: abc,
            checkpoints: [ObservedCheckpoint(afterEvent: 1, text: "ф", language: "en", sourceID: abc)]
        )
        check(Scorer.classify(trial: guarded, result: restored) == .textDamageFP, "Damage seen at a checkpoint counts even when the final text is restored")

        let languageMismatch = TrialResult(
            trialID: "neg-cp",
            finalText: "a ",
            finalSourceID: abc,
            checkpoints: [ObservedCheckpoint(afterEvent: 1, text: "a", language: "uk", sourceID: ukrainian)]
        )
        check(Scorer.classify(trial: guarded, result: languageMismatch) == .layoutOnlyFP, "Language-only mismatch at checkpoint is a layout-only false positive, not text damage")

        let switchOnly = TrialResult(trialID: "neg1", finalText: "a ", finalSourceID: ukrainian, actions: [switchToUkrainian])
        check(Scorer.classify(trial: negative, result: switchOnly) == .layoutOnlyFP, "A switch without a text edit is a layout-only false positive")

        let undone = TrialResult(trialID: "neg1", finalText: "a ", finalSourceID: abc, actions: [replace])
        check(Scorer.classify(trial: negative, result: undone) == .textDamageFP, "Any replacement on a negative counts as damage")

        let foreign = TrialResult(trialID: "pos1", finalText: "п ", finalSourceID: ukrainian, actions: [replace, EmittedAction(type: "pasteSelection", eventIndex: 1)])
        check(Scorer.classify(trial: positive, result: foreign) == .fnUnsafeMutation, "An action outside allowedAutomaticActions is unsafe")

        let prefixed = trial("pos-prefix", label: "repair", events: positive.events, expected: "keep п ", expectedSource: ukrainian, initialText: "keep ")
        let clobbered = TrialResult(trialID: "pos-prefix", finalText: "kee п ", finalSourceID: ukrainian, actions: [replace])
        check(Scorer.classify(trial: prefixed, result: clobbered) == .fnUnsafeMutation, "Damage to the protected initial text is unsafe")
    }

    private static func testBaselineGate() {
        let trials = [positive, negative]
        let good = Scorer.score(trials: trials, results: [
            TrialResult(trialID: "pos1", finalText: "п ", finalSourceID: ukrainian, actions: [replace, switchToUkrainian]),
            TrialResult(trialID: "neg1", finalText: "a ", finalSourceID: abc)
        ])
        let metadata = BenchmarkEnvironment.metadata(corpusDir: URL(fileURLWithPath: "/nonexistent"), trials: trials, profile: "boundary-layout-only", layer: .replay, commitOverride: "self-check")
        let baseline = BaselineRecord(schemaVersion: 2, baselineVersion: "self-check", created: "", metadata: metadata, runnerChecks: [:], development: good, holdout: good, combined: good)
        check(BaselineGate.regressions(current: good, baseline: baseline).isEmpty, "An unchanged run passes the gate")

        let empty = Scorer.score(trials: [], results: [])
        check(BaselineGate.regressions(current: empty, baseline: baseline).map(\.trialID) == ["neg1", "pos1"], "Removed trial IDs fail the inventory gate")
        let splitBaseline = BaselineRecord(schemaVersion: 2, baselineVersion: "split", created: "", metadata: metadata, runnerChecks: [:], development: good, holdout: empty, combined: good)
        check(BaselineGate.regressions(current: empty, baseline: splitBaseline, split: "holdout").isEmpty, "Holdout gate must not require development IDs")
        check(BaselineGate.regressions(current: empty, baseline: splitBaseline, split: "development").count == 2, "Development gate requires its own IDs")
        check(BaselineGate.regressions(current: good, baseline: splitBaseline, split: "development").isEmpty, "Development gate ignores holdout inventory")
        let unsupported = Scorer.score(trials: trials, results: trials.map {
            TrialResult(trialID: $0.id, status: "unsupported", finalText: "", finalSourceID: "")
        })
        let unsupportedBaseline = BaselineRecord(schemaVersion: 2, baselineVersion: "unsupported", created: "", metadata: metadata, runnerChecks: [:], development: unsupported, holdout: empty, combined: unsupported)
        check(BaselineGate.regressions(current: empty, baseline: unsupportedBaseline, split: "development").count == 2, "Removed unsupported IDs also fail inventory")

        let regressed = Scorer.score(trials: trials, results: [
            TrialResult(trialID: "pos1", finalText: "g ", finalSourceID: abc),
            TrialResult(trialID: "neg1", finalText: "ф ", finalSourceID: abc, actions: [replace])
        ])
        let findings = BaselineGate.regressions(current: regressed, baseline: baseline)
        check(findings.map(\.trialID) == ["neg1", "pos1"], "A lost repair and a new false positive both fail the gate")

        let lostCoverage = Scorer.score(trials: trials, results: [
            TrialResult(trialID: "pos1", status: "unsupported", finalText: "", finalSourceID: ""),
            TrialResult(trialID: "neg1", finalText: "a ", finalSourceID: abc)
        ])
        check(BaselineGate.regressions(current: lostCoverage, baseline: baseline).map(\.trialID) == ["pos1"], "Silent coverage loss fails the gate")
    }

    // MARK: - Validation

    private static func writeCorpus(_ dev: [Trial], _ holdout: [Trial], to dir: URL) {
        let encoder = JSONEncoder()
        func lines(_ trials: [Trial]) -> String {
            trials.map { String(decoding: try! encoder.encode($0), as: UTF8.self) + "\n" }.joined()
        }
        try! lines(dev).write(to: dir.appendingPathComponent("development.jsonl"), atomically: true, encoding: .utf8)
        try! lines(holdout).write(to: dir.appendingPathComponent("holdout.jsonl"), atomically: true, encoding: .utf8)
    }

    private static func withSplit(_ t: Trial, _ split: String, id: String? = nil, group: String? = nil, label: String? = nil, review: String = "pending-human") -> Trial {
        Trial(
            id: id ?? t.id,
            groupID: group ?? t.groupID,
            split: split,
            languages: t.languages,
            category: t.category,
            label: label ?? t.label,
            provenance: Provenance(review: review),
            initial: t.initial,
            events: t.events,
            expected: t.expected
        )
    }

    private static func testValidationCatchesErrors() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("benchmark-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        func validate() -> ValidationResult { try! CorpusValidator.validate(corpusDirectory: tempDir, tablesDirectory: tablesDir) }

        let a = trial("a", label: "preserve", events: [TrialEvent(type: "key", keyCode: 0, rendered: "a")], expected: "a")
        let s = trial("s", label: "preserve", events: [TrialEvent(type: "key", keyCode: 1, rendered: "s")], expected: "s")

        writeCorpus([a, withSplit(s, "development", id: "a")], [], to: tempDir)
        let duplicate = validate()
        check(!duplicate.passed && duplicate.errors.contains { $0.contains("Duplicate trial ID") }, "Validation must fail on duplicate trial IDs")
        check(duplicate.errors.contains { $0.contains("Missing manifest.json") }, "Validation must require a manifest")

        writeCorpus([withSplit(a, "development", group: "leak")], [withSplit(s, "holdout", group: "leak")], to: tempDir)
        check(validate().errors.contains { $0.contains("Leaking groups") }, "Validation must fail on leaking groups between splits")

        let badRender = trial("bad", label: "preserve", events: [TrialEvent(type: "key", keyCode: 0, rendered: "z")], expected: "z")
        writeCorpus([badRender], [], to: tempDir)
        check(validate().errors.contains { $0.contains("does not match table output") }, "Validation must fail when rendered text does not match the table")

        writeCorpus([a, withSplit(a, "development", id: "a2", label: "abstain")], [], to: tempDir)
        check(validate().warnings.contains { $0.contains("Contradictory labels") }, "Identical input with different labels must be reported (and fails --strict)")

        writeCorpus([a], [withSplit(a, "holdout", id: "a-holdout", group: "other")], to: tempDir)
        let crossSplit = validate()
        check(crossSplit.warnings.contains { $0.contains("Identical typed input in both splits") }, "Identical input in both splits must warn")
        check(crossSplit.warnings.contains { $0.contains("in both splits") && $0.contains("Base text") }, "Shared base text across splits must warn")

        writeCorpus([withSplit(a, "development", review: "reviewed")], [], to: tempDir)
        check(!validate().errors.contains { $0.contains("Provenance review") }, "Reviewed trials must be accepted")
        writeCorpus([withSplit(a, "development", review: "approved-by-bot")], [], to: tempDir)
        check(validate().errors.contains { $0.contains("Provenance review") }, "Unknown review states must fail")

        let otherType = Trial(id: "kt", groupID: "kt", split: "development", languages: ["en"], category: "test", label: "preserve",
                              initial: InitialState(sourceID: abc, language: "en", keyboardType: 40),
                              events: a.events, expected: a.expected)
        writeCorpus([otherType], [], to: tempDir)
        check(validate().errors.contains { $0.contains("Missing layout table for \(abc)@40") }, "A keyboard type without its own table must fail, not borrow another")

        check(CorpusValidator.verifyManifest(corpusDirectory: URL(fileURLWithPath: "Benchmarks/layout-corpus/v1"), tablesDirectory: tablesDir).isEmpty, "The frozen v1 manifest hashes must match its files")
    }

    private static func testActualInputChecksums() {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: temp) }
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            let corpus = temp.appendingPathComponent("relocated-corpus")
            let tables = temp.appendingPathComponent("relocated-tables")
            try fm.copyItem(at: URL(fileURLWithPath: "Benchmarks/layout-corpus/v2"), to: corpus)
            try fm.copyItem(at: tablesDir, to: tables)
            check(CorpusValidator.verifyManifest(corpusDirectory: corpus, tablesDirectory: tables).isEmpty, "Relocated identical inputs verify without inferred roots")
            let table = tables.appendingPathComponent("com.apple.keylayout.ABC@91.json")
            var bytes = try Data(contentsOf: table)
            bytes.append(Data("\n".utf8))
            try bytes.write(to: table)
            let validation = try CorpusValidator.validate(corpusDirectory: corpus, tablesDirectory: tables)
            check(validation.errors.contains { $0.contains("hash mismatch") && $0.contains("ABC@91") }, "Validator hashes the actual supplied tables")
            do {
                try CorpusValidator.requireVerifiedInputs(corpusDirectory: corpus, tablesDirectory: tables)
                check(false, "Run/record input preflight must reject modified tables")
            } catch { check(true, "Run/record input preflight rejects modified tables") }
            try fm.copyItem(at: table, to: tables.appendingPathComponent("extra.json"))
            check(CorpusValidator.verifyManifest(corpusDirectory: corpus, tablesDirectory: tables).contains { $0.contains("does not list table") }, "Unmanifested replay tables fail preflight")
            try fm.removeItem(at: table)
            check(CorpusValidator.verifyManifest(corpusDirectory: corpus, tablesDirectory: tables).contains { $0.contains("missing file") }, "Missing manifest tables fail preflight")
            try Data("changed".utf8).write(to: corpus.appendingPathComponent("development.jsonl"))
            check(CorpusValidator.verifyManifest(corpusDirectory: corpus, tablesDirectory: tables).contains { $0.contains("hash mismatch") && $0.contains("development.jsonl") }, "Modified corpus bytes fail preflight")
        } catch { check(false, "Checksum regression fixture: \(error)") }
    }

    private static func testCaretAndGraphemes() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("benchmark-caret-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let text = "привіт 👋"
        let midSurrogate = trial("mid", label: "preserve", events: [], expected: text, initialText: text, caret: text.utf16.count - 1)
        writeCorpus([midSurrogate], [], to: tempDir)
        let result = try! CorpusValidator.validate(corpusDirectory: tempDir, tablesDirectory: tablesDir)
        check(result.errors.contains { $0.contains("not on a character boundary") }, "A caret inside a surrogate pair must fail validation")

        let midChar = trial("midchar", label: "preserve", events: [], expected: text, initialText: text, caret: 0)
        writeCorpus([midChar], [], to: tempDir)
        let midCharResult = try! CorpusValidator.validate(corpusDirectory: tempDir, tablesDirectory: tablesDir)
        check(midCharResult.errors.contains { $0.contains("must be at end of initial text") }, "A non-terminal caret must fail validation")

        let atEnd = trial("end", label: "preserve", events: [], expected: text, initialText: text)
        writeCorpus([atEnd], [], to: tempDir)
        check(!(try! CorpusValidator.validate(corpusDirectory: tempDir, tablesDirectory: tablesDir)).errors.contains { $0.contains("caretUTF16") }, "A caret at the end is valid")

        var editor = VirtualEditor(text: "a👋")
        editor.deleteBackward()
        check(editor.text == "a", "One backspace deletes the whole emoji (two UTF-16 units, one grapheme)")
        var combining = VirtualEditor(text: "е\u{0301}")
        combining.deleteBackward()
        check(combining.text.isEmpty, "One backspace deletes a letter with its combining mark")
    }

    private static func testSuffixMismatch() {
        var matched = VirtualEditor(text: "say test ")
        let ok = matched.replaceSuffix(deleteCount: 5, with: "тест ", expectedSuffix: "test ")
        check(ok.suffixMatched && !ok.underflow && matched.text == "say тест ", "A matching suffix is replaced exactly")

        var mismatched = VirtualEditor(text: "other word ")
        let outcome = mismatched.replaceSuffix(deleteCount: 5, with: "тест ", expectedSuffix: "test ")
        check(!outcome.suffixMatched, "A suffix mismatch is reported")
        check(mismatched.text == "other тест ", "The editor deletes by count like TextCorrector, so the damage stays visible")

        var short = VirtualEditor(text: "ab")
        check(short.replaceSuffix(deleteCount: 5, with: "x", expectedSuffix: "test ").underflow, "Deleting past the start is reported")
    }

    private static func testSourceSwitchRendering() {
        guard let tables = try? loadTables(from: tablesDir) else {
            check(false, "Frozen layout tables must load")
            return
        }
        let renderer = KeyRenderer(tables: tables)
        let keyA = TrialEvent(type: "key", keyCode: 0, rendered: "a")
        check(renderer.render(keyA, sourceID: abc, keyboardType: 91, initialSourceID: abc) == .rendered("a"), "The initial source uses the validated rendered text")
        check(renderer.render(keyA, sourceID: ukrainian, keyboardType: 91, initialSourceID: abc) == .rendered("ф"), "After a switch the key renders through the new source's table")
        check(renderer.render(keyA, sourceID: ukrainian, keyboardType: 40, initialSourceID: abc) == .unavailable(status: "error", reason: "missing_layout_table"), "A missing table is an error, never the original text")
        let optionE = TrialEvent(type: "key", keyCode: 14, modifiers: ["option"], rendered: "e")
        check(renderer.render(optionE, sourceID: abc, keyboardType: 91, initialSourceID: ukrainian) == .unavailable(status: "unsupported", reason: "rejected_stroke_deadKey"), "A dead key after a switch is unsupported")
    }

    // MARK: - Adapter

    private static func testSourceEnvironment(tables: [String: LayoutTable]) {
        guard let repair = generated("привіт ", label: "repair", from: "en", to: "uk", id: "env") else {
            check(false, "Generator must build a repair trial")
            return
        }
        guard case .success(let environment) = TrialSourceEnvironment.make(trial: repair, tables: tables, allowedLayouts: SwitchFixAdapter.profileLayouts) else {
            check(false, "Environment must build from the frozen tables")
            return
        }
        check(environment.descriptors[ukrainian]?.ukrainianVariant == .legacy, "Apple 'Ukrainian' (s=и, b=і) is classified legacy, as the app does")
        check(environment.descriptors[abc]?.supportedLayouts == [.english], "ABC supports English only")
        let config = environment.detectionConfiguration(currentSourceID: abc, currentLayout: .english)
        check(config.ukrainianToVariant == .legacy, "Conversions target the variant of the trial's Ukrainian source")
        check(config.activeSourceSupportedLayouts == [.english], "Active source layouts come from discovery")

        let pc = Trial(id: "pc", groupID: "pc", split: "development", languages: ["en", "uk"], category: "test", label: "repair",
                       initial: repair.initial, events: repair.events,
                       expected: ExpectedOutcome(text: "привіт ", language: "uk", sourceID: "com.apple.keylayout.Ukrainian-PC", allowedAutomaticActions: ["replaceSuffix", "switchSource"]))
        if case .success(let pcEnvironment) = TrialSourceEnvironment.make(trial: pc, tables: tables, allowedLayouts: SwitchFixAdapter.profileLayouts) {
            check(pcEnvironment.detectionConfiguration(currentSourceID: abc, currentLayout: .english).ukrainianToVariant == .standard, "Ukrainian-PC is classified standard")
        } else {
            check(false, "Ukrainian-PC environment must build")
        }
    }

    private static func testAdapterReplay(adapter: SwitchFixAdapter, tables: [String: LayoutTable]) {
        if let clean = generated("привіт ", label: "repair", from: "en", to: "uk", id: "typo") {
            // Type a stray key and delete it before the last letter.
            var events = clean.events
            events.insert(contentsOf: [TrialEvent(type: "key", keyCode: 7, rendered: "x"), TrialEvent(type: "delete", keyCode: 51, rendered: "")], at: events.count - 2)
            let typo = Trial(id: "typo", groupID: "typo", split: "development", languages: clean.languages, category: "test", label: "repair",
                             initial: clean.initial, events: events, expected: ExpectedOutcome(text: clean.expected.text, language: "uk", sourceID: ukrainian, allowedAutomaticActions: clean.expected.allowedAutomaticActions))
            let result = adapter.executeTrial(trial: typo)
            check(result.finalText == "привіт ", "A delete inside a word is replayed on screen and in the buffer (got '\(result.finalText)')")
            check(Scorer.classify(trial: typo, result: result) == .truePositive, "The corrected word after a delete is a true positive")
        } else {
            check(false, "Generator must build the delete fixture")
        }

        if let twoWords = generated("добрий день ", label: "repair", from: "en", to: "uk", id: "two-words") {
            let result = adapter.executeTrial(trial: twoWords)
            check(result.finalText == "добрий день ", "After the first word switches the source, later keys render as Ukrainian (got '\(result.finalText)')")
            check(result.finalSourceID == ukrainian, "The replay ends on the switched source")
            check(Scorer.classify(trial: twoWords, result: result) == .truePositive, "A two-word repair on Apple 'Ukrainian' is a true positive")
            let decision = adapter.executeTrial(trial: twoWords, layer: .decision)
            let edits = { (r: TrialResult) in r.actions.filter { $0.type == "replaceSuffix" }.count }
            check(edits(result) == 1, "With switch feedback only the first word needs a repair")
            check(edits(decision) == 2, "Without feedback the second word is still typed on ABC and needs its own repair")

            for event in [TrialEvent(type: "key", keyCode: 36, rendered: "\r"),
                          TrialEvent(type: "unknown", keyCode: 0, rendered: "")] {
                let failing = Trial(id: "post-intervention", groupID: "post-intervention", split: "development",
                                    languages: twoWords.languages, category: "test", label: "repair",
                                    initial: twoWords.initial, events: twoWords.events + [event], expected: twoWords.expected)
                let failed = adapter.executeTrial(trial: failing)
                check(!failed.actions.isEmpty && failed.status == "error", "Unsupported input after an intervention remains an error")
                check(Scorer.classify(trial: failing, result: failed) == .fnError, "A post-intervention error remains in quality denominators")
            }
        } else {
            check(false, "Generator must build the two-word trial")
        }

        let caretInside = trial("caret", label: "preserve", events: negative.events, expected: "x a ", initialText: "x ", caret: 0)
        let caretResult = adapter.executeTrial(trial: caretInside)
        check(caretResult.status == "unsupported" && caretResult.reasonCodes.contains("caret_not_at_end"), "A caret that is not at the end is unsupported, not approximated")

        let typeFortyTrial = Trial(id: "kt40", groupID: "kt40", split: "development", languages: ["en", "uk"], category: "test", label: "preserve",
                                   initial: InitialState(sourceID: abc, language: "en", keyboardType: 40), events: negative.events, expected: negative.expected)
        let typeForty = adapter.executeTrial(trial: typeFortyTrial)
        check(typeForty.status == "error" && typeForty.reasonCodes.contains("missing_layout_table"), "A trial without its keyboard type's tables is an error")
    }

    /// Feeds the same trials through `InputEngine` with its real detector and an injected
    /// emission, and checks the engine's planned edit leaves the same text and switch.
    private static func testEngineCrossCheck(adapter: SwitchFixAdapter, tables: [String: LayoutTable]) {
        let cases: [(String, String, String, String)] = [
            ("привіт ", "repair", "en", "uk"),
            ("робота ", "repair", "en", "uk"),
            ("hello ", "repair", "uk", "en"),
            ("apple ", "preserve", "en", "en"),
            ("яблуко ", "preserve", "uk", "uk"),
            ("vs ", "preserve", "en", "en")
        ]
        for (index, (text, label, from, to)) in cases.enumerated() {
            guard let trial = generated(text, label: label, from: from, to: to, id: "xcheck-\(index)"),
                  case .success(let environment) = TrialSourceEnvironment.make(trial: trial, tables: tables, allowedLayouts: SwitchFixAdapter.profileLayouts),
                  let initialLayout = layout(forLanguageCode: trial.initial.language) else {
                check(false, "Cross-check fixture \(index) must build")
                continue
            }
            let replay = adapter.executeTrial(trial: trial)

            let context = InputContextSnapshot(epoch: 1, frontmostPID: 100, appAllowed: true, layout: initialLayout, inputSourceID: trial.initial.sourceID, secureFocus: .notSecure)
            let store = CaptureStateStore(context: context, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
            let detector = LayoutDetector()
            detector.preferredSourceIDProvider = { environment.preferredSourceIDs[$0] }
            let lock = NSLock()
            var plans: [CorrectionPlan] = []
            let engine = InputEngine(
                captureState: store,
                initialContext: context,
                preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
                detector: detector,
                correctionEmission: { plan in
                    lock.lock(); plans.append(plan); lock.unlock()
                    return true
                }
            )
            let config = environment.detectionConfiguration(currentSourceID: trial.initial.sourceID, currentLayout: initialLayout)
            engine.updateDetectionConfiguration(
                allowedLayouts: config.allowedLayouts,
                preferredCyrillicLayout: config.preferredCyrillicLayout,
                activeSourceSupportedLayouts: config.activeSourceSupportedLayouts,
                ukrainianFromVariant: config.ukrainianFromVariant,
                ukrainianToVariant: config.ukrainianToVariant
            )

            var screen = VirtualEditor(text: trial.initial.text)
            for (timestamp, event) in trial.events.enumerated() {
                screen.type(event.rendered)
                let kind: CapturedInput.Kind = event.type == "boundary" ? .boundary(event.rendered) : KeyboardMonitor.capturedKind(forText: event.rendered)
                engine.enqueue(store.capture(
                    timestamp: UInt64(timestamp + 1),
                    kind: kind,
                    keyCode: event.keyCode,
                    flagsRawValue: event.modifiers.contains("shift") ? 0x020000 : 0,
                    isAutorepeat: false,
                    sourcePID: 100,
                    sourceUserData: 0
                ))
            }
            let drained = DispatchSemaphore(value: 0)
            engine.drainPipeline { drained.signal() }
            check(drained.wait(timeout: .now() + 5) == .success, "Engine pipeline drains for '\(text)'")

            lock.lock(); let emitted = plans; lock.unlock()
            for plan in emitted {
                _ = screen.replaceSuffix(deleteCount: plan.deleteCount, with: plan.replacementText, expectedSuffix: plan.originalText + plan.boundaryText)
            }
            let engineTarget = emitted.last?.targetLayout.map(languageCode(for:))
            let replayTarget = replay.actions.last(where: { $0.type == "switchSource" })?.targetLayout
            check(screen.text == replay.finalText, "Replay and engine leave the same text for '\(text)' (engine '\(screen.text)', replay '\(replay.finalText)')")
            check(engineTarget == replayTarget, "Replay and engine request the same switch for '\(text)'")
            let engineEdits = emitted.filter { $0.deleteCount > 0 || !$0.replacementText.isEmpty }.count
            check(engineEdits == replay.actions.filter { $0.type == "replaceSuffix" }.count, "Replay and engine apply the same number of text edits for '\(text)'")
        }
    }
}

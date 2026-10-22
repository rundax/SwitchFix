import Dictionary
import Foundation

func main() {
    let args = CommandLine.arguments
    if args.count < 2 {
        printUsage()
        exit(1)
    }

    let command = args[1]
    let options = Options(Array(args.dropFirst(2)))
    switch command {
    case "export-layout-tables":
        handleExportLayoutTables(options)
    case "generate-seed-corpus":
        handleGenerateSeedCorpus(options)
    case "validate":
        handleValidate(options)
    case "run":
        handleRun(options)
    case "summarize":
        handleSummarize(options)
    case "self-check":
        let passed = SelfChecks.runAll()
        exit(passed ? 0 : 1)
    case "record-baseline":
        handleRecordBaseline(options)
    case "compare":
        print("competitor_unavailable: compare is not implemented yet (Plan-Item 03.5)")
        exit(1)
    default:
        print("Unknown command: \(command)")
        printUsage()
        exit(1)
    }
}

func printUsage() {
    print("""
    LayoutBenchmark: SwitchFix Layout Reliability & False-Positive Benchmark

    Commands:
      export-layout-tables --output <new-dir> [--keyboard-types <type1,type2>]
      generate-seed-corpus --version v1|v2 [--corpus <dir>] [--tables <dir>] [--commit <sha>]
      validate [--corpus <corpus-dir>] [--tables <tables-dir>] [--strict]
      run [--adapter switchfix] [--split development|holdout|all] [--layer decision|replay] [--profile boundary-layout-only]
          [--corpus <dir>] [--tables <dir>] [--output <dir>] [--baseline <baseline.json>]
          [--dictionary-backend bundled|system|system-lowercase]  (system: macOS spell checker, spike)
      record-baseline --baselines <dir> [--corpus <dir>] [--tables <dir>] [--commit <sha>] [--runner-log <Name>=<path>]...
      summarize [--results <dir>]
      self-check
      compare
    """)
}

/// `--name value` options; repeatable options keep every value.
struct Options {
    private var values: [String: [String]] = [:]
    private var flags: Set<String> = []

    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("--"), i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                values[arg, default: []].append(args[i + 1])
                i += 2
            } else {
                flags.insert(arg)
                i += 1
            }
        }
    }

    func value(_ name: String) -> String? { values[name]?.last }
    func all(_ name: String) -> [String] { values[name] ?? [] }
    func flag(_ name: String) -> Bool { flags.contains(name) }
    func url(_ name: String, default path: String) -> URL { URL(fileURLWithPath: value(name) ?? path) }
}

func loadTables(from tablesDir: URL) throws -> [String: LayoutTable] {
    var tables: [String: LayoutTable] = [:]
    let tableFiles = try FileManager.default.contentsOfDirectory(at: tablesDir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
    for tURL in tableFiles {
        tables[tURL.deletingPathExtension().lastPathComponent] = try LayoutTable.load(from: tURL)
    }
    return tables
}

func loadTrials(corpusDir: URL, split: String) throws -> [Trial] {
    let splits: [String]
    switch split {
    case "development", "holdout": splits = [split]
    case "all": splits = ["development", "holdout"]
    default: throw NSError(domain: "LayoutBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown split '\(split)'"])
    }
    let decoder = JSONDecoder()
    var trials: [Trial] = []
    for name in splits {
        let content = try String(contentsOf: corpusDir.appendingPathComponent("\(name).jsonl"), encoding: .utf8)
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            trials.append(try decoder.decode(Trial.self, from: Data(trimmed.utf8)))
        }
    }
    return trials
}

func prettyEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

func handleExportLayoutTables(_ options: Options) {
    guard let output = options.value("--output") else {
        print("export-layout-tables needs --output <new-dir>; frozen table versions are never regenerated in place")
        exit(1)
    }
    let outputDir = URL(fileURLWithPath: output)
    let existing = (try? FileManager.default.contentsOfDirectory(atPath: outputDir.path))?.filter { $0.hasSuffix(".json") } ?? []
    guard existing.isEmpty else {
        print("Refusing to overwrite \(existing.count) existing tables in \(outputDir.path); export into a new tables version")
        exit(1)
    }
    let keyboardTypes = options.value("--keyboard-types")?
        .split(separator: ",")
        .compactMap { UInt32($0.trimmingCharacters(in: .whitespaces)) } ?? [91, 37]

    do {
        let written = try TableExporter.exportAllStandardTables(outputDirectory: outputDir, keyboardTypes: keyboardTypes)
        print("Successfully exported \(written.count) layout tables to \(outputDir.path)")
    } catch {
        print("Error exporting layout tables: \(error)")
        exit(1)
    }
}

func handleGenerateSeedCorpus(_ options: Options) {
    guard let version = options.value("--version"), let definitions = SeedCorpusDefinitions.version(version) else {
        print("generate-seed-corpus needs --version v1|v2")
        exit(1)
    }
    let corpusDir = options.url("--corpus", default: "Benchmarks/layout-corpus/\(version)")
    let tablesDir = options.url("--tables", default: "Benchmarks/layout-tables/v1")
    let commit = options.value("--commit") ?? BenchmarkEnvironment.sourceState(commitOverride: nil).commit

    do {
        try ManifestGenerator.generateSeedCorpusAndManifest(corpusDir: corpusDir, tablesDir: tablesDir, sourceCommit: commit, definitions: definitions)
        print("Successfully generated seed corpus \(version) and manifest at \(corpusDir.path)")
    } catch {
        print("Error generating seed corpus: \(error)")
        exit(1)
    }
}

func handleValidate(_ options: Options) {
    let corpusDir = options.url("--corpus", default: "Benchmarks/layout-corpus/v1")
    let tablesDir = options.url("--tables", default: "Benchmarks/layout-tables/v1")
    let strict = options.flag("--strict")

    do {
        let result = try CorpusValidator.validate(corpusDirectory: corpusDir, tablesDirectory: tablesDir)
        for warning in result.warnings {
            print("  warning: \(warning)")
        }
        if !result.passed || (strict && !result.warnings.isEmpty) {
            print("Validation FAILED: \(result.errors.count) errors, \(result.warnings.count) warnings\(strict ? " (strict)" : ""):")
            for err in result.errors {
                print("  - \(err)")
            }
            exit(1)
        }
        print("Validation PASSED: \(result.trialsCount) trials validated across \(result.splitsCount) splits (\(result.warnings.count) warnings).")
        exit(0)
    } catch {
        print("Validation error: \(error)")
        exit(1)
    }
}

func execute(trials: [Trial], tables: [String: LayoutTable], layer: BenchmarkLayer) -> [TrialResult] {
    let adapter = SwitchFixAdapter(tables: tables)
    guard adapter.prewarm() else {
        print("Failed to prewarm SwitchFix adapter dictionaries")
        exit(1)
    }
    return trials.map { adapter.executeTrial(trial: $0, layer: layer) }
}

/// Lookups answered by an external dictionary backend during `run` (spike measurement).
var externalLookups = 0

func handleRun(_ options: Options) {
    let adapterName = options.value("--adapter") ?? "switchfix"
    let split = options.value("--split") ?? "development"
    let profile = options.value("--profile") ?? "boundary-layout-only"
    let corpusDir = options.url("--corpus", default: "Benchmarks/layout-corpus/v1")
    let tablesDir = options.url("--tables", default: "Benchmarks/layout-tables/v1")

    guard adapterName == "switchfix" else {
        print("competitor_unavailable: adapter '\(adapterName)' is not available")
        exit(1)
    }
    guard profile == "boundary-layout-only" else {
        print("Unsupported profile: \(profile)")
        exit(1)
    }
    guard let layer = BenchmarkLayer(rawValue: options.value("--layer") ?? "replay"), layer != .app else {
        print("Unsupported layer: the app layer is measured by manual conformance runs")
        exit(1)
    }
    let dictionaryMode: String
    switch options.value("--dictionary-backend") ?? "bundled" {
    case "bundled":
        dictionaryMode = "text-fallback-test"
    case "system", "system-lowercase":
        let checker = SystemSpellChecker.shared
        checker.casePolicy = options.value("--dictionary-backend") == "system" ? .lowercaseOrCapitalized : .lowercase
        dictionaryMode = "macos-spellchecker-\(checker.casePolicy.rawValue)"
        DictionaryLoader.shared.useExternalLookup { word, language in
            externalLookups += 1
            return checker.isValid(word, language: SystemSpellChecker.languageCode(for: language))
        }
    case let other:
        print("Unsupported dictionary backend: \(other)")
        exit(1)
    }

    do {
        try CorpusValidator.requireVerifiedInputs(corpusDirectory: corpusDir, tablesDirectory: tablesDir)
        let tables = try loadTables(from: tablesDir)
        let trials = try loadTrials(corpusDir: corpusDir, split: split)
        guard !trials.isEmpty else {
            print("No trials found for split '\(split)' in \(corpusDir.path)")
            exit(1)
        }

        let results = execute(trials: trials, tables: tables, layer: layer)
        if externalLookups > 0 {
            let boundaries = trials.reduce(0) { $0 + $1.events.filter { $0.type == "boundary" }.count }
            print("Dictionary lookups: \(externalLookups) for \(boundaries) word boundaries (\(String(format: "%.1f", Double(externalLookups) / Double(max(boundaries, 1)))) per boundary)\n")
        }
        let report = Scorer.score(trials: trials, results: results)
        let metadata = BenchmarkEnvironment.metadata(corpusDir: corpusDir, trials: trials, profile: profile, layer: layer, commitOverride: options.value("--commit"), dictionaryMode: dictionaryMode)
        let md = Scorer.renderMarkdown(report: report, split: split, adapter: adapterName)
        print(md)

        if let output = options.value("--output") {
            let outDir = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let reportURL = outDir.appendingPathComponent("report.md")
            try md.write(to: reportURL, atomically: true, encoding: .utf8)

            struct OutputEnvelope: Codable {
                let created: String
                let adapter: String
                let split: String
                let metadata: RunMetadata
                let report: BenchmarkScoreReport
                let results: [TrialResult]
            }
            let envelope = OutputEnvelope(
                created: ISO8601DateFormatter().string(from: Date()),
                adapter: adapterName,
                split: split,
                metadata: metadata,
                report: report,
                results: results
            )
            let jsonURL = outDir.appendingPathComponent("results.json")
            try prettyEncoder().encode(envelope).write(to: jsonURL)
            print("\nSaved report to \(reportURL.path) and results to \(jsonURL.path)")
        }

        print("\ncomparisonStatus: \(metadata.comparisonStatus)")

        if let baselinePath = options.value("--baseline") {
            let baseline = try JSONDecoder().decode(BaselineRecord.self, from: Data(contentsOf: URL(fileURLWithPath: baselinePath)))
            guard baseline.metadata.corpusManifestSha256 == metadata.corpusManifestSha256 else {
                print("Gate FAILED: baseline was recorded on a different corpus (manifest \(baseline.metadata.corpusManifestSha256.prefix(12)) vs \(metadata.corpusManifestSha256.prefix(12)))")
                exit(2)
            }
            guard baseline.metadata.layer == metadata.layer else {
                print("Gate FAILED: baseline was recorded on layer '\(baseline.metadata.layer)' but current run is on layer '\(metadata.layer)'")
                exit(2)
            }
            let findings = BaselineGate.regressions(current: report, baseline: baseline, split: split)
            if !report.complete || !findings.isEmpty {
                print("Gate FAILED against \(baselinePath):")
                if !report.complete {
                    print("  - run is incomplete: \(report.errorTrials) errors, \(report.missingTrials) missing")
                }
                for finding in findings {
                    print("  - \(finding.trialID): \(finding.baseline.rawValue) -> \(finding.current?.rawValue ?? "missing_trial")")
                }
                exit(2)
            }
            print("Gate PASSED against \(baselinePath): no trial lost its pass or coverage")
        }
    } catch {
        print("Execution error: \(error)")
        exit(1)
    }
}

func handleSummarize(_ options: Options) {
    let resultsDir = options.url("--results", default: "Benchmarks/results/current")
    let reportURL = resultsDir.appendingPathComponent("report.md")
    if let content = try? String(contentsOf: reportURL, encoding: .utf8) {
        print(content)
    } else {
        print("No report.md found at \(resultsDir.path)")
        exit(1)
    }
}

func handleRecordBaseline(_ options: Options) {
    guard let baselines = options.value("--baselines") else {
        print("record-baseline needs --baselines <dir>; recorded baselines are never overwritten in place")
        exit(1)
    }
    let corpusDir = options.url("--corpus", default: "Benchmarks/layout-corpus/v1")
    let tablesDir = options.url("--tables", default: "Benchmarks/layout-tables/v1")
    let baselinesDir = URL(fileURLWithPath: baselines)
    let baselineJSONURL = baselinesDir.appendingPathComponent("baseline.json")
    let baselineMDURL = baselinesDir.appendingPathComponent("baseline.md")
    guard !FileManager.default.fileExists(atPath: baselineJSONURL.path) else {
        print("Refusing to overwrite \(baselineJSONURL.path); record a new baseline version instead")
        exit(1)
    }

    var runnerChecks: [String: RunnerCheck] = [:]
    for entry in options.all("--runner-log") {
        let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, let check = BenchmarkEnvironment.runnerCheck(logPath: parts[1]) else {
            print("Could not read runner results from '\(entry)'")
            exit(1)
        }
        runnerChecks[parts[0]] = check
    }

    do {
        try CorpusValidator.requireVerifiedInputs(corpusDirectory: corpusDir, tablesDirectory: tablesDir)
        let tables = try loadTables(from: tablesDir)
        let devTrials = try loadTrials(corpusDir: corpusDir, split: "development")
        let holdoutTrials = try loadTrials(corpusDir: corpusDir, split: "holdout")
        let allTrials = devTrials + holdoutTrials
        let devResults = execute(trials: devTrials, tables: tables, layer: .replay)
        let holdoutResults = execute(trials: holdoutTrials, tables: tables, layer: .replay)
        let allResults = devResults + holdoutResults

        let metadata = BenchmarkEnvironment.metadata(
            corpusDir: corpusDir,
            trials: allTrials,
            profile: "boundary-layout-only",
            layer: .replay,
            commitOverride: options.value("--commit")
        )
        let record = BaselineRecord(
            schemaVersion: 2,
            baselineVersion: baselinesDir.pathComponents.suffix(2).joined(separator: "/"),
            created: ISO8601DateFormatter().string(from: Date()),
            metadata: metadata,
            runnerChecks: runnerChecks,
            development: Scorer.score(trials: devTrials, results: devResults),
            holdout: Scorer.score(trials: holdoutTrials, results: holdoutResults),
            combined: Scorer.score(trials: allTrials, results: allResults)
        )

        let rawOutputDir = URL(fileURLWithPath: "Benchmarks/results/baselines").appendingPathComponent(record.baselineVersion)
        try FileManager.default.createDirectory(at: rawOutputDir, withIntermediateDirectories: true)
        try prettyEncoder().encode(allResults).write(to: rawOutputDir.appendingPathComponent("all-results.json"))

        try FileManager.default.createDirectory(at: baselinesDir, withIntermediateDirectories: true)
        try prettyEncoder().encode(record).write(to: baselineJSONURL)
        let md = renderBaselineMarkdown(record: record, trials: allTrials, results: allResults)
        try md.write(to: baselineMDURL, atomically: true, encoding: .utf8)

        print(md)
        print("\nRecorded \(baselineJSONURL.path), \(baselineMDURL.path); raw results in \(rawOutputDir.path)")
    } catch {
        print("Error recording baseline: \(error)")
        exit(1)
    }
}

func renderBaselineMarkdown(record: BaselineRecord, trials: [Trial], results: [TrialResult]) -> String {
    let m = record.metadata
    var lines: [String] = []
    lines.append("# SwitchFix Baseline \(record.baselineVersion)")
    lines.append("")
    lines.append("Generated by `LayoutBenchmark record-baseline`; every value below is measured or read from the corpus.")
    lines.append("")
    lines.append("- **Recorded**: `\(record.created)`")
    lines.append("- **Source**: `\(m.sourceCommit)` (\(m.sourceTreeState))")
    lines.append("- **Environment**: macOS \(m.osVersion) (\(m.osBuild)), \(m.architecture), keyboard types \(m.keyboardTypes.map(String.init).joined(separator: ", ")), \(m.swiftVersion)")
    lines.append("- **Profile**: `\(m.profile)` (layer `\(m.layer)`), dictionaries `\(m.dictionaryMode)`, \(m.personalExceptions) personal exceptions, comparison `\(m.comparisonStatus)`")
    lines.append("- **Corpus**: `\(m.corpusVersion)` (manifest SHA-256 `\(m.corpusManifestSha256)`), tables `\(m.tablesVersion)`")
    lines.append("- **Detector thresholds**: " + m.detectorThresholds.keys.sorted().map { "\($0)=\(m.detectorThresholds[$0] ?? 0)" }.joined(separator: ", "))
    lines.append("")
    lines.append("## Runner Results")
    lines.append("")
    if record.runnerChecks.isEmpty {
        lines.append("No runner logs were supplied.")
    } else {
        lines.append("| Runner | Passed | Failed | Failures | Log |")
        lines.append("| --- | --- | --- | --- | --- |")
        for name in record.runnerChecks.keys.sorted() {
            guard let check = record.runnerChecks[name] else { continue }
            let failures = check.failures.isEmpty ? "none" : check.failures.joined(separator: "; ")
            lines.append("| `\(name)` | \(check.passed) | \(check.failed) | \(failures) | `\(check.log)` |")
        }
    }
    lines.append("")
    lines.append("## Aggregate Results")
    lines.append("")
    lines.append("| Split | Trials | Groups | Complete | Pos / Neg | TP | FN | Text FP | Layout FP | Recall (95% CI) | Text-Damage FP (95% CI) | Layout-Only FP (95% CI) | Precision (95% CI) |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    func row(_ name: String, _ r: BenchmarkScoreReport) -> String {
        func cell(_ metric: ScoredMetric, _ digits: Int) -> String {
            "\(Scorer.percent(metric.rate, digits: digits)) \(metric.interval?.formatted ?? "")"
        }
        return "| **\(name)** | \(r.totalTrials) | \(r.groupCount) | \(r.complete ? "yes" : "NO") | \(r.nPositive) / \(r.nNegative) | \(r.truePositives) | \(r.falseNegatives) | \(r.textDamageFPs) | \(r.layoutOnlyFPs) | \(cell(r.recall, 1)) | \(cell(r.textDamageFPRate, 2)) | \(cell(r.layoutOnlyFPRate, 2)) | \(cell(r.precision, 1)) |"
    }
    lines.append(row("Development", record.development))
    lines.append(row("Holdout", record.holdout))
    lines.append(row("Combined", record.combined))
    lines.append("")
    lines.append("## Direction Breakdown (Combined)")
    lines.append("")
    lines.append("| Direction | Trials | TP | FN | TN | Text FP | Layout FP | Errors | Unsupported | Recall | Text-Damage FP |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for dir in record.combined.directionBreakdown.keys.sorted() {
        guard let d = record.combined.directionBreakdown[dir] else { continue }
        lines.append("| \(dir) | \(d.total) | \(d.tp) | \(d.fn) | \(d.tn) | \(d.textFP) | \(d.layoutFP) | \(d.errors) | \(d.unsupported) | \(Scorer.percent(d.recall)) | \(Scorer.percent(d.textDamageFPRate, digits: 2)) |")
    }
    lines.append("")
    lines.append("## Category Breakdown (Combined)")
    lines.append("")
    lines.append("| Category | Trials | TP | FN | TN | Text FP | Layout FP |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    for category in record.combined.categoryBreakdown.keys.sorted() {
        guard let c = record.combined.categoryBreakdown[category] else { continue }
        lines.append("| \(category) | \(c.total) | \(c.tp) | \(c.fn) | \(c.tn) | \(c.textFP) | \(c.layoutFP) |")
    }
    lines.append("")
    lines.append("## Trials That Did Not Pass")
    lines.append("")
    let resultsByID = Dictionary(results.map { ($0.trialID, $0) }, uniquingKeysWith: { first, _ in first })
    let failing = trials.filter { !(record.combined.trialOutcomes[$0.id]?.isPassing ?? false) }
    if failing.isEmpty {
        lines.append("None.")
    } else {
        lines.append("| Trial | Label | Category | Outcome | Expected | Observed | Reason codes |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- |")
        for trial in failing {
            let result = resultsByID[trial.id]
            let outcome = record.combined.trialOutcomes[trial.id]?.rawValue ?? "missing"
            let observed = result.map { "`\($0.finalText)` @ \($0.finalSourceID)" } ?? "missing"
            let reasons = result?.reasonCodes.joined(separator: ", ") ?? ""
            lines.append("| \(trial.id) | \(trial.label) | \(trial.category) | \(outcome) | `\(trial.expected.text)` @ \(trial.expected.sourceID) | \(observed) | \(reasons) |")
        }
    }
    if !record.combined.reasonCodeCounts.isEmpty {
        lines.append("")
        lines.append("## Reason Codes (Combined)")
        lines.append("")
        for code in record.combined.reasonCodeCounts.keys.sorted() {
            lines.append("- `\(code)`: \(record.combined.reasonCodeCounts[code] ?? 0) trials")
        }
    }
    lines.append("")
    return lines.joined(separator: "\n")
}

main()

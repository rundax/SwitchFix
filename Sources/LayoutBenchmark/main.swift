import Foundation

func main() {
    let args = CommandLine.arguments
    if args.count < 2 {
        printUsage()
        exit(1)
    }

    let command = args[1]
    switch command {
    case "export-layout-tables":
        handleExportLayoutTables(args: Array(args.dropFirst(2)))
    case "generate-seed-corpus":
        handleGenerateSeedCorpus(args: Array(args.dropFirst(2)))
    case "validate":
        handleValidate(args: Array(args.dropFirst(2)))
    case "run":
        handleRun(args: Array(args.dropFirst(2)))
    case "summarize":
        handleSummarize(args: Array(args.dropFirst(2)))
    case "self-check":
        print("self-check not yet implemented (scheduled for Plan-Item 03.3)")
        exit(0)
    case "compare":
        print("compare not yet implemented (scheduled for Plan-Item 03.5)")
        exit(0)
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
      export-layout-tables [--output <dir>] [--keyboard-types <type1,type2>]
      generate-seed-corpus [--corpus <dir>] [--tables <dir>] [--commit <sha>]
      validate [--corpus <corpus-dir>] [--tables <tables-dir>]
      run [--adapter switchfix] [--split development|holdout|all] [--layer decision|replay|app] [--profile boundary-layout-only] [--output <dir>]
      summarize [--results <dir>]
      self-check
      compare
    """)
}

func handleExportLayoutTables(args: [String]) {
    var outputDir = URL(fileURLWithPath: "Benchmarks/layout-tables/v1")
    var keyboardTypes: [UInt32] = [91, 37]

    var i = 0
    while i < args.count {
        if args[i] == "--output" && i + 1 < args.count {
            outputDir = URL(fileURLWithPath: args[i + 1])
            i += 2
        } else if args[i] == "--keyboard-types" && i + 1 < args.count {
            keyboardTypes = args[i + 1].split(separator: ",").compactMap { UInt32($0.trimmingCharacters(in: .whitespaces)) }
            i += 2
        } else {
            i += 1
        }
    }

    do {
        let written = try TableExporter.exportAllStandardTables(outputDirectory: outputDir, keyboardTypes: keyboardTypes)
        print("Successfully exported \(written.count) layout tables to \(outputDir.path)")
    } catch {
        print("Error exporting layout tables: \(error)")
        exit(1)
    }
}

func handleGenerateSeedCorpus(args: [String]) {
    var corpusDir = URL(fileURLWithPath: "Benchmarks/layout-corpus/v1")
    var tablesDir = URL(fileURLWithPath: "Benchmarks/layout-tables/v1")
    var commit = "b8471649300162827cc4053d553c14a895820e8b"

    var i = 0
    while i < args.count {
        if args[i] == "--corpus" && i + 1 < args.count {
            corpusDir = URL(fileURLWithPath: args[i + 1])
            i += 2
        } else if args[i] == "--tables" && i + 1 < args.count {
            tablesDir = URL(fileURLWithPath: args[i + 1])
            i += 2
        } else if args[i] == "--commit" && i + 1 < args.count {
            commit = args[i + 1]
            i += 2
        } else {
            i += 1
        }
    }

    do {
        try ManifestGenerator.generateSeedCorpusAndManifest(corpusDir: corpusDir, tablesDir: tablesDir, sourceCommit: commit)
        print("Successfully generated seed corpus and manifest at \(corpusDir.path)")
    } catch {
        print("Error generating seed corpus: \(error)")
        exit(1)
    }
}

func handleValidate(args: [String]) {
    var corpusDir = URL(fileURLWithPath: "Benchmarks/layout-corpus/v1")
    var tablesDir = URL(fileURLWithPath: "Benchmarks/layout-tables/v1")

    var i = 0
    while i < args.count {
        if args[i] == "--corpus" && i + 1 < args.count {
            corpusDir = URL(fileURLWithPath: args[i + 1])
            i += 2
        } else if args[i] == "--tables" && i + 1 < args.count {
            tablesDir = URL(fileURLWithPath: args[i + 1])
            i += 2
        } else {
            i += 1
        }
    }

    do {
        let result = try CorpusValidator.validate(corpusDirectory: corpusDir, tablesDirectory: tablesDir)
        if !result.passed {
            print("Validation FAILED: \(result.errors.count) errors found:")
            for err in result.errors {
                print("  - \(err)")
            }
            exit(1)
        } else {
            print("Validation PASSED: \(result.trialsCount) trials validated across \(result.splitsCount) splits.")
            exit(0)
        }
    } catch {
        print("Validation error: \(error)")
        exit(1)
    }
}

func handleRun(args: [String]) {
    var adapterName = "switchfix"
    var split = "development"
    var layerStr = "replay"
    var profile = "boundary-layout-only"
    var corpusDir = URL(fileURLWithPath: "Benchmarks/layout-corpus/v1")
    var tablesDir = URL(fileURLWithPath: "Benchmarks/layout-tables/v1")
    var outputDir: URL? = nil

    var i = 0
    while i < args.count {
        if args[i] == "--adapter" && i + 1 < args.count {
            adapterName = args[i + 1]
            i += 2
        } else if args[i] == "--split" && i + 1 < args.count {
            split = args[i + 1]
            i += 2
        } else if args[i] == "--layer" && i + 1 < args.count {
            layerStr = args[i + 1]
            i += 2
        } else if args[i] == "--profile" && i + 1 < args.count {
            profile = args[i + 1]
            i += 2
        } else if args[i] == "--corpus" && i + 1 < args.count {
            corpusDir = URL(fileURLWithPath: args[i + 1])
            i += 2
        } else if args[i] == "--tables" && i + 1 < args.count {
            tablesDir = URL(fileURLWithPath: args[i + 1])
            i += 2
        } else if args[i] == "--output" && i + 1 < args.count {
            outputDir = URL(fileURLWithPath: args[i + 1])
            i += 2
        } else {
            i += 1
        }
    }

    let layer = BenchmarkLayer(rawValue: layerStr) ?? .replay

    guard adapterName == "switchfix" else {
        print("Unsupported adapter: \(adapterName) (only 'switchfix' is supported in this release)")
        exit(1)
    }

    do {
        // Load layout tables
        var tables: [String: LayoutTable] = [:]
        let tableFiles = try FileManager.default.contentsOfDirectory(at: tablesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        for tURL in tableFiles {
            let key = tURL.deletingPathExtension().lastPathComponent
            if let table = try? LayoutTable.load(from: tURL) {
                tables[key] = table
            }
        }

        // Load trials
        var trials: [Trial] = []
        let decoder = JSONDecoder()

        if split == "development" || split == "all" {
            let devURL = corpusDir.appendingPathComponent("development.jsonl")
            let devContent = try String(contentsOf: devURL, encoding: .utf8)
            for line in devContent.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if let data = trimmed.data(using: .utf8) {
                    trials.append(try decoder.decode(Trial.self, from: data))
                }
            }
        }

        if split == "holdout" || split == "all" {
            let holdoutURL = corpusDir.appendingPathComponent("holdout.jsonl")
            let holdoutContent = try String(contentsOf: holdoutURL, encoding: .utf8)
            for line in holdoutContent.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if let data = trimmed.data(using: .utf8) {
                    trials.append(try decoder.decode(Trial.self, from: data))
                }
            }
        }

        guard !trials.isEmpty else {
            print("No trials found for split '\(split)' in \(corpusDir.path)")
            exit(1)
        }

        let adapter = SwitchFixAdapter(tables: tables)
        guard adapter.prewarm() else {
            print("Failed to prewarm SwitchFix adapter dictionaries")
            exit(1)
        }

        var results: [TrialResult] = []
        for trial in trials {
            let res = adapter.executeTrial(trial: trial, layer: layer)
            results.append(res)
        }

        let report = Scorer.score(trials: trials, results: results)
        let md = Scorer.renderMarkdown(report: report, split: split, adapter: adapterName)
        print(md)

        if let outDir = outputDir {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let reportURL = outDir.appendingPathComponent("report.md")
            try md.write(to: reportURL, atomically: true, encoding: .utf8)

            struct OutputEnvelope: Codable {
                let timestamp: String
                let adapter: String
                let split: String
                let layer: String
                let profile: String
                let report: BenchmarkScoreReport
                let results: [TrialResult]
            }

            let envelope = OutputEnvelope(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                adapter: adapterName,
                split: split,
                layer: layerStr,
                profile: profile,
                report: report,
                results: results
            )

            let jsonURL = outDir.appendingPathComponent("results.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(envelope)
            try jsonData.write(to: jsonURL)
            print("\nSaved report to \(reportURL.path) and results to \(jsonURL.path)")
        }

    } catch {
        print("Execution error: \(error)")
        exit(1)
    }
}

func handleSummarize(args: [String]) {
    var resultsDir = URL(fileURLWithPath: "Benchmarks/results/current")

    var i = 0
    while i < args.count {
        if args[i] == "--results" && i + 1 < args.count {
            resultsDir = URL(fileURLWithPath: args[i + 1])
            i += 2
        } else {
            i += 1
        }
    }

    let reportURL = resultsDir.appendingPathComponent("report.md")
    if let content = try? String(contentsOf: reportURL, encoding: .utf8) {
        print(content)
    } else {
        print("No report.md found at \(resultsDir.path)")
        exit(1)
    }
}

main()

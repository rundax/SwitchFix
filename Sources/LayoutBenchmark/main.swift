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
    case "self-check":
        print("self-check not yet implemented (scheduled for Plan-Item 03.3)")
        exit(0)
    case "run":
        print("run not yet implemented (scheduled for Plan-Item 03.2)")
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
      self-check
      run
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

main()

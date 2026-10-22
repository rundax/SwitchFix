import Core
import Foundation

/// Environment and inputs a run was measured with. Everything here is measured or read from
/// the corpus, never typed in by hand.
public struct RunMetadata: Codable, Equatable, Sendable {
    public let sourceCommit: String
    /// "clean", "dirty", or "unknown" when no git metadata is available.
    public let sourceTreeState: String
    public let swiftVersion: String
    public let osVersion: String
    public let osBuild: String
    public let architecture: String
    public let keyboardTypes: [UInt32]
    public let dictionaryMode: String
    public let profile: String
    public let layer: String
    public let corpusVersion: String
    public let corpusManifestSha256: String
    public let tablesVersion: String
    public let detectorThresholds: [String: Int]
    public let personalExceptions: Int
    public let comparisonStatus: String
}

public struct RunnerCheck: Codable, Equatable, Sendable {
    public let passed: Int
    public let failed: Int
    public let failures: [String]
    public let log: String
}

public struct BaselineRecord: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let baselineVersion: String
    public let created: String
    public let metadata: RunMetadata
    public let runnerChecks: [String: RunnerCheck]
    public let development: BenchmarkScoreReport
    public let holdout: BenchmarkScoreReport
    public let combined: BenchmarkScoreReport
}

public enum BenchmarkEnvironment {
    static func run(_ launchPath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Commit and tree state of the sources that build the measured binary.
    public static func sourceState(commitOverride: String?) -> (commit: String, state: String) {
        guard let head = run("/usr/bin/git", ["rev-parse", "HEAD"]) else {
            return (commitOverride ?? "unknown", "unknown")
        }
        let status = run("/usr/bin/git", ["status", "--porcelain", "--untracked-files=all", "--", "Sources", "Package.swift", "Benchmarks/layout-corpus", "Benchmarks/layout-tables"]) ?? "?"
        return (commitOverride ?? head, status.isEmpty ? "clean" : "dirty")
    }

    public static func swiftVersion() -> String {
        run("/usr/bin/xcrun", ["swift", "--version"])?.components(separatedBy: "\n").first ?? "unknown"
    }

    public static func architecture() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    public static func detectorThresholds() -> [String: Int] {
        let detector = LayoutDetector()
        return [
            "detectionThreshold": detector.detectionThreshold,
            "consecutiveThreshold": detector.consecutiveThreshold,
            "lowConfidenceMaxLength": detector.lowConfidenceMaxLength,
            "lowConfidenceConfirmations": detector.lowConfidenceConfirmations,
            "shortWordSuppressionLength": detector.shortWordSuppressionLength,
            "shortWordSuppressionMinValidContext": detector.shortWordSuppressionMinValidContext,
            "shortWordSuppressionContextWindow": detector.shortWordSuppressionContextWindow
        ]
    }

    public static func metadata(
        corpusDir: URL,
        trials: [Trial],
        profile: String,
        layer: BenchmarkLayer,
        commitOverride: String?,
        dictionaryMode: String = "text-fallback-test"
    ) -> RunMetadata {
        let manifestURL = corpusDir.appendingPathComponent("manifest.json")
        let manifest = (try? Data(contentsOf: manifestURL)).flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
        let source = sourceState(commitOverride: commitOverride)
        return RunMetadata(
            sourceCommit: source.commit,
            sourceTreeState: source.state,
            swiftVersion: swiftVersion(),
            osVersion: TableExporter.osVersionString(),
            osBuild: TableExporter.osBuildVersion(),
            architecture: architecture(),
            keyboardTypes: Set(trials.map { $0.initial.keyboardType ?? 91 }).sorted(),
            dictionaryMode: dictionaryMode,
            profile: profile,
            layer: layer.rawValue,
            corpusVersion: manifest?.corpusVersion ?? corpusDir.lastPathComponent,
            corpusManifestSha256: (try? ManifestGenerator.sha256(for: manifestURL)) ?? "missing",
            tablesVersion: manifest?.tablesVersion ?? "unknown",
            detectorThresholds: detectorThresholds(),
            personalExceptions: 0,
            comparisonStatus: "not_run"
        )
    }

    /// Parses a runner log ("Results: N passed, M failed" or "Input pipeline: N passed, M failed").
    public static func runnerCheck(logPath: String) -> RunnerCheck? {
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else { return nil }
        var passed: Int?
        var failed: Int?
        var failures: [String] = []
        let pattern = try? NSRegularExpression(pattern: "(\\d+) passed, (\\d+) failed")
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("FAIL") {
                failures.append(trimmed)
            }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = pattern?.firstMatch(in: trimmed, range: range),
               let p = Range(match.range(at: 1), in: trimmed),
               let f = Range(match.range(at: 2), in: trimmed) {
                passed = Int(trimmed[p])
                failed = Int(trimmed[f])
            }
        }
        guard let passed, let failed else { return nil }
        return RunnerCheck(passed: passed, failed: failed, failures: failures, log: logPath)
    }
}

/// Per-trial regression gate against a recorded baseline of the same corpus version.
public enum BaselineGate {
    public struct Finding: Equatable, Sendable {
        public let trialID: String
        public let baseline: TrialOutcome
        public let current: TrialOutcome?
    }

    public static func regressions(current: BenchmarkScoreReport, baseline: BaselineRecord, split: String = "all") -> [Finding] {
        let baselineOutcomes: [String: TrialOutcome]
        switch split {
        case "development": baselineOutcomes = baseline.development.trialOutcomes
        case "holdout": baselineOutcomes = baseline.holdout.trialOutcomes
        case "all": baselineOutcomes = baseline.development.trialOutcomes.merging(baseline.holdout.trialOutcomes) { first, _ in first }
        default: preconditionFailure("Unknown baseline split: \(split)")
        }
        return Set(current.trialOutcomes.keys).union(baselineOutcomes.keys).sorted().compactMap { id in
            guard let now = current.trialOutcomes[id] else {
                return Finding(trialID: id, baseline: baselineOutcomes[id]!, current: nil)
            }
            guard let before = baselineOutcomes[id] else {
                return now.isPassing ? nil : Finding(trialID: id, baseline: .unsupported, current: now)
            }
            let lostPass = before.isPassing && !now.isPassing
            let lostCoverage = before != .unsupported && now == .unsupported
            return lostPass || lostCoverage ? Finding(trialID: id, baseline: before, current: now) : nil
        }
    }
}

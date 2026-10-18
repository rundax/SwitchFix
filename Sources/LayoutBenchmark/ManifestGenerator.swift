import Foundation
import CryptoKit

public enum ManifestGenerator {
    public static func sha256(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func generateSeedCorpusAndManifest(
        corpusDir: URL,
        tablesDir: URL,
        sourceCommit: String
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: corpusDir, withIntermediateDirectories: true)

        let abcURL = tablesDir.appendingPathComponent("com.apple.keylayout.ABC@91.json")
        let ukURL = tablesDir.appendingPathComponent("com.apple.keylayout.Ukrainian@91.json")

        guard fileManager.fileExists(atPath: abcURL.path) else {
            throw NSError(domain: "ManifestGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing table at \(abcURL.path)"])
        }
        guard fileManager.fileExists(atPath: ukURL.path) else {
            throw NSError(domain: "ManifestGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing table at \(ukURL.path)"])
        }

        let abcTable = try LayoutTable.load(from: abcURL)
        let ukTable = try LayoutTable.load(from: ukURL)

        // Generate development trials
        var devTrials: [Trial] = []
        for (idx, item) in SeedCorpusDefinitions.developmentItems.enumerated() {
            let id = String(format: "dev-%@-%03d", item.label, idx + 1)
            let trial = try SeedCorpusGenerator.generateTrial(
                id: id,
                item: item,
                split: "development",
                abcTable: abcTable,
                ukTable: ukTable
            )
            devTrials.append(trial)
        }

        // Generate holdout trials
        var holdoutTrials: [Trial] = []
        for (idx, item) in SeedCorpusDefinitions.holdoutItems.enumerated() {
            let id = String(format: "holdout-%@-%03d", item.label, idx + 1)
            let trial = try SeedCorpusGenerator.generateTrial(
                id: id,
                item: item,
                split: "holdout",
                abcTable: abcTable,
                ukTable: ukTable
            )
            holdoutTrials.append(trial)
        }

        let encoder = JSONEncoder()

        // Write development.jsonl
        let devURL = corpusDir.appendingPathComponent("development.jsonl")
        var devLines: [String] = []
        for trial in devTrials {
            let data = try encoder.encode(trial)
            if let line = String(data: data, encoding: .utf8) {
                devLines.append(line)
            }
        }
        try (devLines.joined(separator: "\n") + "\n").write(to: devURL, atomically: true, encoding: .utf8)

        // Write holdout.jsonl
        let holdoutURL = corpusDir.appendingPathComponent("holdout.jsonl")
        var holdoutLines: [String] = []
        for trial in holdoutTrials {
            let data = try encoder.encode(trial)
            if let line = String(data: data, encoding: .utf8) {
                holdoutLines.append(line)
            }
        }
        try (holdoutLines.joined(separator: "\n") + "\n").write(to: holdoutURL, atomically: true, encoding: .utf8)

        // Write README.md
        let readmeURL = corpusDir.appendingPathComponent("README.md")
        let readmeContent = """
        # Layout Benchmark Corpus v1

        Version: 1.0 (Frozen Seed Baseline)
        Specification: `docs/plans/03-comparative-false-positive-benchmark.md`
        Source commit: `\(sourceCommit)`

        ## Overview

        This directory contains the frozen 200-trial seed corpus for the SwitchFix comparative layout reliability benchmark:
        - `development.jsonl`: 100 trials used during development and regression testing
        - `holdout.jsonl`: 100 trials reserved for generalization evaluation
        - `manifest.json`: Cryptographic integrity hashes and split distributions

        ## Split Structure (Per Split)

        Each split contains exactly 100 trials:
        - **20 Repair** trials: Intentional layout errors requiring automatic repair (10 English → Ukrainian, 10 Ukrainian → English)
        - **60 Preserve** trials: Intentional correct text requiring preservation with no modifications (30 typed under ABC, 30 typed under Ukrainian)
        - **20 Abstain** trials: Ambiguous or unsupported inputs requiring no automatic action (10 typed under ABC, 10 typed under Ukrainian)

        Base group IDs (`groupID`) are completely disjoint across the development and holdout splits.

        ## Trial Schema & Provenance

        Every row in the JSONL files is an independent JSON object:
        - `schemaVersion`: 1
        - `id`: Unique identifier across all splits
        - `groupID`: Base entity / sentence group (disjoint across splits)
        - `split`: `"development"` or `"holdout"`
        - `languages`: Array of relevant language codes (e.g. `["en", "uk"]`)
        - `category`: Strata label (e.g. `single-word`, `capitalized`, `code-token`, `acronym`, `ambiguous-short`, etc.)
        - `label`: Target behavior (`repair`, `preserve`, or `abstain`)
        - `provenance`: Synthetic generation metadata with `"review": "pending-human"`
        - `initial`: Starting editor state (sourceID, language, text, caretUTF16, preferredCyrillic, keyboardType)
        - `events`: Array of physical key and boundary events (keyCode, modifiers, rendered)
        - `expected`: Target outcome (text, language, sourceID, allowedAutomaticActions, checkpoints)

        ## Deterministic Rendering

        Events are rendered using the frozen layout tables in `Benchmarks/layout-tables/v1/`. The `rendered` field in each event is verified against the table output for the given keyCode and modifiers.
        """
        try readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)

        // Compute hashes for all corpus files and layout table files
        var filesMap: [String: FileChecksum] = [:]

        let devSha = try sha256(for: devURL)
        filesMap["layout-corpus/v1/development.jsonl"] = FileChecksum(sha256: devSha, trialsCount: devTrials.count)

        let holdoutSha = try sha256(for: holdoutURL)
        filesMap["layout-corpus/v1/holdout.jsonl"] = FileChecksum(sha256: holdoutSha, trialsCount: holdoutTrials.count)

        let readmeSha = try sha256(for: readmeURL)
        filesMap["layout-corpus/v1/README.md"] = FileChecksum(sha256: readmeSha, trialsCount: nil)

        // Hash layout tables
        let tableFiles = try fileManager.contentsOfDirectory(at: tablesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for tURL in tableFiles {
            let relPath = "layout-tables/v1/\(tURL.lastPathComponent)"
            let tSha = try sha256(for: tURL)
            filesMap[relPath] = FileChecksum(sha256: tSha, trialsCount: nil)
        }

        let devSummary = SplitSummary(repair: 20, preserve: 60, abstain: 20, total: 100)
        let holdoutSummary = SplitSummary(repair: 20, preserve: 60, abstain: 20, total: 100)

        let manifest = Manifest(
            schemaVersion: 1,
            corpusVersion: "v1",
            tablesVersion: "v1",
            created: "2026-10-19",
            osVersion: TableExporter.osVersionString(),
            osBuild: TableExporter.osBuildVersion(),
            keyboardType: 91,
            sourceCommit: sourceCommit,
            files: filesMap,
            splits: [
                "development": devSummary,
                "holdout": holdoutSummary
            ]
        )

        let manifestURL = corpusDir.appendingPathComponent("manifest.json")
        let manifestEncoder = JSONEncoder()
        manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try manifestEncoder.encode(manifest)
        try manifestData.write(to: manifestURL)
    }
}

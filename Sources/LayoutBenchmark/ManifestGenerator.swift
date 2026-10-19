import Foundation
import CryptoKit

public enum ManifestGenerator {
    public static func sha256(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes one corpus version byte-deterministically: sorted JSON keys, fixed dates and the
    /// definition order, so regenerating a version reproduces its manifest hashes.
    public static func generateSeedCorpusAndManifest(
        corpusDir: URL,
        tablesDir: URL,
        sourceCommit: String,
        definitions: SeedCorpusVersion
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: corpusDir, withIntermediateDirectories: true)

        let abcURL = tablesDir.appendingPathComponent("com.apple.keylayout.ABC@91.json")
        let ukURL = tablesDir.appendingPathComponent("com.apple.keylayout.Ukrainian@91.json")
        let abcTable = try LayoutTable.load(from: abcURL)
        let ukTable = try LayoutTable.load(from: ukURL)

        func trials(_ items: [SeedItemDefinition], split: String, prefix: String) throws -> [Trial] {
            try items.enumerated().map { idx, item in
                try SeedCorpusGenerator.generateTrial(
                    id: item.id ?? String(format: "%@-%@-%03d", prefix, item.label, idx + 1),
                    item: item,
                    split: split,
                    generator: definitions.generator,
                    abcTable: abcTable,
                    ukTable: ukTable
                )
            }
        }
        let devTrials = try trials(definitions.developmentItems, split: "development", prefix: "dev")
        let holdoutTrials = try trials(definitions.holdoutItems, split: "holdout", prefix: "holdout")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func writeJSONL(_ list: [Trial], to url: URL) throws {
            let lines = try list.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        }

        let devURL = corpusDir.appendingPathComponent("development.jsonl")
        let holdoutURL = corpusDir.appendingPathComponent("holdout.jsonl")
        try writeJSONL(devTrials, to: devURL)
        try writeJSONL(holdoutTrials, to: holdoutURL)

        func summary(_ list: [Trial]) -> SplitSummary {
            SplitSummary(
                repair: list.filter { $0.label == "repair" }.count,
                preserve: list.filter { $0.label == "preserve" }.count,
                abstain: list.filter { $0.label == "abstain" }.count,
                total: list.count
            )
        }
        let summaries = ["development": summary(devTrials), "holdout": summary(holdoutTrials)]

        let readmeURL = corpusDir.appendingPathComponent("README.md")
        try Data((definitions.readme(sourceCommit, summaries) + "\n").utf8).write(to: readmeURL)

        let corpusPrefix = "layout-corpus/\(definitions.version)"
        var filesMap: [String: FileChecksum] = [:]
        filesMap["\(corpusPrefix)/development.jsonl"] = FileChecksum(sha256: try sha256(for: devURL), trialsCount: devTrials.count)
        filesMap["\(corpusPrefix)/holdout.jsonl"] = FileChecksum(sha256: try sha256(for: holdoutURL), trialsCount: holdoutTrials.count)
        filesMap["\(corpusPrefix)/README.md"] = FileChecksum(sha256: try sha256(for: readmeURL), trialsCount: nil)

        let tablesVersion = tablesDir.lastPathComponent
        let tableFiles = try fileManager.contentsOfDirectory(at: tablesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for tURL in tableFiles {
            filesMap["layout-tables/\(tablesVersion)/\(tURL.lastPathComponent)"] = FileChecksum(sha256: try sha256(for: tURL), trialsCount: nil)
        }

        let manifest = Manifest(
            schemaVersion: 1,
            corpusVersion: definitions.version,
            tablesVersion: tablesVersion,
            created: definitions.created,
            osVersion: abcTable.osVersion,
            osBuild: abcTable.osBuild,
            keyboardType: abcTable.keyboardType,
            sourceCommit: sourceCommit,
            files: filesMap,
            splits: summaries
        )

        let manifestEncoder = JSONEncoder()
        manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try manifestEncoder.encode(manifest).write(to: corpusDir.appendingPathComponent("manifest.json"))
    }
}

import Foundation

public struct ValidationResult: Sendable {
    public let passed: Bool
    public let trialsCount: Int
    public let splitsCount: Int
    public let errors: [String]
    /// Problems a frozen version may carry but a new version must not (`validate --strict`).
    public let warnings: [String]

    public init(passed: Bool, trialsCount: Int, splitsCount: Int, errors: [String], warnings: [String] = []) {
        self.passed = passed
        self.trialsCount = trialsCount
        self.splitsCount = splitsCount
        self.errors = errors
        self.warnings = warnings
    }
}

public enum CorpusValidator {
    public static let supportedEventTypes: Set<String> = ["key", "boundary", "delete"]
    public static let reviewStates: Set<String> = ["pending-human", "reviewed"]

    public static func validate(corpusDirectory: URL, tablesDirectory: URL) throws -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        var loadedTables: [String: LayoutTable] = [:]

        func getTable(sourceID: String, keyboardType: UInt32) -> LayoutTable? {
            let key = "\(sourceID)@\(keyboardType)"
            if let existing = loadedTables[key] { return existing }
            // Exact keyboard type only: another type's table is not evidence for this one.
            guard let table = try? LayoutTable.load(from: tablesDirectory.appendingPathComponent("\(key).json")) else {
                return nil
            }
            loadedTables[key] = table
            return table
        }

        let devURL = corpusDirectory.appendingPathComponent("development.jsonl")
        let holdoutURL = corpusDirectory.appendingPathComponent("holdout.jsonl")

        guard FileManager.default.fileExists(atPath: devURL.path) else {
            return ValidationResult(passed: false, trialsCount: 0, splitsCount: 0, errors: ["Missing development.jsonl at \(devURL.path)"])
        }
        guard FileManager.default.fileExists(atPath: holdoutURL.path) else {
            return ValidationResult(passed: false, trialsCount: 0, splitsCount: 0, errors: ["Missing holdout.jsonl at \(holdoutURL.path)"])
        }

        errors += verifyManifest(corpusDirectory: corpusDirectory)

        let devTrials = try loadJSONL(from: devURL)
        let holdoutTrials = try loadJSONL(from: holdoutURL)

        var seenIDs: Set<String> = []
        var devGroups: Set<String> = []
        var holdoutGroups: Set<String> = []
        // Identical input (source, initial text, keys) must carry one label everywhere.
        var labelsByInput: [String: [(id: String, split: String, label: String)]] = [:]
        var splitsByBaseText: [String: [(id: String, split: String)]] = [:]

        func validateTrial(_ trial: Trial, expectedSplit: String, file: String, lineNum: Int) {
            let prefix = "[\(file):\(lineNum) id=\(trial.id)]"

            if trial.schemaVersion != 1 {
                errors.append("\(prefix) Unknown schemaVersion \(trial.schemaVersion)")
            }

            if seenIDs.contains(trial.id) {
                errors.append("\(prefix) Duplicate trial ID: \(trial.id)")
            }
            seenIDs.insert(trial.id)

            if trial.split != expectedSplit {
                errors.append("\(prefix) Trial split '\(trial.split)' does not match expected file split '\(expectedSplit)'")
            }

            if !reviewStates.contains(trial.provenance.review) {
                errors.append("\(prefix) Provenance review must be one of \(reviewStates.sorted()), got '\(trial.provenance.review)'")
            }

            let validLabels = ["repair", "preserve", "abstain"]
            if !validLabels.contains(trial.label) {
                errors.append("\(prefix) Invalid label: \(trial.label)")
            }

            let initialText = trial.initial.text
            let caret = trial.initial.caretUTF16
            let characterBoundaries = Set(initialText.indices.map { $0.utf16Offset(in: initialText) }).union([initialText.utf16.count])
            if caret < 0 || caret > initialText.utf16.count {
                errors.append("\(prefix) caretUTF16 \(caret) outside 0...\(initialText.utf16.count)")
            } else if !characterBoundaries.contains(caret) {
                errors.append("\(prefix) caretUTF16 \(caret) is not on a character boundary")
            } else if caret != initialText.utf16.count {
                errors.append("\(prefix) caretUTF16 \(caret) must be at end of initial text (\(initialText.utf16.count))")
            }

            var editor = VirtualEditor(text: initialText)
            for event in trial.events {
                switch event.type {
                case "key", "boundary": editor.type(event.rendered)
                case "delete": editor.deleteBackward()
                default: errors.append("\(prefix) Unsupported event type '\(event.type)'")
                }
            }
            let typedText = editor.text

            switch trial.label {
            case "repair":
                if trial.expected.allowedAutomaticActions.isEmpty {
                    errors.append("\(prefix) Repair label must have non-empty allowedAutomaticActions")
                }
                if trial.expected.text == typedText && trial.expected.sourceID == trial.initial.sourceID {
                    errors.append("\(prefix) Repair label must specify a text change or source change compared to typed text")
                }
            case "preserve", "abstain":
                if !trial.expected.allowedAutomaticActions.isEmpty {
                    errors.append("\(prefix) Label '\(trial.label)' must have empty allowedAutomaticActions, got \(trial.expected.allowedAutomaticActions)")
                }
                if trial.expected.text != typedText {
                    errors.append("\(prefix) Label '\(trial.label)' expected text '\(trial.expected.text)' does not match typed text '\(typedText)'")
                }
                if trial.expected.sourceID != trial.initial.sourceID {
                    errors.append("\(prefix) Label '\(trial.label)' expected sourceID '\(trial.expected.sourceID)' does not match initial sourceID '\(trial.initial.sourceID)'")
                }
            default:
                break
            }

            for cp in trial.expected.checkpoints {
                if cp.afterEvent > trial.events.count || cp.afterEvent < 0 {
                    errors.append("\(prefix) Checkpoint afterEvent \(cp.afterEvent) out of range 0...\(trial.events.count)")
                }
            }

            let inputKey = ([trial.initial.sourceID, initialText] + trial.events.map { "\($0.type):\($0.keyCode):\($0.modifiers.sorted().joined(separator: "+"))" })
                .joined(separator: "\u{1F}")
            labelsByInput[inputKey, default: []].append((trial.id, trial.split, trial.label))
            let baseText = trial.expected.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            splitsByBaseText[baseText, default: []].append((trial.id, trial.split))

            let kbdType = trial.initial.keyboardType ?? 91
            guard let table = getTable(sourceID: trial.initial.sourceID, keyboardType: kbdType) else {
                errors.append("\(prefix) Missing layout table for \(trial.initial.sourceID)@\(kbdType)")
                return
            }

            for (idx, event) in trial.events.enumerated() where event.type != "delete" {
                if event.keyCode >= 128 {
                    errors.append("\(prefix) Event \(idx) keyCode \(event.keyCode) >= 128")
                    continue
                }
                guard let strokeOutput = table.lookup(keyCode: event.keyCode, modifiers: event.modifiers) else {
                    errors.append("\(prefix) Event \(idx) key \(event.keyCode) modifiers \(event.modifiers) missing in table")
                    continue
                }
                if let expectedOutput = strokeOutput.output {
                    if event.rendered != expectedOutput {
                        errors.append("\(prefix) Event \(idx) rendered '\(event.rendered)' does not match table output '\(expectedOutput)' for key \(event.keyCode) modifiers \(event.modifiers)")
                    }
                } else {
                    errors.append("\(prefix) Event \(idx) key \(event.keyCode) modifiers \(event.modifiers) is rejected by table: \(strokeOutput.rejection ?? "unknown") but event rendered '\(event.rendered)'")
                }
            }
        }

        for (idx, trial) in devTrials.enumerated() {
            devGroups.insert(trial.groupID)
            validateTrial(trial, expectedSplit: "development", file: "development.jsonl", lineNum: idx + 1)
        }

        for (idx, trial) in holdoutTrials.enumerated() {
            holdoutGroups.insert(trial.groupID)
            validateTrial(trial, expectedSplit: "holdout", file: "holdout.jsonl", lineNum: idx + 1)
        }

        let groupOverlap = devGroups.intersection(holdoutGroups)
        if !groupOverlap.isEmpty {
            errors.append("Leaking groups between development and holdout: \(groupOverlap.sorted())")
        }

        for entries in labelsByInput.values where entries.count > 1 {
            let ids = entries.map(\.id).joined(separator: ", ")
            if Set(entries.map(\.label)).count > 1 {
                warnings.append("Contradictory labels for identical input: \(entries.map { "\($0.id)=\($0.label)" }.joined(separator: ", "))")
            }
            if Set(entries.map(\.split)).count > 1 {
                warnings.append("Identical typed input in both splits: \(ids)")
            }
        }
        for (text, entries) in splitsByBaseText where Set(entries.map(\.split)).count > 1 {
            warnings.append("Base text '\(text)' in both splits: \(entries.map(\.id).joined(separator: ", "))")
        }

        let totalTrials = devTrials.count + holdoutTrials.count
        return ValidationResult(
            passed: errors.isEmpty,
            trialsCount: totalTrials,
            splitsCount: 2,
            errors: errors,
            warnings: warnings.sorted()
        )
    }

    /// Every file listed in `manifest.json` must exist with its recorded SHA-256. Paths are
    /// relative to the `Benchmarks` directory that holds `layout-corpus/<version>`.
    static func verifyManifest(corpusDirectory: URL) -> [String] {
        let manifestURL = corpusDirectory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return ["Missing manifest.json at \(manifestURL.path)"]
        }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return ["Unreadable manifest.json at \(manifestURL.path)"]
        }
        let root = corpusDirectory.deletingLastPathComponent().deletingLastPathComponent()
        var errors: [String] = []
        for (path, checksum) in manifest.files.sorted(by: { $0.key < $1.key }) {
            guard let actual = try? ManifestGenerator.sha256(for: root.appendingPathComponent(path)) else {
                errors.append("Manifest lists missing file \(path)")
                continue
            }
            if actual != checksum.sha256 {
                errors.append("Manifest hash mismatch for \(path): recorded \(checksum.sha256.prefix(12)), actual \(actual.prefix(12))")
            }
        }
        return errors
    }

    private static func loadJSONL(from url: URL) throws -> [Trial] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var trials: [Trial] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            let trial = try decoder.decode(Trial.self, from: data)
            trials.append(trial)
        }
        return trials
    }
}

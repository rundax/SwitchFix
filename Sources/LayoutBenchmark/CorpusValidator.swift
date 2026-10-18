import Foundation

public struct ValidationResult: Sendable {
    public let passed: Bool
    public let trialsCount: Int
    public let splitsCount: Int
    public let errors: [String]

    public init(passed: Bool, trialsCount: Int, splitsCount: Int, errors: [String]) {
        self.passed = passed
        self.trialsCount = trialsCount
        self.splitsCount = splitsCount
        self.errors = errors
    }
}

public enum CorpusValidator {
    public static func validate(corpusDirectory: URL, tablesDirectory: URL) throws -> ValidationResult {
        var errors: [String] = []
        var loadedTables: [String: LayoutTable] = [:]

        func getTable(sourceID: String, keyboardType: UInt32) -> LayoutTable? {
            let key = "\(sourceID)@\(keyboardType)"
            if let existing = loadedTables[key] { return existing }
            let tableURL = tablesDirectory.appendingPathComponent("\(key).json")
            if let table = try? LayoutTable.load(from: tableURL) {
                loadedTables[key] = table
                return table
            }
            // Fallback: try keyboardType 91 or 37
            for altType in [91, 37] as [UInt32] where altType != keyboardType {
                let altURL = tablesDirectory.appendingPathComponent("\(sourceID)@\(altType).json")
                if let table = try? LayoutTable.load(from: altURL) {
                    loadedTables[key] = table
                    return table
                }
            }
            return nil
        }

        let devURL = corpusDirectory.appendingPathComponent("development.jsonl")
        let holdoutURL = corpusDirectory.appendingPathComponent("holdout.jsonl")

        guard FileManager.default.fileExists(atPath: devURL.path) else {
            return ValidationResult(passed: false, trialsCount: 0, splitsCount: 0, errors: ["Missing development.jsonl at \(devURL.path)"])
        }
        guard FileManager.default.fileExists(atPath: holdoutURL.path) else {
            return ValidationResult(passed: false, trialsCount: 0, splitsCount: 0, errors: ["Missing holdout.jsonl at \(holdoutURL.path)"])
        }

        let devTrials = try loadJSONL(from: devURL)
        let holdoutTrials = try loadJSONL(from: holdoutURL)

        var seenIDs: Set<String> = []
        var devGroups: Set<String> = []
        var holdoutGroups: Set<String> = []

        func validateTrial(_ trial: Trial, expectedSplit: String, file: String, lineNum: Int) {
            let prefix = "[\(file):\(lineNum) id=\(trial.id)]"

            if seenIDs.contains(trial.id) {
                errors.append("\(prefix) Duplicate trial ID: \(trial.id)")
            }
            seenIDs.insert(trial.id)

            if trial.split != expectedSplit {
                errors.append("\(prefix) Trial split '\(trial.split)' does not match expected file split '\(expectedSplit)'")
            }

            if trial.provenance.review != "pending-human" {
                errors.append("\(prefix) Provenance review must be 'pending-human', got '\(trial.provenance.review)'")
            }

            let validLabels = ["repair", "preserve", "abstain"]
            if !validLabels.contains(trial.label) {
                errors.append("\(prefix) Invalid label: \(trial.label)")
            }

            let typedText = trial.events.map { $0.rendered }.joined()

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

            // Validate checkpoints
            for cp in trial.expected.checkpoints {
                if cp.afterEvent > trial.events.count || cp.afterEvent < 0 {
                    errors.append("\(prefix) Checkpoint afterEvent \(cp.afterEvent) out of range 0...\(trial.events.count)")
                }
            }

            // Check layout table for initial source
            let kbdType = trial.initial.keyboardType ?? 91
            guard let table = getTable(sourceID: trial.initial.sourceID, keyboardType: kbdType) else {
                errors.append("\(prefix) Missing layout table for \(trial.initial.sourceID)@\(kbdType)")
                return
            }

            // Validate event rendering against table
            for (idx, event) in trial.events.enumerated() {
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

        // Check that dev and holdout groups are completely disjoint
        let groupOverlap = devGroups.intersection(holdoutGroups)
        if !groupOverlap.isEmpty {
            errors.append("Leaking groups between development and holdout: \(groupOverlap.sorted())")
        }

        let totalTrials = devTrials.count + holdoutTrials.count
        return ValidationResult(
            passed: errors.isEmpty,
            trialsCount: totalTrials,
            splitsCount: 2,
            errors: errors
        )
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

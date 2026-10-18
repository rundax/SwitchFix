import Foundation

public struct SeedItemDefinition {
    public let groupID: String
    public let category: String
    public let label: String
    public let sourceLayout: String // "en" (ABC) or "uk" (Ukrainian)
    public let targetLayout: String // "en" (ABC) or "uk" (Ukrainian)
    public let intendedText: String
    public let isRepair: Bool
}

public enum SeedCorpusGenerator {
    public static func generateTrial(
        id: String,
        item: SeedItemDefinition,
        split: String,
        abcTable: LayoutTable,
        ukTable: LayoutTable
    ) throws -> Trial {
        let initialSourceID = item.sourceLayout == "en" ? "com.apple.keylayout.ABC" : "com.apple.keylayout.Ukrainian"
        let initialLanguage = item.sourceLayout == "en" ? "en" : "uk"

        // Layout used by physical fingers to press keys:
        // If repair, fingers typed assuming target layout, but active layout was sourceLayout.
        // If preserve or abstain, fingers typed assuming source layout, and active was sourceLayout.
        let physicalLayout = item.isRepair ? item.targetLayout : item.sourceLayout
        let physicalTable = physicalLayout == "en" ? abcTable : ukTable
        let activeTable = item.sourceLayout == "en" ? abcTable : ukTable

        var events: [TrialEvent] = []
        var typedText = ""

        // For each character in intendedText (which is what fingers intended to type)
        for char in item.intendedText {
            guard let (keyCode, modifiers) = findKey(for: char, in: physicalTable) else {
                throw NSError(domain: "SeedCorpusGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "No key found for character '\(char)' in \(physicalLayout) table"])
            }
            guard let stroke = activeTable.lookup(keyCode: keyCode, modifiers: modifiers),
                  let rendered = stroke.output else {
                throw NSError(domain: "SeedCorpusGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Active table \(item.sourceLayout) rejected stroke for key \(keyCode) mod \(modifiers)"])
            }
            let isBoundary = (char == " " || char == "\n" || char == "\t")
            let event = TrialEvent(
                type: isBoundary ? "boundary" : "key",
                keyCode: keyCode,
                modifiers: modifiers,
                rendered: rendered
            )
            events.append(event)
            typedText.append(rendered)
        }

        let expectedText: String
        let expectedSourceID: String
        let expectedLanguage: String
        let allowedActions: [String]

        if item.isRepair {
            expectedText = item.intendedText
            expectedSourceID = item.targetLayout == "en" ? "com.apple.keylayout.ABC" : "com.apple.keylayout.Ukrainian"
            expectedLanguage = item.targetLayout == "en" ? "en" : "uk"
            allowedActions = ["replaceSuffix", "switchSource"]
        } else {
            expectedText = typedText
            expectedSourceID = initialSourceID
            expectedLanguage = initialLanguage
            allowedActions = []
        }

        let checkpoints = [
            Checkpoint(afterEvent: events.count, text: expectedText, language: expectedLanguage)
        ]

        let expected = ExpectedOutcome(
            text: expectedText,
            language: expectedLanguage,
            sourceID: expectedSourceID,
            allowedAutomaticActions: allowedActions,
            checkpoints: checkpoints
        )

        return Trial(
            schemaVersion: 1,
            id: id,
            groupID: item.groupID,
            split: split,
            languages: ["en", "uk"],
            category: item.category,
            label: item.label,
            provenance: Provenance(kind: "synthetic", generator: "manual-v1", seed: 0, review: "pending-human"),
            initial: InitialState(
                sourceID: initialSourceID,
                language: initialLanguage,
                text: "",
                caretUTF16: 0,
                preferredCyrillic: "uk",
                keyboardType: 91
            ),
            events: events,
            expected: expected
        )
    }

    private static func findKey(for char: Character, in table: LayoutTable) -> (UInt16, [String])? {
        let s = String(char)
        var candidates: [(UInt16, [String], Int)] = []

        for (kStr, outputs) in table.keyOutputs {
            guard let kc = UInt16(kStr), kc < 65 else { continue }
            if outputs.unmodified.output == s {
                candidates.append((kc, [], 0))
            } else if outputs.shift.output == s {
                candidates.append((kc, ["shift"], 1))
            }
        }

        candidates.sort { $0.2 < $1.2 }
        return candidates.first.map { ($0.0, $0.1) }
    }
}

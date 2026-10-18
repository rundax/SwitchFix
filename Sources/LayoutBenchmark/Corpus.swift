import Foundation

public struct StrokeOutput: Codable, Equatable, Sendable {
    public let output: String?
    public let rejection: String?

    public init(output: String?, rejection: String? = nil) {
        self.output = output
        self.rejection = rejection
    }

    public var isValid: Bool {
        return output != nil && rejection == nil
    }
}

public struct KeyCodeOutputs: Codable, Equatable, Sendable {
    public let keyCode: UInt16
    public let unmodified: StrokeOutput
    public let shift: StrokeOutput
    public let caps: StrokeOutput
    public let shiftCaps: StrokeOutput
    public let option: StrokeOutput
    public let shiftOption: StrokeOutput
    public let capsOption: StrokeOutput
    public let shiftCapsOption: StrokeOutput

    public init(
        keyCode: UInt16,
        unmodified: StrokeOutput,
        shift: StrokeOutput,
        caps: StrokeOutput,
        shiftCaps: StrokeOutput,
        option: StrokeOutput,
        shiftOption: StrokeOutput,
        capsOption: StrokeOutput,
        shiftCapsOption: StrokeOutput
    ) {
        self.keyCode = keyCode
        self.unmodified = unmodified
        self.shift = shift
        self.caps = caps
        self.shiftCaps = shiftCaps
        self.option = option
        self.shiftOption = shiftOption
        self.capsOption = capsOption
        self.shiftCapsOption = shiftCapsOption
    }

    public func output(for modifiers: [String]) -> StrokeOutput {
        let hasShift = modifiers.contains("shift")
        let hasCaps = modifiers.contains("caps")
        let hasOption = modifiers.contains("option")

        switch (hasShift, hasCaps, hasOption) {
        case (false, false, false): return unmodified
        case (true, false, false): return shift
        case (false, true, false): return caps
        case (true, true, false): return shiftCaps
        case (false, false, true): return option
        case (true, false, true): return shiftOption
        case (false, true, true): return capsOption
        case (true, true, true): return shiftCapsOption
        }
    }
}

public struct LayoutTable: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sourceID: String
    public let keyboardType: UInt32
    public let osVersion: String
    public let osBuild: String
    public let keyOutputs: [String: KeyCodeOutputs]

    public init(
        schemaVersion: Int = 1,
        sourceID: String,
        keyboardType: UInt32,
        osVersion: String,
        osBuild: String,
        keyOutputs: [String: KeyCodeOutputs]
    ) {
        self.schemaVersion = schemaVersion
        self.sourceID = sourceID
        self.keyboardType = keyboardType
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.keyOutputs = keyOutputs
    }

    public func lookup(keyCode: UInt16, modifiers: [String]) -> StrokeOutput? {
        guard let entry = keyOutputs[String(keyCode)] else { return nil }
        return entry.output(for: modifiers)
    }

    public static func load(from url: URL) throws -> LayoutTable {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(LayoutTable.self, from: data)
    }
}

public struct Provenance: Codable, Equatable, Sendable {
    public let kind: String
    public let generator: String
    public let seed: Int
    public let review: String

    public init(kind: String = "synthetic", generator: String = "manual-v1", seed: Int = 0, review: String = "pending-human") {
        self.kind = kind
        self.generator = generator
        self.seed = seed
        self.review = review
    }
}

public struct InitialState: Codable, Equatable, Sendable {
    public let sourceID: String
    public let language: String
    public let text: String
    public let caretUTF16: Int
    public let preferredCyrillic: String?
    public let keyboardType: UInt32?

    public init(
        sourceID: String,
        language: String,
        text: String = "",
        caretUTF16: Int = 0,
        preferredCyrillic: String? = nil,
        keyboardType: UInt32? = nil
    ) {
        self.sourceID = sourceID
        self.language = language
        self.text = text
        self.caretUTF16 = caretUTF16
        self.preferredCyrillic = preferredCyrillic
        self.keyboardType = keyboardType
    }
}

public struct TrialEvent: Codable, Equatable, Sendable {
    public let type: String
    public let keyCode: UInt16
    public let modifiers: [String]
    public let rendered: String

    public init(type: String, keyCode: UInt16, modifiers: [String] = [], rendered: String) {
        self.type = type
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.rendered = rendered
    }
}

public struct Checkpoint: Codable, Equatable, Sendable {
    public let afterEvent: Int
    public let text: String
    public let language: String

    public init(afterEvent: Int, text: String, language: String) {
        self.afterEvent = afterEvent
        self.text = text
        self.language = language
    }
}

public struct ExpectedOutcome: Codable, Equatable, Sendable {
    public let text: String
    public let language: String
    public let sourceID: String
    public let allowedAutomaticActions: [String]
    public let checkpoints: [Checkpoint]

    public init(
        text: String,
        language: String,
        sourceID: String,
        allowedAutomaticActions: [String] = [],
        checkpoints: [Checkpoint] = []
    ) {
        self.text = text
        self.language = language
        self.sourceID = sourceID
        self.allowedAutomaticActions = allowedAutomaticActions
        self.checkpoints = checkpoints
    }
}

public struct Trial: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let groupID: String
    public let split: String
    public let languages: [String]
    public let category: String
    public let label: String
    public let provenance: Provenance
    public let initial: InitialState
    public let events: [TrialEvent]
    public let expected: ExpectedOutcome

    public init(
        schemaVersion: Int = 1,
        id: String,
        groupID: String,
        split: String,
        languages: [String],
        category: String,
        label: String,
        provenance: Provenance = Provenance(),
        initial: InitialState,
        events: [TrialEvent],
        expected: ExpectedOutcome
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.groupID = groupID
        self.split = split
        self.languages = languages
        self.category = category
        self.label = label
        self.provenance = provenance
        self.initial = initial
        self.events = events
        self.expected = expected
    }
}

public struct FileChecksum: Codable, Equatable, Sendable {
    public let sha256: String
    public let trialsCount: Int?

    public init(sha256: String, trialsCount: Int? = nil) {
        self.sha256 = sha256
        self.trialsCount = trialsCount
    }
}

public struct SplitSummary: Codable, Equatable, Sendable {
    public let repair: Int
    public let preserve: Int
    public let abstain: Int
    public let total: Int

    public init(repair: Int, preserve: Int, abstain: Int, total: Int) {
        self.repair = repair
        self.preserve = preserve
        self.abstain = abstain
        self.total = total
    }
}

public struct Manifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let corpusVersion: String
    public let tablesVersion: String
    public let created: String
    public let osVersion: String
    public let osBuild: String
    public let keyboardType: UInt32
    public let sourceCommit: String
    public let files: [String: FileChecksum]
    public let splits: [String: SplitSummary]

    public init(
        schemaVersion: Int = 1,
        corpusVersion: String = "v1",
        tablesVersion: String = "v1",
        created: String,
        osVersion: String,
        osBuild: String,
        keyboardType: UInt32,
        sourceCommit: String,
        files: [String: FileChecksum],
        splits: [String: SplitSummary]
    ) {
        self.schemaVersion = schemaVersion
        self.corpusVersion = corpusVersion
        self.tablesVersion = tablesVersion
        self.created = created
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.keyboardType = keyboardType
        self.sourceCommit = sourceCommit
        self.files = files
        self.splits = splits
    }
}

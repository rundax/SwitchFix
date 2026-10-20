import Foundation
import Core

/// Corpus language codes ("en", "uk", "ru") for detector layouts.
public func languageCode(for layout: Layout) -> String {
    switch layout {
    case .english: return "en"
    case .ukrainian: return "uk"
    case .russian: return "ru"
    }
}

public func layout(forLanguageCode code: String) -> Layout? {
    switch code {
    case "en": return .english
    case "uk": return .ukrainian
    case "ru": return .russian
    default: return nil
    }
}

/// What the target application shows during replay. The caret is always at the end; trials
/// that start elsewhere are reported unsupported rather than approximated.
public struct VirtualEditor: Equatable, Sendable {
    public struct ReplacementOutcome: Equatable, Sendable {
        /// The screen ended with the detector's original span plus boundary.
        public let suffixMatched: Bool
        /// More deletions were requested than there were characters.
        public let underflow: Bool
    }

    public private(set) var text: String

    public init(text: String = "") {
        self.text = text
    }

    public mutating func type(_ value: String) {
        text.append(value)
    }

    public mutating func deleteBackward() {
        if !text.isEmpty {
            text.removeLast()
        }
    }

    /// Mirrors `TextCorrector`: `deleteCount` backspaces, then the replacement, whatever the
    /// screen shows. A mismatch is reported, never hidden, so a damaging edit stays visible.
    public mutating func replaceSuffix(deleteCount: Int, with replacement: String, expectedSuffix: String) -> ReplacementOutcome {
        let matched = text.hasSuffix(expectedSuffix)
        let available = text.count
        text.removeLast(min(deleteCount, available))
        text.append(replacement)
        return ReplacementOutcome(suffixMatched: matched, underflow: deleteCount > available)
    }
}

/// Outcome of rendering one physical key through a source's frozen table.
public enum RenderOutcome: Equatable, Sendable {
    case rendered(String)
    case unavailable(status: String, reason: String)
}

/// Renders physical keys after an automatic switch through the new source's own table.
public struct KeyRenderer: Sendable {
    public let tables: [String: LayoutTable]

    public init(tables: [String: LayoutTable]) {
        self.tables = tables
    }

    public func render(_ event: TrialEvent, sourceID: String, keyboardType: UInt32, initialSourceID: String) -> RenderOutcome {
        // `rendered` is the validated oracle for the initial source.
        if sourceID == initialSourceID {
            return .rendered(event.rendered)
        }
        guard let table = tables["\(sourceID)@\(keyboardType)"] else {
            return .unavailable(status: "error", reason: "missing_layout_table")
        }
        guard let stroke = table.lookup(keyCode: event.keyCode, modifiers: event.modifiers) else {
            return .unavailable(status: "error", reason: "missing_key")
        }
        guard let output = stroke.output else {
            return .unavailable(status: "unsupported", reason: "rejected_stroke_\(stroke.rejection ?? "unknown")")
        }
        if event.type == "boundary" && output != event.rendered {
            return .unavailable(status: "unsupported", reason: "boundary_changed_after_switch")
        }
        return .rendered(output)
    }
}

/// Exposes a frozen table through the same protocol the app uses for live TIS sources, so the
/// app's own `InputSourceDiscoveryEngine` classifies it. Tables do not record TIS languages;
/// classification falls back to the source ID and key probes, as for a source without them.
struct TableInputSourceProvider: InputSourcePropertyProviding {
    let table: LayoutTable

    var id: String { table.sourceID }
    var localizedName: String { table.sourceID.components(separatedBy: ".").last ?? table.sourceID }
    var inputSourceType: String? { "TISTypeKeyboardLayout" }
    var languages: [String]? { nil }

    func translatedCharacter(keyCode: UInt16, modifierKeyState: UInt32) -> Character? {
        let modifiers: [String]
        switch modifierKeyState {
        case 0x00: modifiers = []
        case 0x02: modifiers = ["shift"]
        case 0x04: modifiers = ["caps"]
        case 0x06: modifiers = ["shift", "caps"]
        case 0x08: modifiers = ["option"]
        case 0x0A: modifiers = ["shift", "option"]
        case 0x0C: modifiers = ["caps", "option"]
        case 0x0E: modifiers = ["shift", "caps", "option"]
        default: return nil
        }
        guard let output = table.lookup(keyCode: keyCode, modifiers: modifiers)?.output,
              output.count == 1 else { return nil }
        return output.first
    }
}

/// The installed sources for one trial, taken only from the trial and the frozen tables.
public struct TrialSourceEnvironment: Sendable {
    public static let defaultSourceIDs: [Layout: String] = [
        .english: "com.apple.keylayout.ABC",
        .ukrainian: "com.apple.keylayout.Ukrainian"
    ]

    public let keyboardType: UInt32
    public let descriptors: [String: DiscoveredInputSourceDescriptor]
    public let preferredSourceIDs: [Layout: String]
    public let allowedLayouts: Set<Layout>
    public let preferredCyrillicLayout: Layout?

    public static func make(
        trial: Trial,
        tables: [String: LayoutTable],
        allowedLayouts: Set<Layout>
    ) -> Result<TrialSourceEnvironment, AdapterFailure> {
        let keyboardType = trial.initial.keyboardType ?? 91
        var preferred: [Layout: String] = [:]
        for target in allowedLayouts {
            let code = languageCode(for: target)
            if trial.initial.language == code {
                preferred[target] = trial.initial.sourceID
            } else if trial.expected.language == code {
                preferred[target] = trial.expected.sourceID
            } else {
                preferred[target] = defaultSourceIDs[target]
            }
        }

        var descriptors: [String: DiscoveredInputSourceDescriptor] = [:]
        for sourceID in Set(preferred.values).union([trial.initial.sourceID]) {
            guard let table = tables["\(sourceID)@\(keyboardType)"] else {
                return .failure(AdapterFailure(status: "error", reason: "missing_layout_table"))
            }
            guard let descriptor = InputSourceDiscoveryEngine.classify(provider: TableInputSourceProvider(table: table)) else {
                return .failure(AdapterFailure(status: "unsupported", reason: "unclassified_source"))
            }
            descriptors[sourceID] = descriptor
        }

        return .success(TrialSourceEnvironment(
            keyboardType: keyboardType,
            descriptors: descriptors,
            preferredSourceIDs: preferred,
            allowedLayouts: allowedLayouts,
            preferredCyrillicLayout: trial.initial.preferredCyrillic.flatMap(layout(forLanguageCode:))
        ))
    }

    /// Mirrors `AppDelegate.updateDetectionConfiguration` for the given active source.
    public func detectionConfiguration(currentSourceID: String, currentLayout: Layout) -> DetectionConfiguration {
        let preferredVariant = preferredSourceIDs[.ukrainian].flatMap { descriptors[$0]?.ukrainianVariant } ?? .standard
        let currentVariant = currentLayout == .ukrainian
            ? descriptors[currentSourceID]?.ukrainianVariant ?? preferredVariant
            : preferredVariant
        return DetectionConfiguration(
            allowedLayouts: allowedLayouts,
            preferredCyrillicLayout: currentLayout.isCyrillic ? currentLayout : preferredCyrillicLayout,
            activeSourceSupportedLayouts: descriptors[currentSourceID]?.supportedLayouts ?? [currentLayout],
            ukrainianFromVariant: currentVariant,
            ukrainianToVariant: preferredVariant
        )
    }
}

public struct AdapterFailure: Error, Equatable, Sendable {
    public let status: String
    public let reason: String
}

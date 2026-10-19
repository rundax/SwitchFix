import Foundation
import Core
import Dictionary
import Utils

public struct EmittedAction: Codable, Equatable, Sendable {
    public let type: String
    public let eventIndex: Int
    public let fromText: String?
    public let toText: String?
    public let targetSource: String?
    public let targetLayout: String?

    public init(
        type: String,
        eventIndex: Int,
        fromText: String? = nil,
        toText: String? = nil,
        targetSource: String? = nil,
        targetLayout: String? = nil
    ) {
        self.type = type
        self.eventIndex = eventIndex
        self.fromText = fromText
        self.toText = toText
        self.targetSource = targetSource
        self.targetLayout = targetLayout
    }
}

public struct ObservedCheckpoint: Codable, Equatable, Sendable {
    public let afterEvent: Int
    public let text: String
    public let language: String
    public let sourceID: String

    public init(afterEvent: Int, text: String, language: String, sourceID: String) {
        self.afterEvent = afterEvent
        self.text = text
        self.language = language
        self.sourceID = sourceID
    }
}

public struct TrialResult: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let adapter: String
    public let adapterVersion: String
    public let trialID: String
    public let status: String
    public let finalText: String
    public let finalSourceID: String
    public let actions: [EmittedAction]
    public let checkpoints: [ObservedCheckpoint]
    public let reasonCodes: [String]
    public let durationMs: Double
    public let errorMessage: String?

    public init(
        protocolVersion: Int = 1,
        adapter: String = "switchfix",
        adapterVersion: String = "1.0",
        trialID: String,
        status: String = "ok",
        finalText: String,
        finalSourceID: String,
        actions: [EmittedAction] = [],
        checkpoints: [ObservedCheckpoint] = [],
        reasonCodes: [String] = [],
        durationMs: Double = 0,
        errorMessage: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.adapter = adapter
        self.adapterVersion = adapterVersion
        self.trialID = trialID
        self.status = status
        self.finalText = finalText
        self.finalSourceID = finalSourceID
        self.actions = actions
        self.checkpoints = checkpoints
        self.reasonCodes = reasonCodes
        self.durationMs = durationMs
        self.errorMessage = errorMessage
    }
}

public enum BenchmarkLayer: String, Sendable {
    case decision
    case replay
    case app
}

public final class SwitchFixAdapter: @unchecked Sendable {
    /// Profile `boundary-layout-only`: English and Ukrainian only.
    public static let profileLayouts: Set<Layout> = [.english, .ukrainian]

    private let tables: [String: LayoutTable]
    private let renderer: KeyRenderer
    private var isReady = false

    public init(tables: [String: LayoutTable]) {
        self.tables = tables
        self.renderer = KeyRenderer(tables: tables)
    }

    public func prewarm() -> Bool {
        DictionaryLoader.shared.enableTextFallbackForTesting()
        let enLoaded = DictionaryLoader.shared.prewarm(language: .english)
        let ukLoaded = DictionaryLoader.shared.prewarm(language: .ukrainian)
        isReady = enLoaded && ukLoaded
        return isReady
    }

    /// Replays a trial on the real `InputStateMachine` and `LayoutDetector`.
    ///
    /// `replay` feeds automatic source switches back into rendering and context; `decision`
    /// records the same proposals without feedback, so later keys keep the initial source.
    public func executeTrial(trial: Trial, layer: BenchmarkLayer = .replay) -> TrialResult {
        func unavailable(_ failure: AdapterFailure, text: String = "", sourceID: String = "", actions: [EmittedAction] = [], checkpoints: [ObservedCheckpoint] = [], reasons: Set<String> = []) -> TrialResult {
            TrialResult(
                trialID: trial.id,
                status: failure.status,
                finalText: text,
                finalSourceID: sourceID,
                actions: actions,
                checkpoints: checkpoints,
                reasonCodes: reasons.union([failure.reason]).sorted(),
                errorMessage: failure.reason
            )
        }

        guard isReady else {
            return unavailable(AdapterFailure(status: "error", reason: "dictionaries_not_ready"))
        }
        guard let initialLayout = layout(forLanguageCode: trial.initial.language),
              SwitchFixAdapter.profileLayouts.contains(initialLayout) else {
            return unavailable(AdapterFailure(status: "unsupported", reason: "language_outside_profile"))
        }
        guard trial.initial.caretUTF16 == trial.initial.text.utf16.count else {
            return unavailable(AdapterFailure(status: "unsupported", reason: "caret_not_at_end"))
        }

        let environment: TrialSourceEnvironment
        switch TrialSourceEnvironment.make(trial: trial, tables: tables, allowedLayouts: SwitchFixAdapter.profileLayouts) {
        case .success(let value): environment = value
        case .failure(let failure): return unavailable(failure)
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        var activeLayout = initialLayout
        var activeSourceID = trial.initial.sourceID
        var editor = VirtualEditor(text: trial.initial.text)

        let detector = LayoutDetector()
        detector.preferredSourceIDProvider = { environment.preferredSourceIDs[$0] }
        var config = environment.detectionConfiguration(currentSourceID: activeSourceID, currentLayout: activeLayout)

        var contextSnapshot = InputContextSnapshot(
            epoch: 1,
            frontmostPID: 100,
            appAllowed: true,
            layout: activeLayout,
            inputSourceID: activeSourceID,
            secureFocus: .notSecure
        )
        var stateMachine = InputStateMachine(
            context: contextSnapshot,
            preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic)
        )

        var actions: [EmittedAction] = []
        var observedCheckpoints = [ObservedCheckpoint(afterEvent: 0, text: editor.text, language: languageCode(for: activeLayout), sourceID: activeSourceID)]
        var reasons: Set<String> = []
        var sequence: UInt64 = 0

        for (idx, event) in trial.events.enumerated() {
            sequence += 1

            let kind: CapturedInput.Kind
            switch event.type {
            case "key", "boundary":
                let rendered: String
                switch renderer.render(event, sourceID: activeSourceID, keyboardType: environment.keyboardType, initialSourceID: trial.initial.sourceID) {
                case .rendered(let value):
                    rendered = value
                case .unavailable(let status, let reason):
                    return unavailable(AdapterFailure(status: status, reason: reason), text: editor.text, sourceID: activeSourceID, actions: actions, checkpoints: observedCheckpoints, reasons: reasons)
                }
                // The keystroke reaches the application before SwitchFix sees the boundary.
                editor.type(rendered)
                kind = event.type == "boundary" ? .boundary(rendered) : KeyboardMonitor.capturedKind(forText: rendered)
            case "delete":
                editor.deleteBackward()
                kind = .delete
            default:
                return unavailable(AdapterFailure(status: "unsupported", reason: "event_type_\(event.type)"), text: editor.text, sourceID: activeSourceID, actions: actions, checkpoints: observedCheckpoints, reasons: reasons)
            }

            var flags: UInt64 = 0
            if event.modifiers.contains("shift") { flags |= 0x020000 }
            if event.modifiers.contains("caps") { flags |= 0x010000 }
            if event.modifiers.contains("option") { flags |= 0x080000 }

            let input = CapturedInput(
                sequence: sequence,
                timestamp: sequence,
                kind: kind,
                keyCode: event.keyCode,
                flagsRawValue: flags,
                isAutorepeat: false,
                sourcePID: 100,
                sourceUserData: 0,
                context: contextSnapshot,
                editGeneration: 1
            )

            for command in stateMachine.consume(input) {
                switch command {
                case .append, .deleteLast, .untrackedWordHeld:
                    break
                case .invalidate, .nativeUndo:
                    detector.reset()
                case .requestManualCorrection, .requestRevert:
                    reasons.insert("manual_command_ignored")
                case .flush(let word, let boundary, let seq, let ctx):
                    let request = assembleDetectionRequest(
                        trigger: .automaticBoundary,
                        word: word,
                        boundary: boundary,
                        sequence: seq,
                        editGeneration: 1,
                        correctionEpoch: 0,
                        context: ctx,
                        run: stateMachine.run
                    )
                    guard let detection = evaluateDetection(detector: detector, request: request, configuration: config) else {
                        continue
                    }

                    let edit: CorrectionEdit
                    switch planCorrectionEdit(result: detection, boundary: boundary) {
                    case .success(let value):
                        edit = value
                    case .failure(let rejection):
                        reasons.insert("cancelled_\(rejection.rawValue)")
                        continue
                    }

                    if edit.deleteCount > 0 || !edit.replacementText.isEmpty {
                        let outcome = editor.replaceSuffix(
                            deleteCount: edit.deleteCount,
                            with: edit.replacementText,
                            expectedSuffix: detection.originalWord + boundary
                        )
                        if !outcome.suffixMatched { reasons.insert("suffix_mismatch") }
                        if outcome.underflow { reasons.insert("delete_underflow") }
                        actions.append(EmittedAction(
                            type: "replaceSuffix",
                            eventIndex: idx,
                            fromText: detection.originalWord,
                            toText: detection.convertedWord
                        ))
                    }

                    guard let target = edit.switchTarget else { continue }
                    guard let targetSource = environment.preferredSourceIDs[target] else {
                        reasons.insert("no_source_for_target")
                        continue
                    }
                    actions.append(EmittedAction(
                        type: "switchSource",
                        eventIndex: idx,
                        targetSource: targetSource,
                        targetLayout: languageCode(for: target)
                    ))
                    guard layer == .replay else { continue }

                    // Mirrors the app after its own switch: new context (focus assumed resolved
                    // before the next key), detector reset, configuration recomputed.
                    activeSourceID = targetSource
                    activeLayout = target
                    contextSnapshot = InputContextSnapshot(
                        epoch: contextSnapshot.epoch + 1,
                        frontmostPID: 100,
                        appAllowed: true,
                        layout: activeLayout,
                        inputSourceID: activeSourceID,
                        secureFocus: .notSecure
                    )
                    _ = stateMachine.updateContext(contextSnapshot)
                    detector.reset()
                    config = environment.detectionConfiguration(currentSourceID: activeSourceID, currentLayout: activeLayout)
                }
            }

            observedCheckpoints.append(ObservedCheckpoint(
                afterEvent: idx + 1,
                text: editor.text,
                language: languageCode(for: activeLayout),
                sourceID: activeSourceID
            ))
        }

        let finalSourceID: String
        if layer == .replay {
            finalSourceID = activeSourceID
        } else {
            finalSourceID = actions.last(where: { $0.type == "switchSource" })?.targetSource ?? activeSourceID
        }

        return TrialResult(
            trialID: trial.id,
            status: "ok",
            finalText: editor.text,
            finalSourceID: finalSourceID,
            actions: actions,
            checkpoints: observedCheckpoints,
            reasonCodes: reasons.sorted(),
            durationMs: Double(DispatchTime.now().uptimeNanoseconds &- startedAt) / 1_000_000.0
        )
    }
}

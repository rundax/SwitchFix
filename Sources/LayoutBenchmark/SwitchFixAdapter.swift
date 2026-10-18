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
    private let tables: [String: LayoutTable]
    private var isReady = false

    public init(tables: [String: LayoutTable]) {
        self.tables = tables
    }

    public func prewarm() -> Bool {
        DictionaryLoader.shared.enableTextFallbackForTesting()
        let enLoaded = DictionaryLoader.shared.prewarm(language: .english)
        let ukLoaded = DictionaryLoader.shared.prewarm(language: .ukrainian)
        isReady = enLoaded && ukLoaded
        return isReady
    }

    public func executeTrial(trial: Trial, layer: BenchmarkLayer = .replay) -> TrialResult {
        guard isReady else {
            return TrialResult(
                trialID: trial.id,
                status: "error",
                finalText: "",
                finalSourceID: "",
                errorMessage: "Adapter dictionaries not ready"
            )
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds

        let initialLayout: Layout = trial.initial.language == "uk" ? .ukrainian : .english
        var activeLayout = initialLayout
        var activeSourceID = trial.initial.sourceID
        var virtualText = trial.initial.text

        let detector = LayoutDetector()
        detector.preferredSourceIDProvider = { layout in
            switch layout {
            case .english: return "com.apple.keylayout.ABC"
            case .ukrainian: return "com.apple.keylayout.Ukrainian"
            case .russian: return "com.apple.keylayout.Russian"
            }
        }

        var config = DetectionConfiguration(
            allowedLayouts: [.english, .ukrainian],
            preferredCyrillicLayout: .ukrainian,
            activeSourceSupportedLayouts: [activeLayout],
            ukrainianFromVariant: .standard,
            ukrainianToVariant: .standard
        )

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
            preferences: InputPreferencesSnapshot(
                isEnabled: true,
                correctionMode: .automatic
            )
        )

        var actions: [EmittedAction] = []
        var observedCheckpoints: [ObservedCheckpoint] = []
        var sequence: UInt64 = 0

        for (idx, event) in trial.events.enumerated() {
            sequence += 1

            // If active layout switched and this is a key event in replay mode, render through the new layout's table
            var renderedChar = event.rendered
            if layer == .replay && activeSourceID != trial.initial.sourceID && event.type == "key" {
                let kbdType = trial.initial.keyboardType ?? 91
                let tableKey = "\(activeSourceID)@\(kbdType)"
                if let activeTable = tables[tableKey] ?? tables["\(activeSourceID)@91"] ?? tables["\(activeSourceID)@37"] {
                    if let stroke = activeTable.lookup(keyCode: event.keyCode, modifiers: event.modifiers),
                       let out = stroke.output {
                        renderedChar = out
                    }
                }
            }

            let kind: CapturedInput.Kind
            switch event.type {
            case "boundary":
                kind = .boundary(renderedChar)
            case "delete":
                kind = .delete
            case "navigation":
                kind = .navigation
            default:
                kind = .character(renderedChar)
            }

            let input = CapturedInput(
                sequence: sequence,
                timestamp: sequence,
                kind: kind,
                keyCode: event.keyCode,
                flagsRawValue: event.modifiers.contains("shift") ? 0x020000 : 0,
                isAutorepeat: false,
                sourcePID: 100,
                sourceUserData: 0,
                context: contextSnapshot,
                editGeneration: 1
            )

            let commands = stateMachine.consume(input)

            for command in commands {
                switch command {
                case .append(let text):
                    if layer == .replay {
                        virtualText.append(text)
                    }
                case .deleteLast:
                    if layer == .replay && !virtualText.isEmpty {
                        virtualText.removeLast()
                    }
                case .invalidate:
                    detector.reset()
                case .untrackedWordHeld:
                    break
                case .flush(let word, let boundary, let seq, let ctx):
                    if layer == .replay {
                        virtualText.append(boundary)
                    }

                    let req = assembleDetectionRequest(
                        word: word,
                        boundary: boundary,
                        sequence: seq,
                        editGeneration: 1,
                        correctionEpoch: 0,
                        context: ctx,
                        run: stateMachine.run
                    )

                    let detection = evaluateDetection(
                        detector: detector,
                        request: req,
                        configuration: config
                    )

                    if let res = detection {
                        // 1. Text replacement
                        let targetSuffix = res.originalWord + boundary
                        if layer == .replay {
                            if virtualText.hasSuffix(targetSuffix) {
                                let prefix = virtualText.dropLast(targetSuffix.count)
                                virtualText = String(prefix) + res.convertedWord + boundary
                                actions.append(EmittedAction(
                                    type: "replaceSuffix",
                                    eventIndex: idx,
                                    fromText: res.originalWord,
                                    toText: res.convertedWord
                                ))
                            }
                        } else {
                            actions.append(EmittedAction(
                                type: "replaceSuffix",
                                eventIndex: idx,
                                fromText: res.originalWord,
                                toText: res.convertedWord
                            ))
                        }

                        // 2. Source switch
                        if res.shouldSwitchLayout {
                            let targetSource = (detector.preferredSourceIDProvider?(res.targetLayout) ?? nil) ?? "com.apple.keylayout.Ukrainian"
                            activeSourceID = targetSource
                            activeLayout = res.targetLayout
                            contextSnapshot = InputContextSnapshot(
                                epoch: contextSnapshot.epoch + 1,
                                frontmostPID: 100,
                                appAllowed: true,
                                layout: activeLayout,
                                inputSourceID: activeSourceID,
                                secureFocus: .notSecure
                            )
                            _ = stateMachine.updateContext(contextSnapshot)
                            config.activeSourceSupportedLayouts = [activeLayout]
                            actions.append(EmittedAction(
                                type: "switchSource",
                                eventIndex: idx,
                                targetSource: targetSource,
                                targetLayout: res.targetLayout.rawValue
                            ))
                        }
                    }
                case .requestManualCorrection, .requestRevert, .nativeUndo:
                    break
                }
            }

            observedCheckpoints.append(ObservedCheckpoint(
                afterEvent: idx + 1,
                text: virtualText,
                language: activeLayout.rawValue,
                sourceID: activeSourceID
            ))
        }

        let duration = Double(DispatchTime.now().uptimeNanoseconds &- startedAt) / 1_000_000.0

        let finalText: String
        let finalSource: String

        if layer == .replay {
            finalText = virtualText
            finalSource = activeSourceID
        } else {
            // In decision mode, synthesize final state based on proposed decisions
            if let replaceAction = actions.first(where: { $0.type == "replaceSuffix" }),
               let conv = replaceAction.toText {
                finalText = conv + " "
            } else {
                finalText = trial.events.map { $0.rendered }.joined()
            }
            if let switchAction = actions.first(where: { $0.type == "switchSource" }),
               let s = switchAction.targetSource {
                finalSource = s
            } else {
                finalSource = activeSourceID
            }
        }

        return TrialResult(
            protocolVersion: 1,
            adapter: "switchfix",
            adapterVersion: "1.0",
            trialID: trial.id,
            status: "ok",
            finalText: finalText,
            finalSourceID: finalSource,
            actions: actions,
            checkpoints: observedCheckpoints,
            reasonCodes: [],
            durationMs: duration,
            errorMessage: nil
        )
    }
}

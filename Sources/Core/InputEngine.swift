import Foundation
import os

public struct DetectionRequest: Equatable {
    public let word: String
    public let boundary: String
    public let sequence: UInt64
    public let editGeneration: UInt64
    public let correctionEpoch: UInt64
    public let context: InputContextSnapshot

    public init(
        word: String,
        boundary: String,
        sequence: UInt64,
        editGeneration: UInt64,
        correctionEpoch: UInt64,
        context: InputContextSnapshot
    ) {
        self.word = word
        self.boundary = boundary
        self.sequence = sequence
        self.editGeneration = editGeneration
        self.correctionEpoch = correctionEpoch
        self.context = context
    }
}

public final class InputEngine {
    public typealias ExactDetection = (DetectionRequest) -> DetectionResult?
    public typealias CorrectionEmission = (CorrectionPlan) -> Bool
    public typealias SelectedTextRequest = (pid_t, UInt64, @escaping (String?) -> Void) -> Void

    public var onFocusMayChange: ((pid_t, UInt64) -> Void)?

    private struct DetectionConfiguration {
        var allowedLayouts = Set(Layout.allCases)
        var ukrainianFromVariant: UkrainianKeyboardVariant = .standard
        var ukrainianToVariant: UkrainianKeyboardVariant = .standard
    }

    private let inputQueue = DispatchQueue(label: "com.switchfix.input-engine", qos: .userInteractive)
    private let detectionQueue = DispatchQueue(label: "com.switchfix.detection", qos: .userInitiated)
    private let correctionQueue = DispatchQueue(label: "com.switchfix.correction", qos: .userInteractive)
    private let selectionQueue = DispatchQueue(label: "com.switchfix.selection", qos: .userInitiated)
    private let captureState: CaptureStateStore
    private var stateMachine: InputStateMachine
    private let detector: LayoutDetector
    private let corrector: TextCorrector
    private let customDetection: ExactDetection?
    private let customEmission: CorrectionEmission?
    private let selectedTextRequest: SelectedTextRequest?
    private let detectionConfiguration = OSAllocatedUnfairLock(initialState: DetectionConfiguration())
    private var correctionEpoch: UInt64
    private var latestProcessedSequence: UInt64 = 0
    private var maximumQueueDepth = 0
    private let logger = Logger(subsystem: "com.switchfix", category: "input-engine")

    public init(
        captureState: CaptureStateStore,
        initialContext: InputContextSnapshot,
        preferences: InputPreferencesSnapshot,
        detector: LayoutDetector = LayoutDetector(),
        corrector: TextCorrector = TextCorrector(),
        exactDetection: ExactDetection? = nil,
        correctionEmission: CorrectionEmission? = nil,
        selectedTextRequest: SelectedTextRequest? = nil
    ) {
        self.captureState = captureState
        self.stateMachine = InputStateMachine(context: initialContext, preferences: preferences)
        self.detector = detector
        self.corrector = corrector
        self.customDetection = exactDetection
        self.customEmission = correctionEmission
        self.selectedTextRequest = selectedTextRequest
        correctionEpoch = captureState.updateCorrectionEnabled(preferences.isEnabled)
    }

    public func enqueue(_ input: CapturedInput) {
        guard input.sourceUserData != switchFixEventMarker else { return }
        switch captureState.reserveEnqueue(for: input) {
        case .drop:
            return
        case .enqueue(let reservedInput):
            let depth = captureState.snapshot().pendingInputCount
            inputQueue.async { [weak self] in
                guard let self else { return }
                defer { self.captureState.completeEnqueue() }
                self.maximumQueueDepth = max(self.maximumQueueDepth, depth)
                self.process(reservedInput)
            }
        }
    }

    public func updateContext(_ context: InputContextSnapshot) {
        inputQueue.async { [weak self] in
            _ = self?.stateMachine.updateContext(context)
            self?.resetDetectorState()
        }
    }

    public func updatePreferences(_ preferences: InputPreferencesSnapshot) {
        let correctionEpoch = captureState.updateCorrectionEnabled(preferences.isEnabled)
        inputQueue.async { [weak self] in
            guard let self else { return }
            self.correctionEpoch = correctionEpoch
            if !self.stateMachine.updatePreferences(preferences).isEmpty {
                self.resetDetectorState()
            }
        }
    }

    public func handleGeneratedLayoutContext(_ context: InputContextSnapshot) {
        let generation = captureState.snapshot().editGeneration
        inputQueue.async { [weak self] in
            _ = self?.stateMachine.updateContext(context)
            self?.resetDetectorState()
        }
        correctionQueue.async { [weak self] in
            self?.corrector.rebaseUndoContext(context, editGeneration: generation)
        }
    }

    public func handleLayoutChange(
        from oldLayout: Layout,
        to newLayout: Layout,
        context: InputContextSnapshot,
        fromVariant: UkrainianKeyboardVariant,
        toVariant: UkrainianKeyboardVariant
    ) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            let bufferedWord = self.stateMachine.currentBuffer
            let preferences = self.stateMachine.preferences
            _ = self.stateMachine.updateContext(context)
            self.resetDetectorState()
            guard preferences.isEnabled,
                  preferences.correctionMode == .layoutSwitch,
                  context.appAllowed,
                  context.secureFocus == .notSecure,
                  oldLayout != newLayout else {
                return
            }

            let latest = self.captureState.snapshot()
            let requestCorrectionEpoch = self.correctionEpoch
            let applyBufferedCorrection = {
                guard self.latestProcessedSequence == latest.latestPhysicalSequence,
                      !bufferedWord.isEmpty,
                      bufferedWord.count <= 64 else { return }
                let converted = LayoutMapper.convert(
                    bufferedWord,
                    from: oldLayout,
                    to: newLayout,
                    ukrainianFromVariant: fromVariant,
                    ukrainianToVariant: toVariant
                )
                guard converted != bufferedWord else { return }
                let result = DetectionResult(
                    sourceLayout: oldLayout,
                    targetLayout: newLayout,
                    convertedWord: converted,
                    originalWord: bufferedWord,
                    shouldSwitchLayout: false
                )
                self.prepareCorrection(
                    result: result,
                    request: DetectionRequest(
                        word: bufferedWord,
                        boundary: "",
                        sequence: latest.latestPhysicalSequence,
                        editGeneration: latest.editGeneration,
                        correctionEpoch: requestCorrectionEpoch,
                        context: context
                    )
                )
            }

            guard let selectedTextRequest = self.selectedTextRequest else {
                applyBufferedCorrection()
                return
            }
            self.selectionQueue.async {
                selectedTextRequest(context.frontmostPID, context.epoch) { [weak self] selectedText in
                    guard let self else { return }
                    self.inputQueue.async {
                        let current = self.captureState.snapshot()
                        guard current.latestPhysicalSequence == latest.latestPhysicalSequence,
                              current.editGeneration == latest.editGeneration,
                              current.correctionEpoch == requestCorrectionEpoch,
                              current.context == context else {
                            return
                        }
                        if let selectedText, !selectedText.isEmpty {
                            guard ScriptAnalyzer.containsScript(for: oldLayout, in: selectedText) else {
                                return
                            }
                            let converted = LayoutMapper.convert(
                                selectedText,
                                from: oldLayout,
                                to: newLayout,
                                ukrainianFromVariant: fromVariant,
                                ukrainianToVariant: toVariant
                            )
                            guard converted != selectedText else { return }
                            self.corrector.performSelectionCorrection(
                                selectedText: selectedText,
                                convertedText: converted,
                                targetLayout: newLayout,
                                shouldSwitchLayout: false,
                                originalLayout: oldLayout,
                                sequence: latest.latestPhysicalSequence,
                                context: context,
                                editGeneration: latest.editGeneration,
                                correctionEpoch: requestCorrectionEpoch,
                                latestCaptureState: self.captureState.snapshot
                            )
                        } else {
                            applyBufferedCorrection()
                        }
                    }
                }
            }
        }
    }

    public func updateDetectionConfiguration(
        allowedLayouts: Set<Layout>,
        ukrainianFromVariant: UkrainianKeyboardVariant,
        ukrainianToVariant: UkrainianKeyboardVariant
    ) {
        detectionConfiguration.withLock { value in
            value.allowedLayouts = allowedLayouts
            value.ukrainianFromVariant = ukrainianFromVariant
            value.ukrainianToVariant = ukrainianToVariant
        }
    }

    public func drain(completion: @escaping () -> Void) {
        inputQueue.async { completion() }
    }

    public func inspectState(
        completion: @escaping (_ buffer: String, _ invalidUntilBoundary: Bool, _ sequence: UInt64) -> Void
    ) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            completion(
                self.stateMachine.currentBuffer,
                self.stateMachine.isInvalidUntilBoundary,
                self.latestProcessedSequence
            )
        }
    }

    private func process(_ input: CapturedInput) {
        latestProcessedSequence = input.sequence

        if input.kind.recordsUserEdit {
            correctionQueue.async { [weak self] in
                self?.corrector.noteUserEdit(generation: input.editGeneration)
            }
        }

        let liveContext = captureState.snapshot().context
        guard input.context == liveContext else {
            _ = stateMachine.updateContext(liveContext)
            resetDetectorState()
            logger.debug("buffer invalidated reason=stale-capture-context")
            return
        }

        if input.kind.invalidatesCaptureContext,
           input.context.epoch >= stateMachine.context.epoch {
            _ = stateMachine.updateContext(input.context)
            onFocusMayChange?(input.context.frontmostPID, input.context.epoch)
        }

        for command in stateMachine.consume(input) {
            handle(command)
        }
    }

    private func handle(_ command: InputStateCommand) {
        switch command {
        case .append, .deleteLast:
            break
        case .invalidate(let reason):
            resetDetectorState()
            logger.debug("buffer invalidated reason=\(String(describing: reason), privacy: .public)")
        case .flush(let word, let boundary, let sequence, let context):
            let latest = captureState.snapshot()
            runDetection(DetectionRequest(
                word: word,
                boundary: boundary,
                sequence: sequence,
                editGeneration: latest.editGeneration,
                correctionEpoch: correctionEpoch,
                context: context
            ))
        case .requestManualCorrection(let word, let sequence, let context):
            requestManualCorrection(word: word, sequence: sequence, context: context)
        case .requestRevert(let word, let sequence, let context):
            correctionQueue.async { [weak self] in
                guard let self else { return }
                if !self.corrector.undo(
                    sequence: sequence,
                    context: context,
                    latestCaptureState: self.captureState.snapshot
                ) {
                    self.inputQueue.async {
                        self.requestManualCorrection(word: word, sequence: sequence, context: context)
                    }
                }
            }
        case .nativeUndo:
            correctionQueue.async { [weak self] in
                self?.corrector.clearUndo()
            }
        }
    }

    private func runDetection(_ request: DetectionRequest) {
        detectionQueue.async { [weak self] in
            guard let self else { return }
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let result: DetectionResult?
            if let customDetection = self.customDetection {
                result = customDetection(request)
            } else {
                let configuration = self.detectionConfiguration.withLock { $0 }
                self.detector.currentLayout = request.context.layout
                self.detector.allowedLayouts = configuration.allowedLayouts
                self.detector.ukrainianFromVariant = configuration.ukrainianFromVariant
                self.detector.ukrainianToVariant = configuration.ukrainianToVariant
                self.detector.discardBuffer()
                self.detector.addCharacter(request.word)
                result = self.detector.flushBuffer(
                    boundaryCharacter: request.boundary.isEmpty ? nil : request.boundary
                )
            }
            let duration = DispatchTime.now().uptimeNanoseconds &- startedAt
            self.logger.debug("dictionary lookup ns=\(duration, privacy: .public)")
            guard let result else { return }
            self.inputQueue.async {
                self.prepareCorrection(result: result, request: request)
            }
        }
    }

    private func prepareCorrection(result: DetectionResult, request: DetectionRequest) {
        let latest = captureState.snapshot()
        guard latest.latestPhysicalSequence == request.sequence,
              latest.editGeneration == request.editGeneration,
              latest.correctionEpoch == request.correctionEpoch,
              latest.context == request.context,
              latest.context.secureFocus == .notSecure,
              latest.correctionAllowed,
              result.originalWord.count <= 64 else {
            logger.debug("correction cancelled before emission")
            return
        }

        let boundary = request.boundary
        let plan = CorrectionPlan(
            boundarySequence: request.sequence,
            contextEpoch: request.context.epoch,
            targetPID: request.context.frontmostPID,
            editGeneration: request.editGeneration,
            correctionEpoch: request.correctionEpoch,
            deleteCount: result.originalWord.count + boundary.count,
            replacementText: result.convertedWord + boundary,
            originalText: result.originalWord,
            correctedText: result.convertedWord,
            boundaryText: boundary,
            originalLayout: result.sourceLayout,
            targetLayout: result.shouldSwitchLayout ? result.targetLayout : nil
        )

        correctionQueue.async { [weak self] in
            guard let self else { return }
            guard plan.isEligible(using: self.captureState.snapshot()) else { return }
            if let customEmission = self.customEmission {
                _ = customEmission(plan)
            } else {
                _ = self.corrector.apply(plan, latestCaptureState: self.captureState.snapshot)
            }
        }
    }

    private func requestManualCorrection(
        word: String?,
        sequence: UInt64,
        context: InputContextSnapshot
    ) {
        guard context.secureFocus == .notSecure, context.appAllowed else { return }
        let latest = captureState.snapshot()
        let generation = latest.editGeneration
        let requestCorrectionEpoch = correctionEpoch
        guard let selectedTextRequest else {
            if let word {
                runDetection(DetectionRequest(
                    word: word,
                    boundary: "",
                    sequence: sequence,
                    editGeneration: generation,
                    correctionEpoch: requestCorrectionEpoch,
                    context: context
                ))
            }
            return
        }

        selectionQueue.async { [weak self] in
            selectedTextRequest(context.frontmostPID, context.epoch) { [weak self] selectedText in
                guard let self else { return }
                self.inputQueue.async {
                let latest = self.captureState.snapshot()
                guard latest.latestPhysicalSequence == sequence,
                      latest.editGeneration == generation,
                      latest.correctionEpoch == requestCorrectionEpoch,
                      latest.context == context else {
                    return
                }

                let configuration = self.detectionConfiguration.withLock { $0 }
                if let selectedText, !selectedText.isEmpty,
                   let (targetLayout, converted) = LayoutMapper.convertToAlternatives(
                    selectedText,
                    from: context.layout,
                    ukrainianFromVariant: configuration.ukrainianFromVariant,
                    ukrainianToVariant: configuration.ukrainianToVariant
                   ).first,
                   converted != selectedText {
                    self.corrector.performSelectionCorrection(
                        selectedText: selectedText,
                        convertedText: converted,
                        targetLayout: targetLayout,
                        shouldSwitchLayout: true,
                        originalLayout: context.layout,
                        sequence: sequence,
                        context: context,
                        editGeneration: generation,
                        correctionEpoch: requestCorrectionEpoch,
                        latestCaptureState: self.captureState.snapshot
                    )
                } else if let word {
                    self.runDetection(DetectionRequest(
                        word: word,
                        boundary: "",
                        sequence: sequence,
                        editGeneration: generation,
                        correctionEpoch: requestCorrectionEpoch,
                        context: context
                    ))
                }
                }
            }
        }
    }

    private func resetDetectorState() {
        detectionQueue.async { [weak self] in
            self?.detector.reset()
        }
    }
}

private extension CapturedInput.Kind {
    var invalidatesCaptureContext: Bool {
        switch self {
        case .navigation, .focusMayChange:
            return true
        default:
            return false
        }
    }

    var recordsUserEdit: Bool {
        switch self {
        case .character, .boundary, .delete, .navigation, .focusMayChange, .undo:
            return true
        default:
            return false
        }
    }
}

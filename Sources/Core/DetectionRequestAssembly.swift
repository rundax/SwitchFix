import Foundation
import Utils

public struct DetectionConfiguration: Equatable, Sendable {
    public var allowedLayouts: Set<Layout>
    public var preferredCyrillicLayout: Layout?
    public var activeSourceSupportedLayouts: Set<Layout>
    public var ukrainianFromVariant: UkrainianKeyboardVariant
    public var ukrainianToVariant: UkrainianKeyboardVariant

    public init(
        allowedLayouts: Set<Layout> = Set(Layout.allCases),
        preferredCyrillicLayout: Layout? = nil,
        activeSourceSupportedLayouts: Set<Layout> = [.english],
        ukrainianFromVariant: UkrainianKeyboardVariant = .standard,
        ukrainianToVariant: UkrainianKeyboardVariant = .standard
    ) {
        self.allowedLayouts = allowedLayouts
        self.preferredCyrillicLayout = preferredCyrillicLayout
        self.activeSourceSupportedLayouts = activeSourceSupportedLayouts
        self.ukrainianFromVariant = ukrainianFromVariant
        self.ukrainianToVariant = ukrainianToVariant
    }
}

public func assemblePrecedingRun(from run: [RunToken], currentSequence: UInt64) -> [RunToken] {
    return run.last?.id == currentSequence ? Array(run.dropLast()) : []
}

public func assembleDetectionRequest(
    word: String,
    boundary: String,
    sequence: UInt64,
    editGeneration: UInt64,
    correctionEpoch: UInt64,
    context: InputContextSnapshot,
    run: [RunToken]
) -> DetectionRequest {
    DetectionRequest(
        word: word,
        boundary: boundary,
        sequence: sequence,
        editGeneration: editGeneration,
        correctionEpoch: correctionEpoch,
        context: context,
        precedingRun: assemblePrecedingRun(from: run, currentSequence: sequence)
    )
}

public func evaluateDetection(
    detector: LayoutDetector,
    request: DetectionRequest,
    configuration: DetectionConfiguration
) -> DetectionResult? {
    if request.context.layout.isCyrillic,
       request.word.unicodeScalars.contains(where: { $0.isASCII && $0.properties.isAlphabetic }),
       !request.word.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) {
        SwitchFixLog.engine.debug("capture mismatch: Latin characters captured under \(request.context.layout.rawValue) layout source=\(request.context.inputSourceID)")
    }
    detector.currentLayout = request.context.layout
    detector.currentInputSourceID = request.context.inputSourceID
    detector.activeSourceSupportedLayouts = configuration.activeSourceSupportedLayouts
    detector.allowedLayouts = configuration.allowedLayouts
    detector.preferredCyrillicLayout = configuration.preferredCyrillicLayout
    detector.ukrainianFromVariant = configuration.ukrainianFromVariant
    detector.ukrainianToVariant = configuration.ukrainianToVariant
    detector.syncRun(request.precedingRun, currentTokenID: request.sequence)
    detector.discardBuffer()
    detector.addCharacter(request.word)
    return detector.flushBuffer(
        boundaryCharacter: request.boundary.isEmpty ? nil : request.boundary
    )
}

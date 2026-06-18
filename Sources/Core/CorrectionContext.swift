import Foundation

public enum RecentOutcome {
    case validCurrent
    case corrected
    case unknown
}

public struct SuppressedShort {
    public let originalWord: String
    public let convertedWord: String
    public let targetLayout: Layout
    public let boundaryAfterWord: String

    public init(originalWord: String, convertedWord: String, targetLayout: Layout, boundaryAfterWord: String) {
        self.originalWord = originalWord
        self.convertedWord = convertedWord
        self.targetLayout = targetLayout
        self.boundaryAfterWord = boundaryAfterWord
    }
}

public struct CorrectionContext {
    private var recentOutcomes: [RecentOutcome] = []
    public var pendingSuppressedShort: SuppressedShort?
    
    public var shortWordSuppressionContextWindow: Int = 6
    public var shortWordSuppressionMinValidContext: Int = 2
    public var shortWordSuppressionLength: Int = 2

    public init() {}

    public mutating func reset() {
        recentOutcomes.removeAll(keepingCapacity: true)
        pendingSuppressedShort = nil
    }

    public mutating func recordOutcome(_ outcome: RecentOutcome) {
        recentOutcomes.append(outcome)
        let window = max(1, shortWordSuppressionContextWindow)
        if recentOutcomes.count > window {
            recentOutcomes.removeFirst(recentOutcomes.count - window)
        }
    }

    public mutating func consumePendingSuppressedShort() -> SuppressedShort? {
        let value = pendingSuppressedShort
        pendingSuppressedShort = nil
        return value
    }

    public func hasStrongCurrentContext() -> Bool {
        let window = max(1, shortWordSuppressionContextWindow)
        let recent = recentOutcomes.suffix(window)
        let validCount = recent.reduce(0) { partial, outcome in
            if case .validCurrent = outcome {
                return partial + 1
            }
            return partial
        }
        let hasRecentCorrection = recent.contains { outcome in
            if case .corrected = outcome { return true }
            return false
        }
        return validCount >= shortWordSuppressionMinValidContext && !hasRecentCorrection
    }

    public func shouldSuppressLowConfidenceCorrection(
        original: String,
        converted: String,
        targetLayout: Layout,
        sourceLayout: Layout,
        isLowConfidence: Bool,
        shouldSwitch: Bool
    ) -> Bool {
        guard isLowConfidence else { return false }
        guard original.count <= shortWordSuppressionLength else { return false }
        guard !shouldSwitch else { return false }
        guard targetLayout != sourceLayout else { return false }
        guard !converted.isEmpty else { return false }
        return hasStrongCurrentContext()
    }

    public func shouldSuppressAcronymFallback(
        targetLayout: Layout,
        sourceLayout: Layout,
        shouldSwitch: Bool
    ) -> Bool {
        guard targetLayout != sourceLayout else { return false }
        guard !shouldSwitch else { return false }
        return hasStrongCurrentContext()
    }

    public func mergeSuppressedShort(
        _ suppressed: SuppressedShort?,
        currentOriginal: String,
        currentConverted: String,
        targetLayout: Layout,
        isLowConfidence: Bool,
        shouldSwitch: Bool
    ) -> (original: String, converted: String)? {
        guard let suppressed = suppressed else { return nil }
        guard suppressed.targetLayout == targetLayout else { return nil }

        // Merge only when the current word provides stronger evidence than the suppressed short word.
        let hasStrongCurrentSignal = currentOriginal.count > shortWordSuppressionLength || shouldSwitch || !isLowConfidence
        guard hasStrongCurrentSignal else { return nil }

        let bridge = suppressed.boundaryAfterWord
        guard !bridge.isEmpty else { return nil }

        return (
            original: suppressed.originalWord + bridge + currentOriginal,
            converted: suppressed.convertedWord + bridge + currentConverted
        )
    }
}

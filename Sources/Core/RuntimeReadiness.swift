import Combine
import Foundation
import Utils

public enum ReadinessStatus: String {
    case checking, setupNeeded, working, paused, needsAttention
}

public enum MonitorHealth: String {
    case stopped, starting, active, failed
}

/// Effective keyboard-listening capability, not the separate Input Monitoring toggle.
/// Accessibility can satisfy ListenEvent without an Input Monitoring settings row.
public enum KeyboardListeningStatus: String {
    case checking, unavailable, available

    public var label: String {
        switch self {
        case .checking: return "Checking…"
        case .unavailable: return "Unavailable"
        case .available: return "Available"
        }
    }

    public var symbolName: String {
        switch self {
        case .checking: return "clock"
        case .unavailable: return "exclamationmark.circle.fill"
        case .available: return "checkmark.circle.fill"
        }
    }
}

/// Current process facts, never a saved onboarding-complete flag.
public struct RuntimeReadinessSnapshot: Equatable {
    public var checked = false
    public var accessibilityGranted = false
    /// Effective listening capability; this does not confirm a separate Input Monitoring grant.
    public var keyboardListeningAvailable = false
    public var postingGranted = false
    public var monitor: MonitorHealth = .stopped
    public var installedLayouts: Set<Layout> = []
    public var dictionaryLayouts: Set<Layout> = []
    public var dictionariesLoaded = false
    public var mode: InputCorrectionMode = .automatic
    public var isEnabled = true
    public var appAllowed = false
    public var appName = "this app"
    public var secureFocus: SecureFocusState = .unknown
    public var sourceSupported = false
    public var currentLayout: Layout = .english
    public var runtimeFailure: String?

    public init() {}

    public var keyboardListeningStatus: KeyboardListeningStatus {
        guard checked else { return .checking }
        return keyboardListeningAvailable ? .available : .unavailable
    }

    public var missingPermissions: [String] {
        var missing: [String] = []
        if !accessibilityGranted { missing.append("Accessibility") }
        if !keyboardListeningAvailable { missing.append("Input Monitoring") }
        return missing
    }

    public var modeName: String {
        switch mode {
        case .automatic: return "Automatic"
        case .hotkey: return "Hotkey only"
        case .layoutSwitch: return "On Layout Switch"
        }
    }

    public var hasRequiredAccess: Bool {
        accessibilityGranted && keyboardListeningAvailable && postingGranted
    }

    public var prerequisitesReady: Bool {
        installedLayouts.count >= 2 &&
            (mode != .automatic || (dictionariesLoaded && dictionaryLayouts.intersection(installedLayouts).count >= 2))
    }

    /// Live setup readiness, not a saved acknowledgment of System Settings toggles.
    /// Pausing correction or focusing another app does not undo completed setup.
    public var setupComplete: Bool {
        checked && hasRequiredAccess && monitor == .active && prerequisitesReady && runtimeFailure == nil
    }

    /// Context is checked again after the exercise takes focus.
    public var canTryCorrection: Bool {
        setupComplete && isEnabled
    }

    public var status: ReadinessStatus {
        if !checked { return .checking }
        if !missingPermissions.isEmpty { return .setupNeeded }
        if !postingGranted { return .needsAttention }
        if monitor == .starting || (mode == .automatic && !dictionariesLoaded) { return .checking }
        if monitor != .active || !prerequisitesReady || runtimeFailure != nil { return .needsAttention }
        if !isEnabled || !appAllowed || secureFocus != .notSecure || !sourceSupported { return .paused }
        if mode == .automatic && !dictionaryLayouts.contains(currentLayout) { return .needsAttention }
        return .working
    }

    public var message: String {
        if !checked { return "Checking access…" }
        if !missingPermissions.isEmpty { return "Not working — \(missingPermissions.joined(separator: " and ")) is not allowed" }
        if !postingGranted { return "Text replacement access is unavailable — check Accessibility, then restart SwitchFix" }
        if monitor == .starting { return "Starting keyboard correction…" }
        if mode == .automatic && !dictionariesLoaded { return "Preparing correction dictionaries…" }
        if let runtimeFailure { return runtimeFailure }
        if monitor != .active { return "Keyboard monitoring could not start — retry or restart SwitchFix" }
        if installedLayouts.count < 2 { return "Add at least two supported keyboard layouts in System Settings" }
        if mode == .automatic && dictionaryLayouts.intersection(installedLayouts).count < 2 {
            return "Automatic correction needs dictionaries for two installed languages — try a manual mode or reinstall"
        }
        if !isEnabled { return "Paused by you" }
        if !appAllowed { return "Paused in \(appName)" }
        if secureFocus == .secure { return "Paused in a password field" }
        if secureFocus == .unknown { return "Paused while checking the focused field" }
        if !sourceSupported { return "Paused — select a supported keyboard layout" }
        if mode == .automatic && !dictionaryLayouts.contains(currentLayout) { return "Automatic correction dictionary unavailable for \(currentLayout.rawValue)" }
        let unavailable = installedLayouts.subtracting(dictionaryLayouts)
        if mode == .automatic && !unavailable.isEmpty {
            return "Working — \(modeName); unavailable dictionaries: \(unavailable.map(\.rawValue).sorted().joined(separator: ", "))"
        }
        return "Working — \(modeName)"
    }

    public var needsSetup: Bool {
        !checked || !missingPermissions.isEmpty || !postingGranted || monitor != .active || runtimeFailure != nil
    }
}

public extension Notification.Name {
    static let readinessRefreshRequested = Notification.Name("SwitchFix.readinessRefreshRequested")
    /// Posting completed through TextCorrector. Delivery must be verified by the receiving field.
    static let switchFixCorrectionApplied = Notification.Name("SwitchFix.correctionApplied")
}

public final class ReadinessStore: ObservableObject {
    public static let shared = ReadinessStore()
    @Published public private(set) var snapshot = RuntimeReadinessSnapshot()

    private init() {}

    public func publish(_ snapshot: RuntimeReadinessSnapshot) {
        precondition(Thread.isMainThread)
        if self.snapshot != snapshot { self.snapshot = snapshot }
    }

    public func refresh(retry: Bool = false) {
        NotificationCenter.default.post(name: .readinessRefreshRequested, object: nil, userInfo: ["retry": retry])
    }
}

/// A failed monitor gets bounded automatic retries; access changes or an explicit retry reset the budget.
public struct MonitorRetryBudget {
    public private(set) var failures = 0
    public init() {}
    public var canAttempt: Bool { failures < 3 }
    public mutating func recordFailure() { failures += 1 }
    public mutating func reset() { failures = 0 }
}

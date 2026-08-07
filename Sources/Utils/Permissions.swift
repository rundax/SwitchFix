import AppKit
import ApplicationServices
import os

public class Permissions {
    public static func ensureRequiredPermissions(completion: @escaping () -> Void) {
        ensureAccessibility {
            ensureInputMonitoring {
                completion()
            }
        }
    }

    public static func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    public static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public static func isInputMonitoringGranted() -> Bool {
        return CGPreflightListenEventAccess()
    }

    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        return CGRequestListenEventAccess()
    }

    /// Shows an alert prompting the user to grant accessibility access,
    /// then polls until permission is granted, calling the completion handler on main thread.
    public static func ensureAccessibility(completion: @escaping () -> Void) {
        if isAccessibilityGranted() {
            completion()
            return
        }

        NSLog("[SwitchFix] Permissions: Accessibility not granted, requesting access")
        NSApplication.shared.activate(ignoringOtherApps: true)
        requestAccessibility()
        openAccessibilitySettings()
        pollForAccessibilityAccess(completion: completion)
    }

    public static func ensureInputMonitoring(completion: @escaping () -> Void) {
        if isInputMonitoringGranted() {
            completion()
            return
        }

        NSLog("[SwitchFix] Permissions: Input Monitoring not granted, requesting access")
        NSApplication.shared.activate(ignoringOtherApps: true)
        _ = requestInputMonitoring()
        openInputMonitoringSettings()
        pollForInputMonitoringAccess(completion: completion)
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(fallback)
        }
    }

    private static func pollForAccessibilityAccess(completion: @escaping () -> Void) {
        guard !isAccessibilityGranted() else {
            NSLog("[SwitchFix] Permissions: Accessibility granted")
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            pollForAccessibilityAccess(completion: completion)
        }
    }

    private static func pollForInputMonitoringAccess(completion: @escaping () -> Void) {
        guard !isInputMonitoringGranted() else {
            NSLog("[SwitchFix] Permissions: Input Monitoring granted")
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            pollForInputMonitoringAccess(completion: completion)
        }
    }
}

public enum AccessibilityFocusState: Equatable {
    case unknown
    case secure
    case notSecure
}

public struct AccessibilityFocusResolution: Equatable {
    public let pid: pid_t
    public let epoch: UInt64
    public let state: AccessibilityFocusState

    public init(pid: pid_t, epoch: UInt64, state: AccessibilityFocusState) {
        self.pid = pid
        self.epoch = epoch
        self.state = state
    }
}

public final class AccessibilityFocusCoordinator {
    public typealias FocusInvalidation = (pid_t) -> UInt64?
    public typealias FocusResolutionHandler = (AccessibilityFocusResolution) -> Void

    private let queryQueue = DispatchQueue(label: "com.switchfix.accessibility", qos: .userInitiated)
    private let onFocusInvalidated: FocusInvalidation
    private let onResolved: FocusResolutionHandler
    private struct QueryIdentity: Equatable {
        var pid: pid_t = 0
        var epoch: UInt64 = 0
        var generation: UInt64 = 0
    }
    private let queryIdentity = OSAllocatedUnfairLock(initialState: QueryIdentity())
    private var observedPID: pid_t = 0
    private var observedEpoch: UInt64 = 0
    private var observer: AXObserver?
    private var applicationElement: AXUIElement?
    private var fallbackQuery: DispatchWorkItem?
    private var queryGeneration: UInt64 = 0

    public init(
        onFocusInvalidated: @escaping FocusInvalidation,
        onResolved: @escaping FocusResolutionHandler
    ) {
        self.onFocusInvalidated = onFocusInvalidated
        self.onResolved = onResolved
    }

    public static func classifyFocus(
        role: String?,
        subrole: String?,
        subroleQueryDefinitive: Bool
    ) -> AccessibilityFocusState {
        guard role != nil else { return .unknown }
        if subrole == (kAXSecureTextFieldSubrole as String) {
            return .secure
        }
        return subroleQueryDefinitive ? .notSecure : .unknown
    }

    public func observeApplication(pid: pid_t, epoch: UInt64) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.stopObserving()
            self.observedPID = pid
            self.observedEpoch = epoch
            guard pid > 0 else { return }

            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.05)
            var newObserver: AXObserver?
            guard AXObserverCreate(pid, Self.observerCallback, &newObserver) == .success,
                  let newObserver else {
                self.scheduleQuery(pid: pid, epoch: epoch, delay: 0)
                return
            }

            let refcon = Unmanaged.passUnretained(self).toOpaque()
            let status = AXObserverAddNotification(
                newObserver,
                application,
                kAXFocusedUIElementChangedNotification as CFString,
                refcon
            )
            guard status == .success else {
                self.scheduleQuery(pid: pid, epoch: epoch, delay: 0)
                return
            }

            self.observer = newObserver
            self.applicationElement = application
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(newObserver),
                .commonModes
            )
            self.scheduleQuery(pid: pid, epoch: epoch, delay: 0)
        }
    }

    public func focusMayChange(pid: pid_t, epoch: UInt64) {
        runOnMain { [weak self] in
            guard let self, self.observedPID == pid else { return }
            self.observedEpoch = epoch
            self.scheduleQuery(pid: pid, epoch: epoch, delay: 0.025)
        }
    }

    public func requestSelectedText(
        pid: pid_t,
        epoch: UInt64,
        completion: @escaping (String?) -> Void
    ) {
        queryQueue.async {
            let text = Self.selectedText(pid: pid)
            DispatchQueue.main.async {
                completion(text)
            }
        }
    }

    public func stop() {
        runOnMain { [weak self] in self?.stopObserving() }
    }

    private func handleObserverNotification() {
        guard observedPID > 0, let epoch = onFocusInvalidated(observedPID) else { return }
        observedEpoch = epoch
        scheduleQuery(pid: observedPID, epoch: epoch, delay: 0)
    }

    private func scheduleQuery(pid: pid_t, epoch: UInt64, delay: TimeInterval) {
        fallbackQuery?.cancel()
        queryGeneration &+= 1
        let generation = queryGeneration
        queryIdentity.withLock {
            $0 = QueryIdentity(pid: pid, epoch: epoch, generation: generation)
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queryQueue.async {
                guard self.queryIdentity.withLock({ identity in
                    identity == QueryIdentity(pid: pid, epoch: epoch, generation: generation)
                }) else { return }
                let state = Self.focusState(pid: pid)
                DispatchQueue.main.async {
                    guard self.queryGeneration == generation,
                          self.observedPID == pid,
                          self.observedEpoch == epoch else {
                        return
                    }
                    self.onResolved(AccessibilityFocusResolution(pid: pid, epoch: epoch, state: state))
                }
            }
        }
        fallbackQuery = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func stopObserving() {
        fallbackQuery?.cancel()
        fallbackQuery = nil
        queryGeneration &+= 1
        queryIdentity.withLock {
            $0 = QueryIdentity(generation: queryGeneration)
        }
        if let observer, let applicationElement {
            AXObserverRemoveNotification(
                observer,
                applicationElement,
                kAXFocusedUIElementChangedNotification as CFString
            )
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        applicationElement = nil
        observedPID = 0
        observedEpoch = 0
    }

    private static func focusState(pid: pid_t) -> AccessibilityFocusState {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        guard let focused = focusedElement(application: application) else { return .unknown }
        AXUIElementSetMessagingTimeout(focused, 0.05)

        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXRoleAttribute as CFString,
            &roleValue
        ) == .success,
        let role = roleValue as? String else {
            return .unknown
        }

        var subroleValue: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(
            focused,
            kAXSubroleAttribute as CFString,
            &subroleValue
        )
        let definitive = subroleResult == .success ||
            subroleResult == .noValue ||
            subroleResult == .attributeUnsupported
        return classifyFocus(
            role: role,
            subrole: subroleValue as? String,
            subroleQueryDefinitive: definitive
        )
    }

    private static func selectedText(pid: pid_t) -> String? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        guard let focused = focusedElement(application: application) else { return nil }
        AXUIElementSetMessagingTimeout(focused, 0.05)

        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        ) == .success,
        let selected = selectedValue as? String,
        !selected.isEmpty else {
            return nil
        }
        return selected
    }

    private static func focusedElement(application: AXUIElement) -> AXUIElement? {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return (focusedValue as! AXUIElement)
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private static let observerCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let coordinator = Unmanaged<AccessibilityFocusCoordinator>.fromOpaque(refcon).takeUnretainedValue()
        coordinator.handleObserverNotification()
    }

    deinit {
        if Thread.isMainThread {
            stopObserving()
        }
    }
}

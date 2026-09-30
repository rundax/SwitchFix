import AppKit
import ApplicationServices
import Carbon
import IOKit.hidsystem
import os

public class Permissions {
    public static func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    public static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Effective keyboard-listening access, NOT the separate System Settings toggle.
    /// TCC can authorize ListenEvent through Accessibility even with no ListenEvent
    /// record. Both IOHID and CoreGraphics report that effective authorization.
    /// Public preflights cannot verify membership in the Input Monitoring list.
    public static func isKeyboardListeningAvailable(
        checkAccess: (IOHIDRequestType) -> IOHIDAccessType = IOHIDCheckAccess
    ) -> Bool {
        checkAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    public static func requestKeyboardListeningAccess(
        requestAccess: (IOHIDRequestType) -> Bool = IOHIDRequestAccess
    ) -> Bool {
        // Even this direct ListenEvent request can succeed through Accessibility
        // without adding an Input Monitoring row. Never treat success as proof
        // that the user enabled the separate System Settings toggle.
        requestAccess(kIOHIDRequestTypeListenEvent)
    }

    public static func isEventPostingGranted() -> Bool {
        CGPreflightPostEventAccess()
    }

    /// Read at each correction boundary; cached UI readiness is not authorization.
    public static func hasRequiredAccess() -> Bool {
        isAccessibilityGranted() && isKeyboardListeningAvailable() && isEventPostingGranted()
    }

    @discardableResult
    public static func openAccessibilitySettings() -> Bool {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    @discardableResult
    public static func openInputMonitoringSettings() -> Bool {
        openPrivacySettings(anchor: "Privacy_ListenEvent")
    }

    private static func openPrivacySettings(anchor: String) -> Bool {
        for suffix in [anchor, "Privacy"] {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(suffix)"),
               NSWorkspace.shared.open(url) { return true }
        }
        return false
    }

    @discardableResult
    public static func resetPermissions(bundleID: String? = nil) -> Bool {
        let targetID = bundleID ?? Bundle.main.bundleIdentifier ?? "com.switchfix.app"
        // All is scoped to this bundle, and covers Accessibility and ListenEvent.
        // PostEvent is not a separate user-facing permission on supported macOS.
        let services = ["All"]
        var allSucceeded = true
        for service in services {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, targetID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    allSucceeded = false
                }
            } catch {
                allSucceeded = false
            }
        }
        if let script = NSAppleScript(source: "tell application \"System Settings\" to quit") {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
        return allSucceeded
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
    private var unknownFocusRetryCount = 0
    private static let maximumUnknownFocusRetries = 8

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

    /// Falls back to macOS secure-input mode when an app does not expose its focused field.
    public static func resolveFocus(
        accessibilityState: AccessibilityFocusState,
        secureInputEnabled: Bool
    ) -> AccessibilityFocusState {
        guard accessibilityState == .unknown else { return accessibilityState }
        return secureInputEnabled ? .secure : .notSecure
    }

    public func observeApplication(pid: pid_t, epoch: UInt64) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.stopObserving()
            self.observedPID = pid
            self.observedEpoch = epoch
            self.unknownFocusRetryCount = 0
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
            self.unknownFocusRetryCount = 0
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
                    let resolvedState = Self.resolveFocus(
                        accessibilityState: state,
                        secureInputEnabled: IsSecureEventInputEnabled()
                    )
                    if state == .unknown,
                       self.unknownFocusRetryCount < Self.maximumUnknownFocusRetries {
                        self.unknownFocusRetryCount += 1
                        self.scheduleQuery(pid: pid, epoch: epoch, delay: 0.25)
                    } else {
                        self.unknownFocusRetryCount = 0
                    }
                    self.onResolved(AccessibilityFocusResolution(pid: pid, epoch: epoch, state: resolvedState))
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

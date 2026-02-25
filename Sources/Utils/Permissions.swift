import AppKit
import ApplicationServices

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
        DispatchQueue.global(qos: .userInitiated).async {
            while !isAccessibilityGranted() {
                Thread.sleep(forTimeInterval: 2.0)
            }
            DispatchQueue.main.async {
                NSLog("[SwitchFix] Permissions: Accessibility granted")
                completion()
            }
        }
    }

    private static func pollForInputMonitoringAccess(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            while !isInputMonitoringGranted() {
                Thread.sleep(forTimeInterval: 2.0)
            }
            DispatchQueue.main.async {
                NSLog("[SwitchFix] Permissions: Input Monitoring granted")
                completion()
            }
        }
    }

    /// Get the currently selected text from the focused UI element via Accessibility API.
    public static func getSelectedText() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else { return nil }

        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        guard textResult == .success, let text = selectedText as? String, !text.isEmpty else { return nil }

        return text
    }

    /// Cached result for secure field check to avoid expensive AXUIElement calls on every keystroke.
    private static var cachedSecureResult: Bool = false
    private static var cachedSecureTime: UInt64 = 0
    private static let secureCacheTTL: UInt64 = 500_000_000 // 500ms in nanoseconds

    /// Check if the currently focused UI element is a secure text field (password).
    /// Result is cached for 500ms to avoid expensive AXUIElement calls on every keystroke.
    public static func isFocusedElementSecure() -> Bool {
        let now = mach_absolute_time()
        // Convert to nanoseconds using timebase
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let elapsed = (now - cachedSecureTime) * UInt64(info.numer) / UInt64(info.denom)

        if elapsed < secureCacheTTL {
            return cachedSecureResult
        }

        cachedSecureTime = now
        cachedSecureResult = checkFocusedElementSecure()
        return cachedSecureResult
    }

    /// Invalidate the secure field cache (call on focus/app change).
    public static func invalidateSecureFieldCache() {
        cachedSecureTime = 0
    }

    private static func checkFocusedElementSecure() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else { return false }

        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &roleValue)
        if roleResult == .success, let role = roleValue as? String, role == "AXSecureTextField" {
            return true
        }

        return false
    }
}

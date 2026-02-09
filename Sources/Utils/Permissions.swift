import AppKit
import ApplicationServices

public class Permissions {
    public static func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    public static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Shows an alert prompting the user to grant accessibility access,
    /// then polls until permission is granted, calling the completion handler on main thread.
    public static func ensureAccessibility(completion: @escaping () -> Void) {
        if isAccessibilityGranted() {
            completion()
            return
        }

        let alert = NSAlert()
        alert.messageText = "SwitchFix Needs Accessibility Access"
        alert.informativeText = "SwitchFix needs Accessibility permissions to monitor keyboard input and correct layout mistakes.\n\nPlease enable SwitchFix in System Settings → Privacy & Security → Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSApplication.shared.terminate(nil)
            return
        }

        // Open System Settings to Accessibility pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // Poll for permission every 2 seconds
        pollForAccessibility(completion: completion)
    }

    private static func pollForAccessibility(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            while !isAccessibilityGranted() {
                Thread.sleep(forTimeInterval: 2.0)
            }
            DispatchQueue.main.async {
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

    /// Check if the currently focused UI element is a secure text field (password).
    public static func isFocusedElementSecure() -> Bool {
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

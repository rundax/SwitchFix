import AppKit
import SwiftUI

public class SettingsWindowController: NSObject {
    public static let shared = SettingsWindowController()

    private var windowController: NSWindowController?

    public func showSettings() {
        if let existing = windowController, let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "SwitchFix Settings"
        window.contentViewController = hostingController
        // Ensure window is released when closed so we can recreate it cleanly or handle shouldClose logic
        window.isReleasedWhenClosed = false
        
        let controller = NSWindowController(window: window)
        self.windowController = controller

        // Observe window close to clear reference
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}

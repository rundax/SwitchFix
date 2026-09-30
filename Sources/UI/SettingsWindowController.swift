import AppKit
import SwiftUI

public class SettingsWindowController: NSObject {
    public static let shared = SettingsWindowController()

    private var windowController: NSWindowController?

    public func showSettings() {
        present(
            NSHostingController(rootView: SettingsView()),
            title: "SwitchFix Settings",
            contentSize: NSSize(width: 500, height: 720),
            minimumSize: NSSize(width: 480, height: 560)
        )
    }

    public func showSetup() {
        present(
            NSHostingController(rootView: ReadinessSetupView()),
            title: "Finish setting up SwitchFix",
            contentSize: NSSize(width: 520, height: 720),
            minimumSize: NSSize(width: 500, height: 560)
        )
    }

    private func present(
        _ hostingController: NSHostingController<some View>,
        title: String,
        contentSize: NSSize,
        minimumSize: NSSize
    ) {
        if let existing = windowController, let window = existing.window {
            window.title = title
            window.contentViewController = hostingController
            window.contentMinSize = minimumSize
            window.setContentSize(contentSize)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = minimumSize
        window.center()
        window.title = title
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
        if let window = notification.object as? NSWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        }
        windowController = nil
    }
}

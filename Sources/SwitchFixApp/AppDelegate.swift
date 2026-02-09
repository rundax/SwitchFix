import AppKit
import Core
import UI
import Utils

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var keyboardMonitor: KeyboardMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()

        Permissions.ensureAccessibility { [weak self] in
            self?.startMonitoring()
        }
    }

    private func startMonitoring() {
        keyboardMonitor = KeyboardMonitor()
        keyboardMonitor?.start()
    }
}

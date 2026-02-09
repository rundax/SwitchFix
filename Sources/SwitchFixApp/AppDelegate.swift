import AppKit
import Core
import UI
import Utils

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var keyboardMonitor: KeyboardMonitor?
    private var layoutDetector: LayoutDetector?
    private var textCorrector: TextCorrector?
    private let inputSourceManager = InputSourceManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()

        setupCorrectionEngine()

        Permissions.ensureAccessibility { [weak self] in
            self?.startMonitoring()
        }
    }

    private func setupCorrectionEngine() {
        layoutDetector = LayoutDetector()
        layoutDetector?.delegate = self

        textCorrector = TextCorrector()
        textCorrector?.onCorrectionStarted = { [weak self] in
            self?.keyboardMonitor?.isPaused = true
            self?.layoutDetector?.beginCorrection()
        }
        textCorrector?.onCorrectionFinished = { [weak self] in
            self?.keyboardMonitor?.isPaused = false
            self?.layoutDetector?.endCorrection()
        }
    }

    private func startMonitoring() {
        keyboardMonitor = KeyboardMonitor()
        keyboardMonitor?.delegate = self
        keyboardMonitor?.start()

        // Observe frontmost app changes to reset detector on app switch
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeAppChanged() {
        layoutDetector?.reset()
    }
}

// MARK: - KeyboardMonitorDelegate

extension AppDelegate: KeyboardMonitorDelegate {
    func keyboardMonitor(_ monitor: KeyboardMonitor, didReceiveCharacter character: String, keyCode: UInt16) {
        guard PreferencesManager.shared.isEnabled else { return }
        guard PreferencesManager.shared.correctionMode == .automatic else { return }

        // Update the detector's current layout
        layoutDetector?.currentLayout = inputSourceManager.currentLayout()
        layoutDetector?.addCharacter(character)
    }

    func keyboardMonitorDidReceiveSpace(_ monitor: KeyboardMonitor) {
        guard PreferencesManager.shared.isEnabled else { return }
        guard PreferencesManager.shared.correctionMode == .automatic else { return }

        layoutDetector?.flushBuffer()
    }

    func keyboardMonitorDidReceiveDelete(_ monitor: KeyboardMonitor) {
        layoutDetector?.deleteLastCharacter()
    }
}

// MARK: - LayoutDetectorDelegate

extension AppDelegate: LayoutDetectorDelegate {
    func layoutDetector(_ detector: LayoutDetector, didDetectWrongLayout result: DetectionResult) {
        textCorrector?.performCorrection(result: result)
    }
}

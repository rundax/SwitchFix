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

    /// Cached result for whether the current frontmost app is allowed (updated on app switch).
    private var isCurrentAppAllowed: Bool = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[SwitchFix] App launching, mode: %@", PreferencesManager.shared.correctionMode == .automatic ? "automatic" : "hotkey")

        statusBarController = StatusBarController()

        setupCorrectionEngine()

        Permissions.ensureAccessibility { [weak self] in
            self?.startMonitoring()
            NSLog("[SwitchFix] Monitoring started, available layouts: %@",
                  InputSourceManager.shared.availableLayouts().map { $0.rawValue }.joined(separator: ", "))
        }
    }

    private func setupCorrectionEngine() {
        layoutDetector = LayoutDetector()
        layoutDetector?.delegate = self
        let available = inputSourceManager.availableLayouts()
        if !available.isEmpty {
            layoutDetector?.allowedLayouts = Set(available)
        }

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

        // Apply hotkey settings from preferences
        keyboardMonitor?.hotkeyKeyCode = PreferencesManager.shared.hotkeyKeyCode
        keyboardMonitor?.hotkeyModifiers = PreferencesManager.shared.hotkeyModifiers
        keyboardMonitor?.onKeyDownWhilePaused = { [weak self] in
            self?.textCorrector?.noteUserInputDuringCorrection()
        }

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
        isCurrentAppAllowed = AppFilter.shared.isCurrentAppAllowed()
        Permissions.invalidateSecureFieldCache()
        if let app = NSWorkspace.shared.frontmostApplication {
            NSLog("[SwitchFix] App switched to: %@ (allowed: %@)", app.localizedName ?? "unknown", isCurrentAppAllowed ? "yes" : "no")
        }
    }
}

// MARK: - KeyboardMonitorDelegate

extension AppDelegate: KeyboardMonitorDelegate {
    func keyboardMonitor(_ monitor: KeyboardMonitor, didReceiveCharacter character: String, keyCode: UInt16) {
        guard PreferencesManager.shared.isEnabled else { return }
        guard isCurrentAppAllowed else { return }

        let layout = inputSourceManager.currentLayout()
        layoutDetector?.currentLayout = layout
        layoutDetector?.addCharacter(character)
    }

    func keyboardMonitor(_ monitor: KeyboardMonitor, didReceiveBoundary character: String) {
        guard PreferencesManager.shared.isEnabled else { return }
        guard isCurrentAppAllowed else { return }

        if PreferencesManager.shared.correctionMode == .automatic {
            // Automatic mode: flush triggers detection + correction
            // Pass boundary character (space, punctuation, newline, etc.) so correction can retype it
            let boundary = character.isEmpty ? nil : character
            layoutDetector?.flushBuffer(boundaryCharacter: boundary)
        } else {
            // Hotkey mode: just discard the buffer (word boundary passed)
            layoutDetector?.discardBuffer()
        }
    }

    func keyboardMonitorDidReceiveDelete(_ monitor: KeyboardMonitor) {
        layoutDetector?.deleteLastCharacter()
    }

    func keyboardMonitorDidReceiveHotkey(_ monitor: KeyboardMonitor) {
        guard PreferencesManager.shared.isEnabled else { return }
        guard isCurrentAppAllowed else { return }

        // First, try selection-based correction (works in any mode)
        if let selectedText = Permissions.getSelectedText() {
            let currentLayout = inputSourceManager.currentLayout()
            let alternatives = LayoutMapper.convertToAlternatives(selectedText, from: currentLayout)

            // Use the first conversion (user explicitly requested conversion)
            if let (targetLayout, converted) = alternatives.first {
                textCorrector?.performSelectionCorrection(
                    selectedText: selectedText,
                    convertedText: converted,
                    targetLayout: targetLayout
                )
            }
            return
        }

        // Fallback: buffer-based correction — flush triggers detection
        layoutDetector?.currentLayout = inputSourceManager.currentLayout()
        layoutDetector?.flushBuffer()
    }

    func keyboardMonitorDidReceiveUndo(_ monitor: KeyboardMonitor) {
        guard PreferencesManager.shared.isEnabled else { return }

        // Only undo if there's a recent correction within the time window
        guard let corrector = textCorrector, corrector.canUndo else { return }

        let currentLayout = inputSourceManager.currentLayout()
        corrector.undoLastCorrection(currentLayout: currentLayout)
    }
}

// MARK: - LayoutDetectorDelegate

extension AppDelegate: LayoutDetectorDelegate {
    func layoutDetector(_ detector: LayoutDetector, didDetectWrongLayout result: DetectionResult, boundaryCharacter: String?) {
        textCorrector?.performCorrection(result: result, boundaryCharacter: boundaryCharacter)
    }
}

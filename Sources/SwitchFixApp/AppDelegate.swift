import AppKit
import Carbon
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
    private var capsLockConflictProbeToken: UUID?
    private static let capsLockKeyCode: UInt16 = 57

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
        keyboardMonitor?.revertHotkeyKeyCode = PreferencesManager.shared.revertHotkeyKeyCode
        keyboardMonitor?.revertHotkeyModifiers = PreferencesManager.shared.revertHotkeyModifiers

        if PreferencesManager.shared.revertHotkeyKeyCode != AppDelegate.capsLockKeyCode {
            SystemHotkeyConflicts.clearObservedCapsLockConflict()
        }

        keyboardMonitor?.onKeyDownWhilePaused = { [weak self] in
            self?.textCorrector?.noteUserInputDuringCorrection()
            self?.textCorrector?.noteUserEdit()
            self?.textCorrector?.recordUserInput(kind: .character)
        }

        keyboardMonitor?.start()

        // Observe frontmost app changes to reset detector on app switch
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(selectedInputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
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

    @objc private func selectedInputSourceChanged() {
        guard capsLockConflictProbeToken != nil else { return }
        capsLockConflictProbeToken = nil
        SystemHotkeyConflicts.markObservedCapsLockConflict()
        NSLog("[SwitchFix] Warning: observed CapsLock conflict (input source changed immediately after revert hotkey)")
    }

    private func startCapsLockConflictProbe() {
        guard PreferencesManager.shared.revertHotkeyKeyCode == AppDelegate.capsLockKeyCode else {
            capsLockConflictProbeToken = nil
            SystemHotkeyConflicts.clearObservedCapsLockConflict()
            return
        }

        let token = UUID()
        capsLockConflictProbeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            guard self.capsLockConflictProbeToken == token else { return }
            self.capsLockConflictProbeToken = nil
            SystemHotkeyConflicts.clearObservedCapsLockConflict()
        }
    }

    private func refreshLayoutVariants(for currentLayout: Layout) {
        let targetVariant = inputSourceManager.preferredUkrainianVariant()
        layoutDetector?.ukrainianToVariant = targetVariant

        if currentLayout == .ukrainian {
            layoutDetector?.ukrainianFromVariant = inputSourceManager.currentUkrainianVariant() ?? targetVariant
        } else {
            layoutDetector?.ukrainianFromVariant = targetVariant
        }
    }

    @discardableResult
    private func triggerManualCorrectionFromCurrentContext() -> Bool {
        // First, try selection-based correction (works in any mode)
        if let selectedText = Permissions.getSelectedText() {
            let currentLayout = inputSourceManager.currentLayout()
            let fromVariant = inputSourceManager.currentUkrainianVariant() ?? inputSourceManager.preferredUkrainianVariant()
            let toVariant = inputSourceManager.preferredUkrainianVariant()
            let alternatives = LayoutMapper.convertToAlternatives(
                selectedText,
                from: currentLayout,
                ukrainianFromVariant: fromVariant,
                ukrainianToVariant: toVariant
            )

            if let (targetLayout, converted) = alternatives.first {
                textCorrector?.performSelectionCorrection(
                    selectedText: selectedText,
                    convertedText: converted,
                    targetLayout: targetLayout
                )
                return true
            }
        }

        // Fallback: buffer-based correction — flush triggers detection
        guard let detector = layoutDetector, !detector.currentBuffer.isEmpty else {
            return false
        }

        let layout = inputSourceManager.currentLayout()
        detector.currentLayout = layout
        refreshLayoutVariants(for: layout)
        detector.flushBuffer()
        textCorrector?.recordUserInput(kind: .other)
        return true
    }
}

// MARK: - KeyboardMonitorDelegate

extension AppDelegate: KeyboardMonitorDelegate {
    func keyboardMonitor(_ monitor: KeyboardMonitor, didReceiveCharacter character: String, keyCode: UInt16) {
        guard PreferencesManager.shared.isEnabled else { return }
        guard isCurrentAppAllowed else { return }

        let layout = inputSourceManager.currentLayout()
        layoutDetector?.currentLayout = layout
        refreshLayoutVariants(for: layout)
        layoutDetector?.addCharacter(character)
        textCorrector?.noteUserEdit()
        textCorrector?.recordUserInput(kind: .character)
    }

    func keyboardMonitor(_ monitor: KeyboardMonitor, didReceiveBoundary character: String) {
        guard PreferencesManager.shared.isEnabled else { return }
        guard isCurrentAppAllowed else { return }
        textCorrector?.noteUserEdit()

        if PreferencesManager.shared.correctionMode == .automatic {
            // Automatic mode: flush triggers detection + correction
            // Pass boundary character (space, punctuation, newline, etc.) so correction can retype it
            let layout = inputSourceManager.currentLayout()
            layoutDetector?.currentLayout = layout
            refreshLayoutVariants(for: layout)
            let boundary = character.isEmpty ? nil : character
            layoutDetector?.flushBuffer(boundaryCharacter: boundary)
        } else {
            // Hotkey mode: just discard the buffer (word boundary passed)
            layoutDetector?.discardBuffer()
        }
        textCorrector?.recordUserInput(kind: .boundary)
    }

    func keyboardMonitorDidReceiveDelete(_ monitor: KeyboardMonitor) {
        layoutDetector?.deleteLastCharacter()
        textCorrector?.noteUserEdit()
        textCorrector?.recordUserInput(kind: .other)
    }

    func keyboardMonitorDidReceiveHotkey(_ monitor: KeyboardMonitor) {
        guard PreferencesManager.shared.isEnabled else { return }
        guard isCurrentAppAllowed else { return }
        _ = triggerManualCorrectionFromCurrentContext()
    }

    func keyboardMonitorDidReceiveUndo(_ monitor: KeyboardMonitor) {
        guard PreferencesManager.shared.isEnabled else { return }

        // Only undo if there's a recent correction within the time window
        guard let corrector = textCorrector, corrector.canUndo else { return }

        let currentLayout = inputSourceManager.currentLayout()
        corrector.undoLastCorrection(currentLayout: currentLayout)
        textCorrector?.recordUserInput(kind: .other)
    }

    func keyboardMonitorDidReceiveRevertHotkey(_ monitor: KeyboardMonitor) {
        guard PreferencesManager.shared.isEnabled else { return }

        guard let corrector = textCorrector else { return }
        guard corrector.canUndo else {
            startCapsLockConflictProbe()
            guard isCurrentAppAllowed else { return }
            _ = triggerManualCorrectionFromCurrentContext()
            return
        }

        let currentLayout = inputSourceManager.currentLayout()
        corrector.undoLastCorrection(currentLayout: currentLayout)
        textCorrector?.recordUserInput(kind: .other)
    }
}

// MARK: - LayoutDetectorDelegate

extension AppDelegate: LayoutDetectorDelegate {
    func layoutDetector(_ detector: LayoutDetector, didDetectWrongLayout result: DetectionResult, boundaryCharacter: String?) {
        textCorrector?.performCorrection(result: result, boundaryCharacter: boundaryCharacter)
    }
}

import AppKit
import Carbon
import Core
import Dictionary
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
    private var monitoringObserversRegistered: Bool = false
    private var previousLayout: Layout = .english
    private var isCorrectionInProgress: Bool = false
    private static let capsLockKeyCode: UInt16 = 57

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[SwitchFix] App launching, mode: %@", PreferencesManager.shared.correctionMode == .automatic ? "automatic" : "hotkey")

        statusBarController = StatusBarController()

        setupCorrectionEngine()
        prewarmDictionaries()

        previousLayout = inputSourceManager.currentLayout()

        Permissions.ensureRequiredPermissions { [weak self] in
            guard let self else { return }
            if self.startMonitoring() {
                NSLog("[SwitchFix] Monitoring started, available layouts: %@",
                      InputSourceManager.shared.availableLayouts().map { $0.rawValue }.joined(separator: ", "))
            } else {
                let accessibility = Permissions.isAccessibilityGranted()
                let inputMonitoring = Permissions.isInputMonitoringGranted()
                NSLog("[SwitchFix] Monitoring failed to start (Accessibility: %@, Input Monitoring: %@)",
                      accessibility ? "granted" : "missing",
                      inputMonitoring ? "granted" : "missing")
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidUpdate),
            name: .preferencesDidChange,
            object: nil
        )
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
            self?.isCorrectionInProgress = true
            self?.keyboardMonitor?.isPaused = true
            self?.layoutDetector?.beginCorrection()
        }
        textCorrector?.onCorrectionFinished = { [weak self] in
            self?.isCorrectionInProgress = false
            self?.keyboardMonitor?.isPaused = false
            self?.layoutDetector?.endCorrection()
        }
    }

    private func prewarmDictionaries() {
        let availableLayouts = inputSourceManager.availableLayouts()
        guard !availableLayouts.isEmpty else { return }

        let currentLayout = inputSourceManager.currentLayout()
        let currentLanguage: Language
        switch currentLayout {
        case .english:
            currentLanguage = .english
        case .ukrainian:
            currentLanguage = .ukrainian
        case .russian:
            currentLanguage = .russian
        }

        DispatchQueue.global(qos: .utility).async {
            let loader = DictionaryLoader.shared
            loader.prewarm(language: currentLanguage, includeSuggestions: false)
            NSLog("[SwitchFix] Dictionary prewarm complete for current layout: %@",
                  currentLanguage.rawValue)
        }
    }

    @discardableResult
    private func startMonitoring() -> Bool {
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

        guard keyboardMonitor?.start() == true else {
            return false
        }

        guard !monitoringObserversRegistered else { return true }
        monitoringObserversRegistered = true

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
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        return true
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
        let newLayout = inputSourceManager.currentLayout()
        defer { previousLayout = newLayout }

        if capsLockConflictProbeToken != nil {
            capsLockConflictProbeToken = nil
            SystemHotkeyConflicts.markObservedCapsLockConflict()
            NSLog("[SwitchFix] Warning: observed CapsLock conflict (input source changed immediately after revert hotkey)")
            return
        }

        NSLog("[SwitchFix] Input source changed: %@ -> %@", previousLayout.rawValue, newLayout.rawValue)

        guard !isCorrectionInProgress else { return }
        guard PreferencesManager.shared.correctionMode == .layoutSwitch else { return }
        guard PreferencesManager.shared.isEnabled else { return }
        guard isCurrentAppAllowed else { return }
        guard newLayout != previousLayout else { return }

        triggerLayoutSwitchCorrection(from: previousLayout, to: newLayout)
    }

    /// Returns true when `text` contains at least one letter belonging to the script
    /// of `layout` (Latin for English, Cyrillic for Ukrainian/Russian). Text that has
    /// no letters of the expected script is considered foreign and should not be
    /// transcribed from `layout`.
    private func textContainsScript(of layout: Layout, text: String) -> Bool {
        let latinLowercase: ClosedRange<UInt32> = 0x0061...0x007A
        let latinUppercase: ClosedRange<UInt32> = 0x0041...0x005A
        let cyrillicRange: ClosedRange<UInt32> = 0x0400...0x04FF

        switch layout {
        case .english:
            return text.unicodeScalars.contains { scalar in
                latinLowercase.contains(scalar.value) || latinUppercase.contains(scalar.value)
            }
        case .ukrainian, .russian:
            return text.unicodeScalars.contains { scalar in
                cyrillicRange.contains(scalar.value)
            }
        }
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
    
    private func triggerLayoutSwitchCorrection(from fromLayout: Layout, to toLayout: Layout) {
        let fromVariant = inputSourceManager.currentUkrainianVariant() ?? inputSourceManager.preferredUkrainianVariant()
        let toVariant = inputSourceManager.preferredUkrainianVariant()

        if let selection = Permissions.getSelectedText(), !selection.isEmpty {
            guard textContainsScript(of: fromLayout, text: selection) else {
                NSLog("[SwitchFix] Layout-switch correction: selection not in %@ script, skipping", fromLayout.rawValue)
                return
            }
            let converted = LayoutMapper.convert(
                selection,
                from: fromLayout,
                to: toLayout,
                ukrainianFromVariant: fromVariant,
                ukrainianToVariant: toVariant
            )
            guard converted != selection else { return }
            NSLog("[SwitchFix] Layout-switch correction: selection '%@' → '%@' (%@→%@)", selection, converted, fromLayout.rawValue, toLayout.rawValue)
            layoutDetector?.discardBuffer()
            textCorrector?.performSelectionCorrection(
                selectedText: selection,
                convertedText: converted,
                targetLayout: toLayout,
                shouldSwitchLayout: false
            )
            return
        }

        guard let detector = layoutDetector, !detector.currentBuffer.isEmpty else { return }
        let originalWord = detector.currentBuffer
        guard textContainsScript(of: fromLayout, text: originalWord) else {
            NSLog("[SwitchFix] Layout-switch correction: buffer '%@' not in %@ script, skipping",
                  originalWord, fromLayout.rawValue)
            detector.discardBuffer()
            return
        }
        let converted = LayoutMapper.convert(
            originalWord,
            from: fromLayout,
            to: toLayout,
            ukrainianFromVariant: fromVariant,
            ukrainianToVariant: toVariant
        )
        guard converted != originalWord else { return }

        NSLog("[SwitchFix] Layout-switch correction: buffer '%@' → '%@' (%@→%@)",
              originalWord, converted, fromLayout.rawValue, toLayout.rawValue)

        let result = DetectionResult(
            sourceLayout: fromLayout,
            targetLayout: toLayout,
            convertedWord: converted,
            originalWord: originalWord,
            shouldSwitchLayout: false
        )
        detector.discardBuffer()
        textCorrector?.performCorrection(result: result, boundaryCharacter: nil)
        textCorrector?.recordUserInput(kind: .other)
    }
    
    @objc private func preferencesDidUpdate() {
        guard let monitor = keyboardMonitor else { return }
        monitor.hotkeyKeyCode = PreferencesManager.shared.hotkeyKeyCode
        monitor.hotkeyModifiers = PreferencesManager.shared.hotkeyModifiers
        monitor.revertHotkeyKeyCode = PreferencesManager.shared.revertHotkeyKeyCode
        monitor.revertHotkeyModifiers = PreferencesManager.shared.revertHotkeyModifiers

        // Re-check conflict whenever settings change
        if PreferencesManager.shared.revertHotkeyKeyCode != AppDelegate.capsLockKeyCode {
            SystemHotkeyConflicts.clearObservedCapsLockConflict()
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
        refreshLayoutVariants(for: layout)
        layoutDetector?.addCharacter(character)
        textCorrector?.noteUserEdit()
        textCorrector?.recordUserInput(kind: .character)
    }

    func keyboardMonitor(_ monitor: KeyboardMonitor, didReceiveBoundary character: String) {
        guard PreferencesManager.shared.isEnabled else { return }
        guard isCurrentAppAllowed else { return }
        textCorrector?.noteUserEdit()

        switch PreferencesManager.shared.correctionMode {
        case .automatic:
            // Automatic mode: flush triggers detection + correction
            // Pass boundary character (space, punctuation, newline, etc.) so correction can retype it
            let layout = inputSourceManager.currentLayout()
            layoutDetector?.currentLayout = layout
            refreshLayoutVariants(for: layout)
            let boundary = character.isEmpty ? nil : character
            layoutDetector?.flushBuffer(boundaryCharacter: boundary)
        case .hotkey, .layoutSwitch:
            // Discard the buffer on word boundary — correction is triggered elsewhere
            // (via hotkey, or via system keyboard-layout change)
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

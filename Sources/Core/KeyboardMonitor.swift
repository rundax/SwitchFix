import AppKit
import Carbon
import CoreGraphics
import Foundation
import os
import Utils

public final class KeyboardMonitor {
    public var onInput: ((CapturedInput) -> Void)?

    private struct TapLifecycle {
        var tap: CFMachPort?
        var source: CFRunLoopSource?
        var isMonitoring = false
        var prefersLayoutTranslation = false
    }

    private struct EventMetadata {
        let sequence: UInt64
        let timestamp: UInt64
        let keyCode: UInt16
        let flagsRawValue: UInt64
        let isAutorepeat: Bool
        let sourcePID: Int32
        let sourceUserData: Int64
        let callbackDurationNanoseconds: UInt64
    }

    private struct TranslationKey: Hashable {
        let keyCode: UInt16
        let shifted: Bool
    }

    private let captureState: CaptureStateStore
    private let lifecycle = OSAllocatedUnfairLock(initialState: TapLifecycle())
    private let translations = OSAllocatedUnfairLock(initialState: [TranslationKey: String]())
    private var diagnosticRing = [EventMetadata?](repeating: nil, count: 256)
    private var diagnosticRingIndex = 0
    // Tap-callback-thread confined: tracks caps lock toggle state for edge detection.
    private var lastAlphaShiftState: Bool?
    private var tapResetCount: UInt64 = 0

    private static let spaceKeyCode: UInt16 = 49
    private static let returnKeyCode: UInt16 = 36
    private static let tabKeyCode: UInt16 = 48
    private static let escapeKeyCode: UInt16 = 53
    private static let deleteKeyCode: UInt16 = 51
    private static let capsLockKeyCode: UInt16 = 57
    private static let zKeyCode: UInt16 = 6

    private static let functionKeyCodes: Set<UInt16> = Set([
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80,
    ])

    private static let navigationKeyCodes: Set<UInt16> = Set([
        123, 124, 125, 126,
        115, 119, 116, 121,
        117, // forward delete: must not reach the character buffer as U+F728
    ])

    private static let boundaryCharacterSet: CharacterSet = {
        var set = CharacterSet.punctuationCharacters.union(.symbols)
        set.subtract(CharacterSet(charactersIn: "'’`-"))
        return set
    }()

    private static let softBoundaryCharacterSet = CharacterSet(charactersIn: ",.;'[]`<>:\"{}~")

    public init(captureState: CaptureStateStore? = nil) {
        if let captureState {
            self.captureState = captureState
        } else {
            let context = InputContextSnapshot(
                epoch: 0,
                frontmostPID: 0,
                appAllowed: false,
                layout: .english,
                inputSourceID: "unknown",
                secureFocus: .unknown
            )
            self.captureState = CaptureStateStore(
                context: context,
                hotkeys: HotkeyConfiguration(
                    hotkeyModifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
                )
            )
        }
    }

    public var hotkeyKeyCode: UInt16 {
        get { captureState.hotkeyConfiguration().hotkeyKeyCode }
        set {
            let old = captureState.hotkeyConfiguration()
            captureState.updateHotkeys(HotkeyConfiguration(
                hotkeyKeyCode: newValue,
                hotkeyModifiers: old.hotkeyModifiers,
                revertHotkeyKeyCode: old.revertHotkeyKeyCode,
                revertHotkeyModifiers: old.revertHotkeyModifiers
            ))
        }
    }

    public var hotkeyModifiers: UInt64 {
        get { captureState.hotkeyConfiguration().hotkeyModifiers }
        set {
            let old = captureState.hotkeyConfiguration()
            captureState.updateHotkeys(HotkeyConfiguration(
                hotkeyKeyCode: old.hotkeyKeyCode,
                hotkeyModifiers: newValue,
                revertHotkeyKeyCode: old.revertHotkeyKeyCode,
                revertHotkeyModifiers: old.revertHotkeyModifiers
            ))
        }
    }

    public var revertHotkeyKeyCode: UInt16 {
        get { captureState.hotkeyConfiguration().revertHotkeyKeyCode }
        set {
            let old = captureState.hotkeyConfiguration()
            captureState.updateHotkeys(HotkeyConfiguration(
                hotkeyKeyCode: old.hotkeyKeyCode,
                hotkeyModifiers: old.hotkeyModifiers,
                revertHotkeyKeyCode: newValue,
                revertHotkeyModifiers: old.revertHotkeyModifiers
            ))
        }
    }

    public var revertHotkeyModifiers: UInt64 {
        get { captureState.hotkeyConfiguration().revertHotkeyModifiers }
        set {
            let old = captureState.hotkeyConfiguration()
            captureState.updateHotkeys(HotkeyConfiguration(
                hotkeyKeyCode: old.hotkeyKeyCode,
                hotkeyModifiers: old.hotkeyModifiers,
                revertHotkeyKeyCode: old.revertHotkeyKeyCode,
                revertHotkeyModifiers: newValue
            ))
        }
    }

    @discardableResult
    public func start() -> Bool {
        if lifecycle.withLock({ $0.isMonitoring }) {
            return true
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tapResult = createEventTap(eventMask: eventMask, userInfo: userInfo),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tapResult.tap, 0) else {
            let accessibility = Permissions.isAccessibilityGranted()
            let inputMonitoring = Permissions.isInputMonitoringGranted()
            NSLog(
                "[SwitchFix] KeyboardMonitor: failed to create event tap (Accessibility: %@, Input Monitoring: %@)",
                accessibility ? "granted" : "missing",
                inputMonitoring ? "granted" : "missing"
            )
            return false
        }

        lifecycle.withLock { value in
            value.tap = tapResult.tap
            value.source = source
            value.isMonitoring = true
            value.prefersLayoutTranslation = tapResult.location == .cghidEventTap
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tapResult.tap, enable: true)
        NSLog(
            "[SwitchFix] KeyboardMonitor: event tap active (%@)",
            tapResult.location == .cgSessionEventTap ? "session" : "HID"
        )
        return true
    }

    /// Precompute HID fallback translations away from the event-tap callback.
    public func refreshInputTranslations() {
        let sources = [
            TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
        ].compactMap { $0 }
        var table: [TranslationKey: String] = [:]
        for source in sources {
            for keyCode in UInt16(0)..<UInt16(128) {
                for shifted in [false, true] {
                    let key = TranslationKey(keyCode: keyCode, shifted: shifted)
                    if table[key] == nil,
                       let text = Self.translatedCharacter(from: source, keyCode: keyCode, shifted: shifted) {
                        table[key] = text
                    }
                }
            }
        }
        let preparedTable = table
        translations.withLock { $0 = preparedTable }
    }

    public func stop() {
        let resources = lifecycle.withLock { value -> (CFMachPort?, CFRunLoopSource?) in
            guard value.isMonitoring else { return (nil, nil) }
            value.isMonitoring = false
            value.prefersLayoutTranslation = false
            let resources = (value.tap, value.source)
            value.tap = nil
            value.source = nil
            return resources
        }

        if let tap = resources.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = resources.1 {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func createEventTap(
        eventMask: CGEventMask,
        userInfo: UnsafeMutableRawPointer
    ) -> (tap: CFMachPort, location: CGEventTapLocation)? {
        for location: CGEventTapLocation in [.cgSessionEventTap, .cghidEventTap] {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: KeyboardMonitor.eventTapCallback,
                userInfo: userInfo
            ) {
                return (tap, location)
            }
        }
        return nil
    }

    private func handleTapReset(event: CGEvent) {
        tapResetCount &+= 1
        let input = captureState.capture(
            timestamp: event.timestamp,
            kind: .tapReset,
            keyCode: 0,
            flagsRawValue: event.flags.rawValue,
            isAutorepeat: false,
            sourcePID: Int32(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID)),
            sourceUserData: event.getIntegerValueField(.eventSourceUserData)
        )
        onInput?(input)
        if let tap = lifecycle.withLock({ $0.tap }) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handle(type: CGEventType, event: CGEvent, startedAt: UInt64) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleTapReset(event: event)
            return
        }

        let sourceUserData = event.getIntegerValueField(.eventSourceUserData)
        guard sourceUserData != switchFixEventMarker else { return }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        guard let kind = classify(type: type, event: event, keyCode: keyCode, flags: flags) else {
            return
        }

        let input = captureState.capture(
            timestamp: event.timestamp,
            kind: kind,
            keyCode: keyCode,
            flagsRawValue: flags.rawValue,
            isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            sourcePID: Int32(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID)),
            sourceUserData: sourceUserData
        )
        onInput?(input)
        let duration = DispatchTime.now().uptimeNanoseconds &- startedAt
        diagnosticRing[diagnosticRingIndex] = EventMetadata(
            sequence: input.sequence,
            timestamp: input.timestamp,
            keyCode: input.keyCode,
            flagsRawValue: input.flagsRawValue,
            isAutorepeat: input.isAutorepeat,
            sourcePID: input.sourcePID,
            sourceUserData: input.sourceUserData,
            callbackDurationNanoseconds: duration
        )
        diagnosticRingIndex = (diagnosticRingIndex + 1) % diagnosticRing.count
    }

    private func classify(
        type: CGEventType,
        event: CGEvent,
        keyCode: UInt16,
        flags: CGEventFlags
    ) -> CapturedInput.Kind? {
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            return .focusMayChange
        }

        let hotkeys = captureState.hotkeyConfiguration()
        if type == .flagsChanged {
            guard keyCode == KeyboardMonitor.capsLockKeyCode,
                  isMatchingHotkey(
                    keyCode: keyCode,
                    flags: flags,
                    configuredKeyCode: hotkeys.revertHotkeyKeyCode,
                    configuredModifiers: hotkeys.revertHotkeyModifiers
                  ) else {
                return nil
            }
            // Caps lock emits flagsChanged on both press and release with the same
            // toggled state; fire only when the alpha-shift bit actually flips so a
            // single press cannot trigger the revert hotkey twice.
            let alphaShiftEngaged = flags.contains(.maskAlphaShift)
            guard alphaShiftEngaged != lastAlphaShiftState else { return nil }
            lastAlphaShiftState = alphaShiftEngaged
            return .revertHotkey
        }

        guard type == .keyDown else { return nil }

        if isMatchingHotkey(
            keyCode: keyCode,
            flags: flags,
            configuredKeyCode: hotkeys.hotkeyKeyCode,
            configuredModifiers: hotkeys.hotkeyModifiers
        ) {
            return .hotkey
        }
        if isMatchingHotkey(
            keyCode: keyCode,
            flags: flags,
            configuredKeyCode: hotkeys.revertHotkeyKeyCode,
            configuredModifiers: hotkeys.revertHotkeyModifiers
        ) {
            return .revertHotkey
        }

        if keyCode == KeyboardMonitor.zKeyCode,
           flags.contains(.maskCommand),
           flags.intersection([.maskControl, .maskAlternate, .maskShift]).isEmpty {
            return .undo
        }

        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty ||
            KeyboardMonitor.functionKeyCodes.contains(keyCode) {
            return .navigation
        }
        if KeyboardMonitor.navigationKeyCodes.contains(keyCode) {
            return .navigation
        }
        if keyCode == KeyboardMonitor.tabKeyCode || keyCode == KeyboardMonitor.escapeKeyCode {
            return .focusMayChange
        }
        if keyCode == KeyboardMonitor.spaceKeyCode {
            return .boundary(" ")
        }
        if keyCode == KeyboardMonitor.returnKeyCode {
            return .boundary("\n")
        }
        if keyCode == KeyboardMonitor.deleteKeyCode {
            return .delete
        }

        let prefersTranslation = lifecycle.withLock { $0.prefersLayoutTranslation }
        let translated = prefersTranslation ? translations.withLock {
            $0[TranslationKey(keyCode: keyCode, shifted: flags.contains(.maskShift))]
        } : nil
        guard let text = translated ?? KeyboardMonitor.eventCharacterString(from: event) else {
            return .navigation
        }
        if text.count == 1,
           let scalar = text.unicodeScalars.first,
           KeyboardMonitor.boundaryCharacterSet.contains(scalar),
           !KeyboardMonitor.softBoundaryCharacterSet.contains(scalar) {
            return .boundary(text)
        }
        return .character(text)
    }

    private func isMatchingHotkey(
        keyCode: UInt16,
        flags: CGEventFlags,
        configuredKeyCode: UInt16,
        configuredModifiers: UInt64
    ) -> Bool {
        guard keyCode == configuredKeyCode else { return false }
        let relevantMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        return flags.intersection(relevantMask) == CGEventFlags(rawValue: configuredModifiers).intersection(relevantMask)
    }

    private static func eventCharacterString(from event: CGEvent) -> String? {
        var actualLength = 0
        var characters = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: characters.count,
            actualStringLength: &actualLength,
            unicodeString: &characters
        )
        guard actualLength > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: actualLength)
        return text.isEmpty ? nil : text
    }

    private static func translatedCharacter(
        from source: TISInputSource,
        keyCode: UInt16,
        shifted: Bool
    ) -> String? {
        guard let layoutDataReference = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataReference, to: CFData.self) as Data
        let modifierState: UInt32 = shifted ? UInt32(shiftKey >> 8) : 0
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var actualLength = 0
        // The layout pointer is only valid inside withUnsafeBytes.
        let status = layoutData.withUnsafeBytes { pointer -> OSStatus in
            guard let baseAddress = pointer.baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self),
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &actualLength,
                &characters
            )
        }
        guard status == noErr, actualLength > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: actualLength)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        monitor.handle(type: type, event: event, startedAt: startedAt)
        return Unmanaged.passUnretained(event)
    }

    deinit {
        stop()
    }
}

import Foundation
import CoreGraphics
import AppKit
import Carbon
import Utils

public protocol KeyboardMonitorDelegate: AnyObject {
    func keyboardMonitor(_ monitor: KeyboardMonitor, didReceiveCharacter character: String, keyCode: UInt16)
    func keyboardMonitor(_ monitor: KeyboardMonitor, didReceiveBoundary character: String)
    func keyboardMonitorDidReceiveDelete(_ monitor: KeyboardMonitor)
    func keyboardMonitorDidReceiveHotkey(_ monitor: KeyboardMonitor)
    func keyboardMonitorDidReceiveRevertHotkey(_ monitor: KeyboardMonitor)
    func keyboardMonitorDidReceiveUndo(_ monitor: KeyboardMonitor)
}

public class KeyboardMonitor {
    public weak var delegate: KeyboardMonitorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var selfPointer: UnsafeMutableRawPointer?
    private var isMonitoring = false

    // Key codes for special keys
    private static let spaceKeyCode: UInt16 = 49
    private static let returnKeyCode: UInt16 = 36
    private static let tabKeyCode: UInt16 = 48
    private static let escapeKeyCode: UInt16 = 53
    private static let deleteKeyCode: UInt16 = 51
    private static let capsLockKeyCode: UInt16 = 57
    private static let zKeyCode: UInt16 = 6

    // Function key range
    private static let functionKeyCodes: Set<UInt16> = Set([
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1-F12
        105, 107, 113, 106, // F13-F16
    ])

    // Arrow keys
    private static let arrowKeyCodes: Set<UInt16> = Set([123, 124, 125, 126])

    // Keys that should flush the buffer (word boundary)
    private static let bufferFlushKeyCodes: Set<UInt16> = Set([
        spaceKeyCode, returnKeyCode, tabKeyCode, escapeKeyCode
    ])

    // Boundary punctuation (excluding apostrophes and hyphen which can be part of words)
    private static let boundaryCharacterSet: CharacterSet = {
        var set = CharacterSet.punctuationCharacters.union(.symbols)
        set.subtract(CharacterSet(charactersIn: "'’`-"))
        return set
    }()

    // Punctuation keys that can represent letters in alternative layouts (e.g. "," -> "б", "." -> "ю").
    // These should stay in the buffer and be resolved by layout conversion logic.
    private static let softBoundaryCharacterSet = CharacterSet(charactersIn: ",.;'[]`<>:\"{}~")

    public init() {}

    @discardableResult
    public func start() -> Bool {
        guard !isMonitoring else { return true }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        if selfPointer == nil {
            selfPointer = Unmanaged.passRetained(self).toOpaque()
        }
        guard let selfPtr = selfPointer else {
            return false
        }

        var usedTapLocation: CGEventTapLocation?
        let tap = createEventTap(eventMask: eventMask, userInfo: selfPtr, usedTapLocation: &usedTapLocation)
        guard let tap else {
            let accessibility = Permissions.isAccessibilityGranted()
            let inputMonitoring = Permissions.isInputMonitoringGranted()
            NSLog("[SwitchFix] KeyboardMonitor: failed to create event tap (Accessibility: %@, Input Monitoring: %@)",
                  accessibility ? "granted" : "missing",
                  inputMonitoring ? "granted" : "missing")
            Unmanaged<KeyboardMonitor>.fromOpaque(selfPtr).release()
            selfPointer = nil
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        isMonitoring = true
        if usedTapLocation == .cghidEventTap {
            NSLog("[SwitchFix] KeyboardMonitor: event tap started (HID fallback)")
        } else {
            NSLog("[SwitchFix] KeyboardMonitor: event tap started")
        }
        return true
    }

    public func stop() {
        guard isMonitoring || selfPointer != nil else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isMonitoring = false
        if let selfPtr = selfPointer {
            Unmanaged<KeyboardMonitor>.fromOpaque(selfPtr).release()
            selfPointer = nil
        }
    }

    /// Temporarily disable/enable monitoring (used during text correction to avoid feedback loops)
    public var isPaused: Bool = false
    public var onKeyDownWhilePaused: (() -> Void)?

    /// Hotkey configuration
    public var hotkeyKeyCode: UInt16 = 49  // Space
    public var hotkeyModifiers: UInt64 = CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
    public var revertHotkeyKeyCode: UInt16 = KeyboardMonitor.capsLockKeyCode // CapsLock
    public var revertHotkeyModifiers: UInt64 = 0

    /// Check if a key event matches the configured hotkey.
    func isHotkey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        isMatchingHotkey(
            keyCode: keyCode,
            flags: flags,
            configuredKeyCode: hotkeyKeyCode,
            configuredModifiers: hotkeyModifiers
        )
    }

    /// Check if a key event matches the configured revert hotkey.
    func isRevertHotkey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        isMatchingHotkey(
            keyCode: keyCode,
            flags: flags,
            configuredKeyCode: revertHotkeyKeyCode,
            configuredModifiers: revertHotkeyModifiers
        )
    }

    private func isMatchingHotkey(
        keyCode: UInt16,
        flags: CGEventFlags,
        configuredKeyCode: UInt16,
        configuredModifiers: UInt64
    ) -> Bool {
        guard keyCode == configuredKeyCode else { return false }

        let requiredFlags = CGEventFlags(rawValue: configuredModifiers)
        let relevantMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        let pressedRelevant = flags.intersection(relevantMask)

        return pressedRelevant == requiredFlags.intersection(relevantMask)
    }

    private func createEventTap(
        eventMask: CGEventMask,
        userInfo: UnsafeMutableRawPointer,
        usedTapLocation: inout CGEventTapLocation?
    ) -> CFMachPort? {
        let locations: [CGEventTapLocation] = [.cgSessionEventTap, .cghidEventTap]
        for location in locations {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: KeyboardMonitor.eventTapCallback,
                userInfo: userInfo
            ) {
                usedTapLocation = location
                return tap
            }
        }
        return nil
    }

    private static func characterString(from event: CGEvent, keyCode: UInt16, flags: CGEventFlags) -> String? {
        // Prefer explicit translation via current input source. In some event tap modes
        // keyboardGetUnicodeString may return US keycap characters even when a non-Latin
        // layout is active, which breaks wrong-layout detection.
        if let fromLayout = fallbackCharacterFromCurrentLayout(keyCode: keyCode, flags: flags),
           !fromLayout.isEmpty {
            return fromLayout
        }

        let maxLen = 8
        var actualLen = 0
        var chars = [UniChar](repeating: 0, count: maxLen)
        event.keyboardGetUnicodeString(maxStringLength: maxLen, actualStringLength: &actualLen, unicodeString: &chars)

        if actualLen > 0 {
            let fromEvent = String(utf16CodeUnits: chars, count: actualLen)
            if !fromEvent.isEmpty {
                return fromEvent
            }
        }

        return nil
    }

    private static func fallbackCharacterFromCurrentLayout(keyCode: UInt16, flags: CGEventFlags) -> String? {
        let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let layoutSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let sources = [currentSource, layoutSource].compactMap { $0 }

        for source in sources {
            guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                continue
            }

            let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
            guard let keyboardLayout = layoutData.withUnsafeBytes({ ptr in
                ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            }) else {
                continue
            }

            var modifierKeyState: UInt32 = 0
            if flags.contains(.maskShift) {
                modifierKeyState |= UInt32(shiftKey >> 8)
            }

            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 8)
            var actualLength: Int = 0

            let status = UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierKeyState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &actualLength,
                &chars
            )

            if status == noErr, actualLength > 0 {
                return String(utf16CodeUnits: chars, count: actualLength)
            }
        }

        return nil
    }

    // The C-convention callback for CGEventTap
    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }

        // Handle tap being disabled by the system (e.g., due to timeout)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if type == .flagsChanged {
            if monitor.isPaused {
                return Unmanaged.passUnretained(event)
            }
            // CapsLock emits flagsChanged (not keyDown), so handle revert hotkey here.
            if keyCode == KeyboardMonitor.capsLockKeyCode, monitor.isRevertHotkey(keyCode: keyCode, flags: flags) {
                DispatchQueue.main.async {
                    monitor.delegate?.keyboardMonitorDidReceiveRevertHotkey(monitor)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        if monitor.isPaused {
            monitor.onKeyDownWhilePaused?()
            return Unmanaged.passUnretained(event)
        }

        // Check for hotkey (Ctrl+Shift+Space by default) — must check before filtering modifiers
        if monitor.isHotkey(keyCode: keyCode, flags: flags) {
            DispatchQueue.main.async {
                monitor.delegate?.keyboardMonitorDidReceiveHotkey(monitor)
            }
            return Unmanaged.passUnretained(event)
        }

        if monitor.isRevertHotkey(keyCode: keyCode, flags: flags) {
            DispatchQueue.main.async {
                monitor.delegate?.keyboardMonitorDidReceiveRevertHotkey(monitor)
            }
            return Unmanaged.passUnretained(event)
        }

        // Check for Cmd+Z (undo) — only Cmd, no other modifiers
        if keyCode == zKeyCode && flags.contains(.maskCommand) {
            let extraModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift]
            if flags.intersection(extraModifiers).isEmpty {
                DispatchQueue.main.async {
                    monitor.delegate?.keyboardMonitorDidReceiveUndo(monitor)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // Ignore events with modifier keys (Cmd, Ctrl, Option) — but allow Shift
        let modifiersToIgnore: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        if !flags.intersection(modifiersToIgnore).isEmpty {
            return Unmanaged.passUnretained(event)
        }

        // Ignore function keys
        if functionKeyCodes.contains(keyCode) {
            return Unmanaged.passUnretained(event)
        }

        // Ignore arrow keys
        if arrowKeyCodes.contains(keyCode) {
            return Unmanaged.passUnretained(event)
        }

        // Check for password fields
        if Permissions.isFocusedElementSecure() {
            return Unmanaged.passUnretained(event)
        }

        // Handle buffer flush keys (space, return, tab, escape)
        if bufferFlushKeyCodes.contains(keyCode) {
            let boundary: String
            switch keyCode {
            case spaceKeyCode: boundary = " "
            case returnKeyCode: boundary = "\n"
            case tabKeyCode: boundary = "\t"
            default: boundary = "" // Escape or unknown; don't retype
            }
            DispatchQueue.main.async {
                monitor.delegate?.keyboardMonitor(monitor, didReceiveBoundary: boundary)
            }
            return Unmanaged.passUnretained(event)
        }

        // Handle delete/backspace
        if keyCode == deleteKeyCode {
            DispatchQueue.main.async {
                monitor.delegate?.keyboardMonitorDidReceiveDelete(monitor)
            }
            return Unmanaged.passUnretained(event)
        }

        if let str = characterString(from: event, keyCode: keyCode, flags: flags) {
            if str.count == 1, let scalar = str.unicodeScalars.first,
               boundaryCharacterSet.contains(scalar),
               !softBoundaryCharacterSet.contains(scalar) {
                DispatchQueue.main.async {
                    monitor.delegate?.keyboardMonitor(monitor, didReceiveBoundary: str)
                }
            } else {
                DispatchQueue.main.async {
                    monitor.delegate?.keyboardMonitor(monitor, didReceiveCharacter: str, keyCode: keyCode)
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    deinit {
        stop()
    }
}

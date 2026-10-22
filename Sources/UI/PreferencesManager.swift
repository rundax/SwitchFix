import Foundation
import CoreGraphics
import ServiceManagement
import Core
import Utils

public enum CorrectionMode: String {
    case automatic
    case hotkey
    case layoutSwitch
}

public class PreferencesManager {
    public static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isEnabled = "SwitchFix_isEnabled"
        static let correctionMode = "SwitchFix_correctionMode"
        static let hotkeyKeyCode = "SwitchFix_hotkeyKeyCode"
        static let hotkeyModifiers = "SwitchFix_hotkeyModifiers"
        static let revertHotkeyKeyCode = "SwitchFix_revertHotkeyKeyCode"
        static let revertHotkeyModifiers = "SwitchFix_revertHotkeyModifiers"
        static let hotkeyModifierTap = "SwitchFix_hotkeyModifierTap"
        static let revertHotkeyModifierTap = "SwitchFix_revertHotkeyModifierTap"
        static let enabledLayouts = "SwitchFix_enabledLayouts"
        static let lastCyrillicLayout = "SwitchFix_lastCyrillicLayout"
        static let legacyAllowCyrillicToCyrillic = "SwitchFix_allowCyrillicToCyrillic"
    }

    public var enabledLayouts: Set<Layout> {
        get {
            guard let rawArray = defaults.stringArray(forKey: Keys.enabledLayouts) else {
                return Set(Layout.allCases)
            }
            let parsed = Set(rawArray.compactMap { Layout(rawValue: $0) })
            return parsed.isEmpty ? Set(Layout.allCases) : parsed
        }
        set {
            let sanitized = newValue.isEmpty ? Set(Layout.allCases) : newValue
            guard sanitized != self.enabledLayouts else { return }
            defaults.set(sanitized.map(\.rawValue).sorted(), forKey: Keys.enabledLayouts)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// The Cyrillic layout the user was last on. Latin text is only converted to this layout.
    public var lastCyrillicLayout: Layout? {
        get { defaults.string(forKey: Keys.lastCyrillicLayout).flatMap { Layout(rawValue: $0) }.flatMap { $0.isCyrillic ? $0 : nil } }
        set {
            guard let newValue, newValue.isCyrillic, newValue != lastCyrillicLayout else { return }
            defaults.set(newValue.rawValue, forKey: Keys.lastCyrillicLayout)
        }
    }

    /// Drops the removed Cyrillic-to-Cyrillic setting.
    public func removeLegacySettings() {
        defaults.removeObject(forKey: Keys.legacyAllowCyrillicToCyrillic)
    }

    public let exceptionsStore = PersonalExceptionsStore()

    public var personalExceptionsPolicy: PersonalExceptionsPolicy {
        exceptionsStore.loadPolicy()
    }

    /// A recoverable problem with the saved list, for a generic Settings message.
    public var personalExceptionsLoadIssue: PersonalExceptionsLoadIssue? {
        exceptionsStore.loadPolicyReportingIssue().issue
    }

    public func addPersonalException(_ candidate: String) -> AddExceptionResult {
        let result = exceptionsStore.add(candidate: candidate)
        if case .success = result {
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
        return result
    }

    @discardableResult
    public func removePersonalException(_ word: String) -> PersonalExceptionsPolicy {
        return removePersonalExceptions([word])
    }

    @discardableResult
    public func removePersonalExceptions(_ words: Set<String>) -> PersonalExceptionsPolicy {
        guard !words.isEmpty else { return exceptionsStore.loadPolicy() }
        let previous = exceptionsStore.loadPolicy()
        let policy = exceptionsStore.remove(words: words)
        if policy != previous {
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
        return policy
    }

    public var isEnabled: Bool {
        get { defaults.object(forKey: Keys.isEnabled) as? Bool ?? true }
        set {
            guard newValue != isEnabled else { return }
            defaults.set(newValue, forKey: Keys.isEnabled)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    public var launchAtLogin: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    public var launchAtLoginMessage: String? {
        guard #available(macOS 13.0, *) else { return "Launch at Login requires macOS 13 or later." }
        switch SMAppService.mainApp.status {
        case .requiresApproval:
            return "Allow SwitchFix under System Settings > General > Login Items."
        case .notFound:
            return "Move SwitchFix to Applications before enabling Launch at Login."
        default:
            return launchAtLoginError
        }
    }

    public private(set) var launchAtLoginError: String?

    public var launchAtLoginStatus: SMAppService.Status {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status }
        return .notRegistered
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            launchAtLoginError = "Launch at Login requires macOS 13 or later."
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            SwitchFixLog.preferences.error("Failed to toggle launch at login: \(error)")
        }
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    public var correctionMode: CorrectionMode {
        get {
            guard let raw = defaults.string(forKey: Keys.correctionMode),
                  let mode = CorrectionMode(rawValue: raw) else {
                return .automatic
            }
            return mode
        }
        set {
            guard newValue != self.correctionMode else { return }
            defaults.set(newValue.rawValue, forKey: Keys.correctionMode)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// Hotkey virtual key code (default: Space = 49)
    public var hotkeyKeyCode: UInt16 {
        get {
            // Key code 0 is the letter "A"; only fall back when the key is truly unset.
            guard let val = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int else { return 49 }
            return UInt16(truncatingIfNeeded: val)
        }
        set {
            guard newValue != self.hotkeyKeyCode else { return }
            defaults.set(Int(newValue), forKey: Keys.hotkeyKeyCode)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// Hotkey modifier flags as raw UInt64 (default: Ctrl+Shift)
    public var hotkeyModifiers: UInt64 {
        get {
            let val = defaults.object(forKey: Keys.hotkeyModifiers) as? UInt64
            // Default: Control + Shift
            return val ?? (CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue)
        }
        set {
            guard newValue != self.hotkeyModifiers else { return }
            defaults.set(newValue, forKey: Keys.hotkeyModifiers)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// Revert-hotkey virtual key code (default: CapsLock = 57)
    public var revertHotkeyKeyCode: UInt16 {
        get {
            // Key code 0 is the letter "A"; only fall back when the key is truly unset.
            guard let val = defaults.object(forKey: Keys.revertHotkeyKeyCode) as? Int else { return 57 }
            return UInt16(truncatingIfNeeded: val)
        }
        set {
            guard newValue != self.revertHotkeyKeyCode else { return }
            defaults.set(Int(newValue), forKey: Keys.revertHotkeyKeyCode)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// Revert-hotkey modifier flags as raw UInt64 (default: none)
    public var revertHotkeyModifiers: UInt64 {
        get {
            let val = defaults.object(forKey: Keys.revertHotkeyModifiers) as? UInt64
            return val ?? 0
        }
        set {
            guard newValue != self.revertHotkeyModifiers else { return }
            defaults.set(newValue, forKey: Keys.revertHotkeyModifiers)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// A lone modifier tap that replaces the correction key combination, such as `control.left`.
    /// Saved combinations stay untouched, so clearing the tap restores them.
    public var hotkeyModifierTap: ModifierTap? {
        get { modifierTap(forKey: Keys.hotkeyModifierTap, keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers) }
        set { setModifierTap(newValue, forKey: Keys.hotkeyModifierTap, current: hotkeyModifierTap) }
    }

    /// A lone modifier tap that replaces the revert key combination.
    public var revertHotkeyModifierTap: ModifierTap? {
        get {
            modifierTap(
                forKey: Keys.revertHotkeyModifierTap,
                keyCode: revertHotkeyKeyCode,
                modifiers: revertHotkeyModifiers
            )
        }
        set { setModifierTap(newValue, forKey: Keys.revertHotkeyModifierTap, current: revertHotkeyModifierTap) }
    }

    private func modifierTap(forKey key: String, keyCode: UInt16, modifiers: UInt64) -> ModifierTap? {
        if let stored = defaults.string(forKey: key) {
            return ModifierTap(storageValue: stored)
        }
        return ModifierTap(legacyKeyCode: keyCode, modifiers: modifiers)
    }

    private func setModifierTap(_ tap: ModifierTap?, forKey key: String, current: ModifierTap?) {
        guard tap != current else { return }
        // An empty value records "no tap", which also overrides a legacy modifier key code.
        defaults.set(tap?.storageValue ?? "", forKey: key)
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    private init() {}
}

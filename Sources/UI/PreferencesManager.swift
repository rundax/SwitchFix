import Foundation
import CoreGraphics
import ServiceManagement
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

    private init() {}
}

import Foundation
import CoreGraphics

public enum CorrectionMode: String {
    case automatic
    case hotkey
}

public class PreferencesManager {
    public static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isEnabled = "SwitchFix_isEnabled"
        static let launchAtLogin = "SwitchFix_launchAtLogin"
        static let correctionMode = "SwitchFix_correctionMode"
        static let hotkeyKeyCode = "SwitchFix_hotkeyKeyCode"
        static let hotkeyModifiers = "SwitchFix_hotkeyModifiers"
    }

    public var isEnabled: Bool {
        get { defaults.object(forKey: Keys.isEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    public var correctionMode: CorrectionMode {
        get {
            guard let raw = defaults.string(forKey: Keys.correctionMode),
                  let mode = CorrectionMode(rawValue: raw) else {
                return .automatic
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.correctionMode) }
    }

    /// Hotkey virtual key code (default: Space = 49)
    public var hotkeyKeyCode: UInt16 {
        get {
            let val = defaults.integer(forKey: Keys.hotkeyKeyCode)
            return val == 0 ? 49 : UInt16(val) // Default: space
        }
        set { defaults.set(Int(newValue), forKey: Keys.hotkeyKeyCode) }
    }

    /// Hotkey modifier flags as raw UInt64 (default: Ctrl+Shift)
    public var hotkeyModifiers: UInt64 {
        get {
            let val = defaults.object(forKey: Keys.hotkeyModifiers) as? UInt64
            // Default: Control + Shift
            return val ?? (CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue)
        }
        set { defaults.set(newValue, forKey: Keys.hotkeyModifiers) }
    }

    private init() {}
}

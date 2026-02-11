import Foundation

public enum SystemHotkeyConflicts {
    private static let capsLockKeyCode: UInt16 = 57
    private static var observedCapsLockConflictInSession = false

    public static func markObservedCapsLockConflict() {
        observedCapsLockConflictInSession = true
    }

    public static func clearObservedCapsLockConflict() {
        observedCapsLockConflictInSession = false
    }

    public static func hasCapsLockConflict(revertHotkeyKeyCode: UInt16) -> Bool {
        guard revertHotkeyKeyCode == capsLockKeyCode else { return false }
        return observedCapsLockConflictInSession
    }
}

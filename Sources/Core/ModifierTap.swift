import CoreGraphics
import Foundation

/// A shortcut made of a single modifier key pressed and released on its own (#16). It inserts no
/// character, unlike combinations such as Option+Space, so the correction never has an extra
/// character to delete.
public struct ModifierTap: Equatable, Hashable {
    public enum Key: String, CaseIterable {
        case control
        case option
        case shift
        case command
    }

    public enum Side: String, CaseIterable {
        case left
        case right
        case either
    }

    public let key: Key
    public let side: Side

    public init(key: Key, side: Side) {
        self.key = key
        self.side = side
    }

    /// The tap on exactly this physical modifier key.
    public init?(keyCode: UInt16) {
        guard let physical = Self.physicalKeys[keyCode] else { return nil }
        self.init(key: physical.key, side: physical.side)
    }

    /// Reads values written by `storageValue`, such as `control.left`.
    public init?(storageValue: String) {
        let parts = storageValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let key = Key(rawValue: String(parts[0])),
              let side = Side(rawValue: String(parts[1])) else {
            return nil
        }
        self.init(key: key, side: side)
    }

    /// A key code that is itself a modifier, saved with no modifiers, can only mean a tap of that
    /// key: modifiers never produce a key-down. Keeps `defaults write` setups from #16 working.
    public init?(legacyKeyCode: UInt16, modifiers: UInt64) {
        guard modifiers == 0 else { return nil }
        self.init(keyCode: legacyKeyCode)
    }

    public var storageValue: String { "\(key.rawValue).\(side.rawValue)" }

    public func matches(keyCode: UInt16) -> Bool {
        guard let physical = Self.physicalKeys[keyCode], physical.key == key else { return false }
        return side == .either || side == physical.side
    }

    public var displayName: String {
        let name: String
        switch key {
        case .control: name = "⌃ Control"
        case .option: name = "⌥ Option"
        case .shift: name = "⇧ Shift"
        case .command: name = "⌘ Command"
        }
        switch side {
        case .left: return "Left \(name)"
        case .right: return "Right \(name)"
        case .either: return name
        }
    }

    fileprivate struct PhysicalKey {
        let key: Key
        let side: Side
        /// NX_DEVICE*KEYMASK: the side-specific bit macOS sets while this key is down.
        let deviceMask: UInt64
    }

    fileprivate static let physicalKeys: [UInt16: PhysicalKey] = [
        59: PhysicalKey(key: .control, side: .left, deviceMask: 0x0001),
        62: PhysicalKey(key: .control, side: .right, deviceMask: 0x2000),
        58: PhysicalKey(key: .option, side: .left, deviceMask: 0x0020),
        61: PhysicalKey(key: .option, side: .right, deviceMask: 0x0040),
        56: PhysicalKey(key: .shift, side: .left, deviceMask: 0x0002),
        60: PhysicalKey(key: .shift, side: .right, deviceMask: 0x0004),
        55: PhysicalKey(key: .command, side: .left, deviceMask: 0x0008),
        54: PhysicalKey(key: .command, side: .right, deviceMask: 0x0010),
    ]
}

extension HotkeyConfiguration {
    /// True when one physical input triggers both shortcuts; the correction shortcut then wins.
    public var shortcutsOverlap: Bool {
        switch (hotkeyModifierTap, revertHotkeyModifierTap) {
        case let (correction?, revert?):
            return correction.key == revert.key &&
                (correction.side == revert.side || correction.side == .either || revert.side == .either)
        case (nil, nil):
            let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            return hotkeyKeyCode == revertHotkeyKeyCode &&
                CGEventFlags(rawValue: hotkeyModifiers).intersection(relevant) ==
                CGEventFlags(rawValue: revertHotkeyModifiers).intersection(relevant)
        default:
            return false
        }
    }
}

extension ModifierTap.Key {
    var flag: CGEventFlags {
        switch self {
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .shift: return .maskShift
        case .command: return .maskCommand
        }
    }
}

/// Recognizes a lone modifier tap: a modifier pressed with nothing else held and released within
/// `maximumHold`, with no other key, modifier, click, or tap reset in between. Not thread-safe;
/// confine each instance to one thread (the event-tap callback, or the main thread).
public struct ModifierTapDetector {
    public static let maximumHoldNanoseconds: UInt64 = 500_000_000

    private static let allDeviceMasks: UInt64 = 0x207F
    private static let chordFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn]

    private var armed: (keyCode: UInt16, pressedAt: UInt64)?

    public init() {}

    public var isArmed: Bool { armed != nil }

    /// Any non-modifier input (a key, a click, a tap reset) ends the tap.
    public mutating func cancel() {
        armed = nil
    }

    /// Feeds one `flagsChanged` event. Returns the physical key code when this event released a
    /// modifier that completed a lone tap.
    public mutating func modifierChanged(keyCode: UInt16, flagsRawValue: UInt64, timestamp: UInt64) -> UInt16? {
        guard let physical = ModifierTap.physicalKeys[keyCode] else {
            armed = nil // Caps Lock, Fn and other non-tap modifiers
            return nil
        }
        let flags = CGEventFlags(rawValue: flagsRawValue)
        let deviceBits = flagsRawValue & Self.allDeviceMasks
        let isDown = deviceBits == 0
            ? flags.contains(physical.key.flag)
            : deviceBits & physical.deviceMask != 0

        if isDown {
            if armed?.keyCode == keyCode { return nil } // repeated press event for the held key
            let alone = flags.intersection(Self.chordFlags) == physical.key.flag &&
                deviceBits & ~physical.deviceMask == 0
            armed = alone ? (keyCode, timestamp) : nil
            return nil
        }

        defer { armed = nil }
        guard let armed, armed.keyCode == keyCode,
              timestamp >= armed.pressedAt,
              timestamp - armed.pressedAt <= Self.maximumHoldNanoseconds else {
            return nil
        }
        return keyCode
    }
}

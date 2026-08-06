import Foundation
import os

public let switchFixEventMarker: Int64 = 0x53574649585F3031

public enum SecureFocusState: Equatable {
    case unknown
    case secure
    case notSecure
}

public struct InputContextSnapshot: Equatable {
    public let epoch: UInt64
    public let frontmostPID: pid_t
    public let appAllowed: Bool
    public let layout: Layout
    public let inputSourceID: String
    public let secureFocus: SecureFocusState

    public init(
        epoch: UInt64,
        frontmostPID: pid_t,
        appAllowed: Bool,
        layout: Layout,
        inputSourceID: String,
        secureFocus: SecureFocusState
    ) {
        self.epoch = epoch
        self.frontmostPID = frontmostPID
        self.appAllowed = appAllowed
        self.layout = layout
        self.inputSourceID = inputSourceID
        self.secureFocus = secureFocus
    }
}

public struct CapturedInput: Equatable {
    public enum Kind: Equatable {
        case character(String)
        case boundary(String)
        case delete
        case navigation
        case hotkey
        case revertHotkey
        case undo
        case focusMayChange
        case tapReset
        case queueOverflow
    }

    public let sequence: UInt64
    public let timestamp: UInt64
    public let kind: Kind
    public let keyCode: UInt16
    public let flagsRawValue: UInt64
    public let isAutorepeat: Bool
    public let sourcePID: Int32
    public let sourceUserData: Int64
    public let context: InputContextSnapshot
    public let editGeneration: UInt64

    public init(
        sequence: UInt64,
        timestamp: UInt64,
        kind: Kind,
        keyCode: UInt16,
        flagsRawValue: UInt64,
        isAutorepeat: Bool,
        sourcePID: Int32,
        sourceUserData: Int64,
        context: InputContextSnapshot,
        editGeneration: UInt64 = 0
    ) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.kind = kind
        self.keyCode = keyCode
        self.flagsRawValue = flagsRawValue
        self.isAutorepeat = isAutorepeat
        self.sourcePID = sourcePID
        self.sourceUserData = sourceUserData
        self.context = context
        self.editGeneration = editGeneration
    }

    func replacingKind(_ kind: Kind) -> CapturedInput {
        CapturedInput(
            sequence: sequence,
            timestamp: timestamp,
            kind: kind,
            keyCode: keyCode,
            flagsRawValue: flagsRawValue,
            isAutorepeat: isAutorepeat,
            sourcePID: sourcePID,
            sourceUserData: sourceUserData,
            context: context,
            editGeneration: editGeneration
        )
    }
}

public struct HotkeyConfiguration: Equatable {
    public let hotkeyKeyCode: UInt16
    public let hotkeyModifiers: UInt64
    public let revertHotkeyKeyCode: UInt16
    public let revertHotkeyModifiers: UInt64

    public init(
        hotkeyKeyCode: UInt16 = 49,
        hotkeyModifiers: UInt64,
        revertHotkeyKeyCode: UInt16 = 57,
        revertHotkeyModifiers: UInt64 = 0
    ) {
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.revertHotkeyKeyCode = revertHotkeyKeyCode
        self.revertHotkeyModifiers = revertHotkeyModifiers
    }
}

public struct CaptureStateSnapshot: Equatable {
    public let latestPhysicalSequence: UInt64
    public let editGeneration: UInt64
    public let context: InputContextSnapshot
    public let pendingInputCount: Int
    public let correctionAllowed: Bool

    public init(
        latestPhysicalSequence: UInt64,
        editGeneration: UInt64,
        context: InputContextSnapshot,
        pendingInputCount: Int,
        correctionAllowed: Bool
    ) {
        self.latestPhysicalSequence = latestPhysicalSequence
        self.editGeneration = editGeneration
        self.context = context
        self.pendingInputCount = pendingInputCount
        self.correctionAllowed = correctionAllowed
    }
}

public final class CaptureStateStore {
    private struct State {
        var latestPhysicalSequence: UInt64
        var editGeneration: UInt64
        var context: InputContextSnapshot
        var hotkeys: HotkeyConfiguration
        var pendingInputCount = 0
        var overloadMarkerPending = false
        var correctionAllowed = true
    }

    public enum EnqueueDecision {
        case enqueue(CapturedInput)
        case drop
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(context: InputContextSnapshot, hotkeys: HotkeyConfiguration) {
        state = OSAllocatedUnfairLock(initialState: State(
            latestPhysicalSequence: 0,
            editGeneration: 0,
            context: context,
            hotkeys: hotkeys
        ))
    }

    public func snapshot() -> CaptureStateSnapshot {
        state.withLock { value in
            CaptureStateSnapshot(
                latestPhysicalSequence: value.latestPhysicalSequence,
                editGeneration: value.editGeneration,
                context: value.context,
                pendingInputCount: value.pendingInputCount,
                correctionAllowed: value.correctionAllowed
            )
        }
    }

    public func hotkeyConfiguration() -> HotkeyConfiguration {
        state.withLock { $0.hotkeys }
    }

    public func updateHotkeys(_ hotkeys: HotkeyConfiguration) {
        state.withLock { $0.hotkeys = hotkeys }
    }

    @discardableResult
    public func replaceContext(
        frontmostPID: pid_t,
        appAllowed: Bool,
        layout: Layout,
        inputSourceID: String,
        secureFocus: SecureFocusState,
        incrementEpoch: Bool = true
    ) -> InputContextSnapshot {
        state.withLock { value in
            let epoch = incrementEpoch ? value.context.epoch &+ 1 : value.context.epoch
            let context = InputContextSnapshot(
                epoch: epoch,
                frontmostPID: frontmostPID,
                appAllowed: appAllowed,
                layout: layout,
                inputSourceID: inputSourceID,
                secureFocus: secureFocus
            )
            value.context = context
            if secureFocus != .notSecure {
                value.correctionAllowed = false
            }
            return context
        }
    }

    @discardableResult
    public func invalidateFocus() -> InputContextSnapshot {
        state.withLock { value in
            let old = value.context
            let context = InputContextSnapshot(
                epoch: old.epoch &+ 1,
                frontmostPID: old.frontmostPID,
                appAllowed: old.appAllowed,
                layout: old.layout,
                inputSourceID: old.inputSourceID,
                secureFocus: .unknown
            )
            value.context = context
            value.correctionAllowed = false
            return context
        }
    }

    @discardableResult
    public func resolveFocus(
        _ secureFocus: SecureFocusState,
        frontmostPID: pid_t,
        epoch: UInt64
    ) -> InputContextSnapshot? {
        state.withLock { value in
            guard value.context.frontmostPID == frontmostPID,
                  value.context.epoch == epoch else {
                return nil
            }
            let old = value.context
            let context = InputContextSnapshot(
                epoch: old.epoch,
                frontmostPID: old.frontmostPID,
                appAllowed: old.appAllowed,
                layout: old.layout,
                inputSourceID: old.inputSourceID,
                secureFocus: secureFocus
            )
            value.context = context
            value.correctionAllowed = secureFocus == .notSecure
            return context
        }
    }

    public func capture(
        timestamp: UInt64,
        kind: CapturedInput.Kind,
        keyCode: UInt16,
        flagsRawValue: UInt64,
        isAutorepeat: Bool,
        sourcePID: Int32,
        sourceUserData: Int64
    ) -> CapturedInput {
        state.withLock { value in
            if kind.invalidatesFocus {
                let old = value.context
                value.context = InputContextSnapshot(
                    epoch: old.epoch &+ 1,
                    frontmostPID: old.frontmostPID,
                    appAllowed: old.appAllowed,
                    layout: old.layout,
                    inputSourceID: old.inputSourceID,
                    secureFocus: .unknown
                )
                value.correctionAllowed = false
            }

            value.latestPhysicalSequence &+= 1
            if kind.isPhysicalEdit {
                value.editGeneration &+= 1
            }
            if case .tapReset = kind {
                value.correctionAllowed = false
            } else if case .boundary = kind,
                      value.context.secureFocus == .notSecure,
                      value.context.appAllowed {
                value.correctionAllowed = true
            }

            return CapturedInput(
                sequence: value.latestPhysicalSequence,
                timestamp: timestamp,
                kind: kind,
                keyCode: keyCode,
                flagsRawValue: flagsRawValue,
                isAutorepeat: isAutorepeat,
                sourcePID: sourcePID,
                sourceUserData: sourceUserData,
                context: value.context,
                editGeneration: value.editGeneration
            )
        }
    }

    public func reserveEnqueue(for input: CapturedInput, limit: Int = 256) -> EnqueueDecision {
        state.withLock { value in
            if case .boundary = input.kind {
                value.overloadMarkerPending = false
            }

            if value.pendingInputCount >= limit, input.kind.isDroppableCharacter {
                value.correctionAllowed = false
                guard !value.overloadMarkerPending else { return .drop }
                value.overloadMarkerPending = true
                value.pendingInputCount += 1
                return .enqueue(input.replacingKind(.queueOverflow))
            }

            value.pendingInputCount += 1
            return .enqueue(input)
        }
    }

    public func completeEnqueue() {
        state.withLock { value in
            value.pendingInputCount = max(0, value.pendingInputCount - 1)
        }
    }
}

private extension CapturedInput.Kind {
    var isDroppableCharacter: Bool {
        if case .character = self { return true }
        return false
    }

    var invalidatesFocus: Bool {
        switch self {
        case .navigation, .focusMayChange:
            return true
        default:
            return false
        }
    }

    var isPhysicalEdit: Bool {
        switch self {
        case .character, .boundary, .delete, .navigation, .focusMayChange:
            return true
        case .undo:
            return true
        case .hotkey, .revertHotkey, .tapReset, .queueOverflow:
            return false
        }
    }
}

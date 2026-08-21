import AppKit
import CoreGraphics
import Foundation
import os

public struct CorrectionPlan: Equatable {
    public let boundarySequence: UInt64
    public let contextEpoch: UInt64
    public let targetPID: pid_t
    public let editGeneration: UInt64
    public let correctionEpoch: UInt64
    public let deleteCount: Int
    public let replacementText: String
    public let originalText: String
    public let correctedText: String
    public let boundaryText: String
    public let originalLayout: Layout
    public let targetLayout: Layout?

    public init(
        boundarySequence: UInt64,
        contextEpoch: UInt64,
        targetPID: pid_t,
        editGeneration: UInt64,
        correctionEpoch: UInt64,
        deleteCount: Int,
        replacementText: String,
        originalText: String,
        correctedText: String,
        boundaryText: String,
        originalLayout: Layout,
        targetLayout: Layout?
    ) {
        self.boundarySequence = boundarySequence
        self.contextEpoch = contextEpoch
        self.targetPID = targetPID
        self.editGeneration = editGeneration
        self.correctionEpoch = correctionEpoch
        self.deleteCount = deleteCount
        self.replacementText = replacementText
        self.originalText = originalText
        self.correctedText = correctedText
        self.boundaryText = boundaryText
        self.originalLayout = originalLayout
        self.targetLayout = targetLayout
    }

    public func isEligible(using state: CaptureStateSnapshot) -> Bool {
        state.latestPhysicalSequence == boundarySequence &&
            state.editGeneration == editGeneration &&
            state.correctionEpoch == correctionEpoch &&
            state.context.epoch == contextEpoch &&
            state.context.frontmostPID == targetPID &&
            state.context.appAllowed &&
            state.context.secureFocus == .notSecure &&
            state.correctionAllowed
    }
}

public struct CorrectionEventDescriptor: Equatable {
    public enum Kind: Equatable {
        case deleteKeyDown
        case deleteKeyUp
        case unicodeKeyDown(String)
        case unicodeKeyUp(String)
    }

    public let kind: Kind
    public let sourceUserData: Int64
}

public final class TextCorrector {
    private struct UndoState {
        let plan: CorrectionPlan
    }

    private let inputSourceManager: InputSourceManager
    private let eventSource: CGEventSource?
    private let undoState = OSAllocatedUnfairLock<UndoState?>(initialState: nil)
    private let logger = Logger(subsystem: "com.switchfix", category: "correction")

    public init(inputSourceManager: InputSourceManager = .shared) {
        self.inputSourceManager = inputSourceManager
        let source = CGEventSource(stateID: .privateState)
        source?.userData = switchFixEventMarker
        source?.localEventsSuppressionInterval = 0
        eventSource = source
    }

    public var canUndo: Bool {
        undoState.withLock { $0 != nil }
    }

    public static func isUndoEligible(
        recordedPlan: CorrectionPlan,
        sequence: UInt64,
        context: InputContextSnapshot,
        latest: CaptureStateSnapshot
    ) -> Bool {
        latest.latestPhysicalSequence == sequence &&
            latest.editGeneration == recordedPlan.editGeneration &&
            latest.correctionEpoch == recordedPlan.correctionEpoch &&
            latest.context.frontmostPID == recordedPlan.targetPID &&
            latest.context.frontmostPID == context.frontmostPID &&
            latest.context.epoch == recordedPlan.contextEpoch &&
            latest.context.appAllowed &&
            latest.context.secureFocus == .notSecure &&
            latest.correctionAllowed
    }

    public static func eventDescriptors(for plan: CorrectionPlan) -> [CorrectionEventDescriptor] {
        guard plan.deleteCount >= 0, plan.deleteCount <= 128, !plan.replacementText.isEmpty else {
            return []
        }
        var events: [CorrectionEventDescriptor] = []
        events.reserveCapacity(plan.deleteCount * 2 + 2)
        for _ in 0..<plan.deleteCount {
            events.append(CorrectionEventDescriptor(kind: .deleteKeyDown, sourceUserData: switchFixEventMarker))
            events.append(CorrectionEventDescriptor(kind: .deleteKeyUp, sourceUserData: switchFixEventMarker))
        }
        events.append(CorrectionEventDescriptor(
            kind: .unicodeKeyDown(plan.replacementText),
            sourceUserData: switchFixEventMarker
        ))
        events.append(CorrectionEventDescriptor(
            kind: .unicodeKeyUp(plan.replacementText),
            sourceUserData: switchFixEventMarker
        ))
        return events
    }

    @discardableResult
    public func apply(
        _ plan: CorrectionPlan,
        latestCaptureState: () -> CaptureStateSnapshot
    ) -> Bool {
        guard plan.originalText.count <= 64,
              plan.deleteCount <= 128,
              let events = makeCorrectionEvents(plan: plan),
              plan.isEligible(using: latestCaptureState()) else {
            logger.debug("correction cancelled")
            return false
        }
        post(events, targetPID: plan.targetPID)

        undoState.withLock { $0 = UndoState(plan: plan) }
        if let layout = plan.targetLayout,
           plan.isEligible(using: latestCaptureState()) {
            // TIS APIs are main-thread-only; apply() runs on the correction queue.
            DispatchQueue.main.async { [inputSourceManager] in
                inputSourceManager.switchTo(layout)
            }
        }
        logger.debug("correction applied delete_count=\(plan.deleteCount, privacy: .public)")
        return true
    }

    public func noteUserEdit(generation: UInt64) {
        undoState.withLock { value in
            guard let current = value else { return }
            if current.plan.editGeneration != generation {
                value = nil
            }
        }
    }

    public func clearUndo() {
        undoState.withLock { $0 = nil }
    }

    public func rebaseUndoContext(_ context: InputContextSnapshot, editGeneration: UInt64) {
        undoState.withLock { value in
            guard let current = value,
                  current.plan.targetPID == context.frontmostPID,
                  current.plan.editGeneration == editGeneration else {
                return
            }
            let plan = current.plan
            value = UndoState(plan: CorrectionPlan(
                boundarySequence: plan.boundarySequence,
                contextEpoch: context.epoch,
                targetPID: context.frontmostPID,
                editGeneration: plan.editGeneration,
                correctionEpoch: plan.correctionEpoch,
                deleteCount: plan.deleteCount,
                replacementText: plan.replacementText,
                originalText: plan.originalText,
                correctedText: plan.correctedText,
                boundaryText: plan.boundaryText,
                originalLayout: plan.originalLayout,
                targetLayout: plan.targetLayout
            ))
        }
    }

    @discardableResult
    public func undo(
        sequence: UInt64,
        context: InputContextSnapshot,
        latestCaptureState: () -> CaptureStateSnapshot
    ) -> Bool {
        guard let undo = undoState.withLock({ $0 }) else { return false }
        let latest = latestCaptureState()
        guard Self.isUndoEligible(
            recordedPlan: undo.plan,
            sequence: sequence,
            context: context,
            latest: latest
        ) else {
            undoState.withLock { $0 = nil }
            return false
        }

        let replacement = undo.plan.originalText + undo.plan.boundaryText
        let inverse = CorrectionPlan(
            boundarySequence: sequence,
            contextEpoch: latest.context.epoch,
            targetPID: latest.context.frontmostPID,
            editGeneration: latest.editGeneration,
            correctionEpoch: latest.correctionEpoch,
            deleteCount: undo.plan.correctedText.count + undo.plan.boundaryText.count,
            replacementText: replacement,
            originalText: undo.plan.correctedText,
            correctedText: undo.plan.originalText,
            boundaryText: undo.plan.boundaryText,
            originalLayout: latest.context.layout,
            targetLayout: undo.plan.originalLayout
        )
        guard let events = makeCorrectionEvents(plan: inverse),
              inverse.isEligible(using: latestCaptureState()) else {
            return false
        }
        post(events, targetPID: inverse.targetPID)
        undoState.withLock { $0 = nil }
        if inverse.isEligible(using: latestCaptureState()) {
            let layout = undo.plan.originalLayout
            // TIS APIs are main-thread-only; undo() runs on the correction queue.
            DispatchQueue.main.async { [inputSourceManager] in
                inputSourceManager.switchTo(layout)
            }
        }
        return true
    }

    public func performSelectionCorrection(
        selectedText: String,
        convertedText: String,
        targetLayout: Layout,
        shouldSwitchLayout: Bool,
        originalLayout: Layout,
        sequence: UInt64,
        context: InputContextSnapshot,
        editGeneration: UInt64,
        correctionEpoch: UInt64,
        latestCaptureState: @escaping () -> CaptureStateSnapshot
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let latest = latestCaptureState()
            guard latest.latestPhysicalSequence == sequence,
                  latest.editGeneration == editGeneration,
                  latest.correctionEpoch == correctionEpoch,
                  latest.context.epoch == context.epoch,
                  latest.context.frontmostPID == context.frontmostPID,
                  latest.context.secureFocus == .notSecure,
                  latest.context.appAllowed,
                  latest.correctionAllowed else {
                return
            }

            let pasteboard = NSPasteboard.general
            // Snapshot item data into fresh items: items read from a pasteboard are
            // invalidated by clearContents() and cannot be written back.
            let previousItems: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        copy.setData(data, forType: type)
                    }
                }
                return copy
            }
            pasteboard.clearContents()
            pasteboard.setString(convertedText, forType: .string)
            let replacementChangeCount = pasteboard.changeCount
            self.postPaste(targetPID: context.frontmostPID)
            let afterPaste = latestCaptureState()
            if shouldSwitchLayout,
               afterPaste.latestPhysicalSequence == sequence,
               afterPaste.editGeneration == editGeneration,
               afterPaste.correctionEpoch == correctionEpoch,
               afterPaste.correctionAllowed,
               afterPaste.context == context {
                self.inputSourceManager.switchTo(targetLayout)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard pasteboard.changeCount == replacementChangeCount else { return }
                pasteboard.clearContents()
                if !previousItems.isEmpty {
                    pasteboard.writeObjects(previousItems)
                }
            }

            let plan = CorrectionPlan(
                boundarySequence: sequence,
                contextEpoch: context.epoch,
                targetPID: context.frontmostPID,
                editGeneration: editGeneration,
                correctionEpoch: correctionEpoch,
                deleteCount: selectedText.count,
                replacementText: convertedText,
                originalText: selectedText,
                correctedText: convertedText,
                boundaryText: "",
                originalLayout: originalLayout,
                targetLayout: shouldSwitchLayout ? targetLayout : nil
            )
            let finalState = latestCaptureState()
            if finalState.editGeneration == editGeneration,
               finalState.correctionEpoch == correctionEpoch,
               finalState.correctionAllowed {
                self.undoState.withLock { $0 = UndoState(plan: plan) }
            }
        }
    }

    private func makeCorrectionEvents(plan: CorrectionPlan) -> [CGEvent]? {
        guard eventSource != nil, !plan.replacementText.isEmpty else { return nil }
        var events: [CGEvent] = []
        events.reserveCapacity(plan.deleteCount * 2 + 2)
        for _ in 0..<plan.deleteCount {
            guard let keyDown = makeKeyEvent(keyCode: 51, keyDown: true),
                  let keyUp = makeKeyEvent(keyCode: 51, keyDown: false) else {
                return nil
            }
            events.append(keyDown)
            events.append(keyUp)
        }

        guard let keyDown = makeUnicodeEvent(text: plan.replacementText, keyDown: true),
              let keyUp = makeUnicodeEvent(text: plan.replacementText, keyDown: false) else {
            return nil
        }
        events.append(keyDown)
        events.append(keyUp)
        return events
    }

    private func post(_ events: [CGEvent], targetPID: pid_t) {
        for event in events {
            event.postToPid(targetPID)
        }
    }

    private func makeKeyEvent(keyCode: UInt16, keyDown: Bool) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: keyDown) else {
            return nil
        }
        event.setIntegerValueField(.eventSourceUserData, value: switchFixEventMarker)
        return event
    }

    private func makeUnicodeEvent(text: String, keyDown: Bool) -> CGEvent? {
        guard let event = makeKeyEvent(keyCode: 0, keyDown: keyDown) else { return nil }
        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        return event
    }

    private func postPaste(targetPID: pid_t) {
        guard let keyDown = makeKeyEvent(keyCode: 9, keyDown: true),
              let keyUp = makeKeyEvent(keyCode: 9, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(targetPID)
        keyUp.postToPid(targetPID)
    }
}

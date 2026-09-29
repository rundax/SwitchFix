import AppKit
import CoreGraphics
import Foundation
import os
import Utils

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
    private let logger = SwitchFixLog.corrector

    public init(inputSourceManager: InputSourceManager = .shared) {
        self.inputSourceManager = inputSourceManager
        let source = CGEventSource(stateID: .hidSystemState)
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
        let chunks = plan.replacementText.utf16Chunks(maxUnits: 20)
        events.reserveCapacity(plan.deleteCount * 2 + chunks.count * 2)
        for _ in 0..<plan.deleteCount {
            events.append(CorrectionEventDescriptor(kind: .deleteKeyDown, sourceUserData: switchFixEventMarker))
            events.append(CorrectionEventDescriptor(kind: .deleteKeyUp, sourceUserData: switchFixEventMarker))
        }
        for chunk in chunks {
            events.append(CorrectionEventDescriptor(
                kind: .unicodeKeyDown(chunk),
                sourceUserData: switchFixEventMarker
            ))
            events.append(CorrectionEventDescriptor(
                kind: .unicodeKeyUp(chunk),
                sourceUserData: switchFixEventMarker
            ))
        }
        return events
    }

    @discardableResult
    public func apply(
        _ plan: CorrectionPlan,
        latestCaptureState: @escaping () -> CaptureStateSnapshot
    ) -> Bool {
        guard Permissions.hasRequiredAccess() else { return false }
        if plan.deleteCount == 0 && plan.replacementText.isEmpty {
            guard isPlanCurrent(plan, latestCaptureState: latestCaptureState) else { return false }
            undoState.withLock { $0 = UndoState(plan: plan) }
            scheduleLayoutSwitch(for: plan, latestCaptureState: latestCaptureState)
            logger.notice(
                "correction APPLIED (layout-only) chars=\(plan.correctedText.count) deletes=0 pid=\(plan.targetPID) layoutSwitch=\(plan.targetLayout?.rawValue ?? "none")"
            )
            return true
        }

        guard plan.originalText.count <= 64,
              plan.deleteCount <= 128,
              let events = makeCorrectionEvents(plan: plan),
              Permissions.hasRequiredAccess(),
              isPlanCurrent(plan, latestCaptureState: latestCaptureState) else {
            logger.debug("apply rejected chars=\(plan.originalText.count) (oversized/no events/state changed)")
            return false
        }
        guard post(
            deletions: events.deletions,
            insertions: events.insertions,
            targetPID: plan.targetPID,
            contextEpoch: plan.contextEpoch,
            boundarySequence: plan.boundarySequence,
            editGeneration: plan.editGeneration,
            rollbackText: plan.originalText + plan.boundaryText,
            replacementText: plan.replacementText,
            latestCaptureState: latestCaptureState,
            shouldContinue: { [self] in isEmissionCurrent(plan, latestCaptureState: latestCaptureState) }
        ) else {
            logger.notice("correction emission interrupted pid=\(plan.targetPID)")
            return false
        }
        NotificationCenter.default.post(
            name: .switchFixCorrectionApplied,
            object: nil,
            userInfo: ["pid": plan.targetPID]
        )

        undoState.withLock { $0 = UndoState(plan: plan) }
        scheduleLayoutSwitch(for: plan, latestCaptureState: latestCaptureState)
        logger.notice(
            "correction APPLIED chars=\(plan.originalText.count) replacementChars=\(plan.correctedText.count) deletes=\(plan.deleteCount) pid=\(plan.targetPID) layoutSwitch=\(plan.targetLayout?.rawValue ?? "none")"
        )
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
        latestCaptureState: @escaping () -> CaptureStateSnapshot
    ) -> Bool {
        guard Permissions.hasRequiredAccess() else { return false }
        guard let undo = undoState.withLock({ $0 }) else {
            logger.info("undo skipped: no recorded correction")
            return false
        }
        let latest = latestCaptureState()
        guard Self.isUndoEligible(
            recordedPlan: undo.plan,
            sequence: sequence,
            context: context,
            latest: latest
        ) else {
            logger.info("undo skipped: state stale since correction chars=\(undo.plan.correctedText.count)")
            undoState.withLock { $0 = nil }
            return false
        }

        if undo.plan.deleteCount == 0 && undo.plan.replacementText.isEmpty {
            undoState.withLock { $0 = nil }
            if undo.plan.targetLayout != nil {
                scheduleLayoutSwitch(undo.plan.originalLayout, for: undo.plan, latestCaptureState: latestCaptureState)
            }
            logger.notice("revert APPLIED (layout-only) pid=\(undo.plan.targetPID)")
            return true
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
              Permissions.hasRequiredAccess(),
              isPlanCurrent(inverse, latestCaptureState: latestCaptureState) else {
            logger.debug("undo rejected: could not build inverse events or state changed")
            return false
        }
        guard post(
            deletions: events.deletions,
            insertions: events.insertions,
            targetPID: inverse.targetPID,
            contextEpoch: inverse.contextEpoch,
            boundarySequence: inverse.boundarySequence,
            editGeneration: inverse.editGeneration,
            rollbackText: inverse.originalText + inverse.boundaryText,
            replacementText: inverse.replacementText,
            latestCaptureState: latestCaptureState,
            shouldContinue: { [self] in isEmissionCurrent(inverse, latestCaptureState: latestCaptureState) }
        ) else {
            logger.notice("undo emission interrupted pid=\(inverse.targetPID)")
            return false
        }
        undoState.withLock { $0 = nil }
        logger.notice(
            "revert APPLIED chars=\(inverse.originalText.count) replacementChars=\(inverse.correctedText.count) deletes=\(inverse.deleteCount) pid=\(inverse.targetPID)"
        )
        if inverse.isEligible(using: latestCaptureState()) {
            let undoLayout = undo.plan.originalLayout
            scheduleLayoutSwitch(undoLayout, for: inverse, latestCaptureState: latestCaptureState)
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
            guard Permissions.hasRequiredAccess() else { return }
            let latest = latestCaptureState()
            guard latest.latestPhysicalSequence == sequence,
                  latest.editGeneration == editGeneration,
                  latest.correctionEpoch == correctionEpoch,
                  latest.context.epoch == context.epoch,
                  latest.context.frontmostPID == context.frontmostPID,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == context.frontmostPID,
                  latest.context.secureFocus == .notSecure,
                  latest.context.appAllowed,
                  Permissions.hasRequiredAccess(),
                  latest.correctionAllowed else {
                logger.debug("selection correction skipped: state changed before paste")
                return
            }

            logger.notice(
                "selection paste chars=\(selectedText.count) replacementChars=\(convertedText.count) pid=\(context.frontmostPID) layoutSwitch=\(shouldSwitchLayout ? targetLayout.rawValue : "none")"
            )
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
            NotificationCenter.default.post(
                name: .switchFixCorrectionApplied,
                object: nil,
                userInfo: ["pid": context.frontmostPID]
            )
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

    private func makeCorrectionEvents(plan: CorrectionPlan) -> (deletions: [CGEvent], insertions: [CGEvent])? {
        guard eventSource != nil, (!plan.replacementText.isEmpty || plan.deleteCount > 0) else { return nil }
        var deletions: [CGEvent] = []
        deletions.reserveCapacity(plan.deleteCount * 2)
        for _ in 0..<plan.deleteCount {
            guard let keyDown = makeKeyEvent(keyCode: 51, keyDown: true),
                  let keyUp = makeKeyEvent(keyCode: 51, keyDown: false) else {
                return nil
            }
            deletions.append(keyDown)
            deletions.append(keyUp)
        }

        let chunks = plan.replacementText.utf16Chunks(maxUnits: 20)
        var insertions: [CGEvent] = []
        insertions.reserveCapacity(chunks.count * 2)
        for chunk in chunks {
            guard let keyDown = makeUnicodeEvent(text: chunk, keyDown: true),
                  let keyUp = makeUnicodeEvent(text: chunk, keyDown: false) else {
                return nil
            }
            insertions.append(keyDown)
            insertions.append(keyUp)
        }
        return (deletions, insertions)
    }

    private func post(
        deletions: [CGEvent],
        insertions: [CGEvent],
        targetPID: pid_t,
        contextEpoch: UInt64,
        boundarySequence: UInt64,
        editGeneration: UInt64,
        rollbackText: String,
        replacementText: String,
        latestCaptureState: () -> CaptureStateSnapshot,
        shouldContinue: () -> Bool
    ) -> Bool {
        let isOwnProcess = targetPID == getpid()
        var deletedPairsPosted = 0
        var insertedCharactersPosted = 0
        let insertionChunks = replacementText.utf16Chunks(maxUnits: 20)
        for pairStart in stride(from: 0, to: deletions.count, by: 2) {
            guard shouldContinue() else {
                rollbackEmission(
                    deletedPairs: deletedPairsPosted,
                    insertedCharacters: insertedCharactersPosted,
                    originalText: rollbackText,
                    targetPID: targetPID,
                    contextEpoch: contextEpoch,
                    boundarySequence: boundarySequence,
                    editGeneration: editGeneration,
                    latestCaptureState: latestCaptureState
                )
                return false
            }
            if isOwnProcess {
                deletions[pairStart].postToPid(targetPID)
                deletions[pairStart + 1].postToPid(targetPID)
            } else {
                deletions[pairStart].post(tap: .cghidEventTap)
                deletions[pairStart + 1].post(tap: .cghidEventTap)
                // Pace between backspace key pairs; down/up events stay adjacent.
                usleep(3_000)
            }
            deletedPairsPosted += 1
        }
        if !deletions.isEmpty && !insertions.isEmpty && !isOwnProcess {
            // Settle interval between backspacing and typing replacement text to allow
            // multi-process applications (Chromium, Electron, WebKit) and rich-text web
            // editors (ProseMirror, Slate, Lexical) to complete DOM mutations and
            // selection reconciliation before receiving new text keystrokes.
            usleep(15_000)
        }
        for pairStart in stride(from: 0, to: insertions.count, by: 2) {
            guard shouldContinue() else {
                rollbackEmission(
                    deletedPairs: deletedPairsPosted,
                    insertedCharacters: insertedCharactersPosted,
                    originalText: rollbackText,
                    targetPID: targetPID,
                    contextEpoch: contextEpoch,
                    boundarySequence: boundarySequence,
                    editGeneration: editGeneration,
                    latestCaptureState: latestCaptureState
                )
                return false
            }
            if isOwnProcess {
                insertions[pairStart].postToPid(targetPID)
                insertions[pairStart + 1].postToPid(targetPID)
            } else {
                insertions[pairStart].post(tap: .cghidEventTap)
                insertions[pairStart + 1].post(tap: .cghidEventTap)
                // Keep a gap between chunks without sleeping between key-down and key-up.
                usleep(3_000)
            }
            insertedCharactersPosted += insertionChunks[pairStart / 2].count
        }
        if !insertions.isEmpty && !isOwnProcess {
            // Settle interval after replacement insertion to ensure the target
            // application's event loop (Qt in Telegram Desktop, Chromium/Electron, AppKit)
            // fully commits the inserted text before any subsequent layout switch
            // (TISSelectInputSource) resets the input context.
            usleep(20_000)
        }
        guard shouldContinue() else {
            rollbackEmission(
                deletedPairs: deletedPairsPosted,
                insertedCharacters: insertedCharactersPosted,
                originalText: rollbackText,
                targetPID: targetPID,
                contextEpoch: contextEpoch,
                boundarySequence: boundarySequence,
                editGeneration: editGeneration,
                latestCaptureState: latestCaptureState
            )
            return false
        }
        return true
    }

    private func rollbackEmission(
        deletedPairs: Int,
        insertedCharacters: Int,
        originalText: String,
        targetPID: pid_t,
        contextEpoch: UInt64,
        boundarySequence: UInt64,
        editGeneration: UInt64,
        latestCaptureState: () -> CaptureStateSnapshot
    ) {
        guard deletedPairs > 0 || insertedCharacters > 0 else { return }
        guard Permissions.hasRequiredAccess() else {
            logger.error("correction rollback skipped because required access was revoked pid=\(targetPID)")
            return
        }
        let latest = latestCaptureState()
        let sameKnownField = latest.context.frontmostPID == targetPID &&
            latest.context.epoch == contextEpoch &&
            latest.context.secureFocus == .notSecure
        let targetIsBackground = NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID
        guard sameKnownField || targetIsBackground else {
            logger.error("correction rollback skipped because target focus changed within the app pid=\(targetPID)")
            return
        }
        let physicalInputChanged = latest.latestPhysicalSequence != boundarySequence ||
            latest.editGeneration != editGeneration

        var rollbackDeletions: [CGEvent] = []
        // Do not backspace over unknown input that may have arrived between emitted chunks.
        for _ in 0..<(physicalInputChanged ? 0 : insertedCharacters) {
            guard let keyDown = makeKeyEvent(keyCode: 51, keyDown: true),
                  let keyUp = makeKeyEvent(keyCode: 51, keyDown: false) else {
                logger.error("correction rollback could not create deletion events pid=\(targetPID)")
                return
            }
            rollbackDeletions.append(keyDown)
            rollbackDeletions.append(keyUp)
        }

        let textToRestore = String(originalText.suffix(min(deletedPairs, originalText.count)))
        var rollbackInsertions: [CGEvent] = []
        for chunk in textToRestore.utf16Chunks(maxUnits: 20) {
            guard let keyDown = makeUnicodeEvent(text: chunk, keyDown: true),
                  let keyUp = makeUnicodeEvent(text: chunk, keyDown: false) else {
                logger.error("correction rollback could not create insertion events pid=\(targetPID)")
                return
            }
            rollbackInsertions.append(keyDown)
            rollbackInsertions.append(keyUp)
        }

        // Keep rollback delivery bound to the original process if another app took focus.
        // ponytail: process-level recovery is the ceiling without retaining the target AX element; revisit if edits become AX-range based.
        for pairStart in stride(from: 0, to: rollbackDeletions.count, by: 2) {
            rollbackDeletions[pairStart].postToPid(targetPID)
            rollbackDeletions[pairStart + 1].postToPid(targetPID)
            if targetPID != getpid() { usleep(3_000) }
        }
        if !rollbackDeletions.isEmpty && !rollbackInsertions.isEmpty && targetPID != getpid() {
            usleep(15_000)
        }
        for pairStart in stride(from: 0, to: rollbackInsertions.count, by: 2) {
            rollbackInsertions[pairStart].postToPid(targetPID)
            rollbackInsertions[pairStart + 1].postToPid(targetPID)
            if targetPID != getpid() { usleep(3_000) }
        }
        logger.notice(
            "correction emission interrupted; rollback posted pid=\(targetPID) deletedPairs=\(deletedPairs) removedInsertedChars=\(physicalInputChanged ? 0 : insertedCharacters)"
        )
    }

    private func isPlanCurrent(
        _ plan: CorrectionPlan,
        latestCaptureState: () -> CaptureStateSnapshot
    ) -> Bool {
        guard Permissions.hasRequiredAccess(), plan.isEligible(using: latestCaptureState()) else {
            return false
        }
        return true
    }

    private func isEmissionCurrent(
        _ plan: CorrectionPlan,
        latestCaptureState: () -> CaptureStateSnapshot
    ) -> Bool {
        isPlanCurrent(plan, latestCaptureState: latestCaptureState) && isTargetFrontmost(plan)
    }

    private func isTargetFrontmost(_ plan: CorrectionPlan) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == plan.targetPID
    }

    private func scheduleLayoutSwitch(
        for plan: CorrectionPlan,
        latestCaptureState: @escaping () -> CaptureStateSnapshot
    ) {
        guard let layout = plan.targetLayout else { return }
        scheduleLayoutSwitch(layout, for: plan, latestCaptureState: latestCaptureState)
    }

    private func scheduleLayoutSwitch(
        _ layout: Layout,
        for plan: CorrectionPlan,
        latestCaptureState: @escaping () -> CaptureStateSnapshot
    ) {
        // TIS APIs are main-thread-only; revalidate after the queue hop.
        DispatchQueue.main.async { [self] in
            guard isPlanCurrent(plan, latestCaptureState: latestCaptureState), isTargetFrontmost(plan) else { return }
            inputSourceManager.switchTo(layout)
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
        if targetPID == getpid() {
            keyDown.postToPid(targetPID)
            keyUp.postToPid(targetPID)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

extension String {
    func utf16Chunks(maxUnits: Int = 20) -> [String] {
        guard !isEmpty else { return [] }
        var chunks: [String] = []
        var currentChunk = ""
        var currentCount = 0
        for char in self {
            let charCount = char.utf16.count
            if currentCount + charCount > maxUnits && currentCount > 0 {
                chunks.append(currentChunk)
                currentChunk = ""
                currentCount = 0
            }
            currentChunk.append(char)
            currentCount += charCount
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        return chunks
    }
}

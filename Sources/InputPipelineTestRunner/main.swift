import AppKit
import Core
import CoreGraphics
import Darwin
import Foundation
import Utils

private var passed = 0
private var failed = 0

private final class DetectionRecorder {
    private let lock = NSLock()
    private var sequences: [UInt64] = []

    func record(_ sequence: UInt64) -> Int {
        lock.lock()
        defer { lock.unlock() }
        sequences.append(sequence)
        return sequences.count
    }

    func snapshot() -> [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return sequences
    }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        passed += 1
    } else {
        failed += 1
        print("FAIL: \(message)")
    }
}

private func context(
    epoch: UInt64 = 1,
    pid: pid_t = 100,
    allowed: Bool = true,
    layout: Layout = .english,
    sourceID: String = "com.test.english",
    focus: SecureFocusState = .notSecure
) -> InputContextSnapshot {
    InputContextSnapshot(
        epoch: epoch,
        frontmostPID: pid,
        appAllowed: allowed,
        layout: layout,
        inputSourceID: sourceID,
        secureFocus: focus
    )
}

private func input(
    sequence: UInt64,
    kind: CapturedInput.Kind,
    context: InputContextSnapshot,
    editGeneration: UInt64? = nil,
    autorepeat: Bool = false,
    marker: Int64 = 0
) -> CapturedInput {
    CapturedInput(
        sequence: sequence,
        timestamp: sequence,
        kind: kind,
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: autorepeat,
        sourcePID: 1,
        sourceUserData: marker,
        context: context,
        editGeneration: editGeneration ?? sequence
    )
}

private func automaticMachine(_ value: InputContextSnapshot = context()) -> InputStateMachine {
    InputStateMachine(
        context: value,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic)
    )
}

private func run(_ name: String, _ body: () -> Void) {
    print("--- \(name) ---")
    body()
}

run("ordered word") {
    let current = context()
    var machine = automaticMachine(current)
    var commands: [InputStateCommand] = []
    for (index, character) in ["c", "o", "d", "e"].enumerated() {
        commands += machine.consume(input(
            sequence: UInt64(index + 1),
            kind: .character(character),
            context: current
        ))
    }
    commands += machine.consume(input(sequence: 5, kind: .boundary(" "), context: current))
    let flushes = commands.compactMap { command -> String? in
        if case .flush(let word, _, _, _) = command { return word }
        return nil
    }
    check(flushes == ["code"], "c-o-d-e must flush exactly once and in order")
}

run("autorepeat preserved") {
    let current = context()
    var machine = automaticMachine(current)
    _ = machine.consume(input(sequence: 1, kind: .character("c"), context: current, autorepeat: true))
    _ = machine.consume(input(sequence: 2, kind: .character("c"), context: current, autorepeat: true))
    let commands = machine.consume(input(sequence: 3, kind: .boundary(" "), context: current))
    let word = commands.compactMap { command -> String? in
        if case .flush(let word, _, _, _) = command { return word }
        return nil
    }.first
    check(word == "cc", "autorepeat characters must not be deduplicated")
}

run("generated identity ignored") {
    let current = context()
    var machine = automaticMachine(current)
    _ = machine.consume(input(sequence: 1, kind: .character("a"), context: current))
    let ignored = machine.consume(input(
        sequence: 999,
        kind: .character("x"),
        context: current,
        marker: switchFixEventMarker
    ))
    check(ignored.isEmpty && machine.currentBuffer == "a", "tagged events must be ignored regardless of arrival time")
}

run("no correction pause window") {
    let current = context()
    var machine = automaticMachine(current)
    var appended: [String] = []
    for sequence in UInt64(1)...UInt64(20) {
        let character = String(UnicodeScalar(96 + Int(sequence))!)
        for command in machine.consume(input(
            sequence: sequence,
            kind: .character(character),
            context: current
        )) {
            if case .append(let value) = command { appended.append(value) }
        }
    }
    check(appended.count == 20 && appended.joined().count == 20, "physical input must remain represented exactly once")
}

run("native undo invalidates detector state") {
    let current = context()
    var machine = automaticMachine(current)
    _ = machine.consume(input(sequence: 1, kind: .character("x"), context: current))
    let commands = machine.consume(input(sequence: 2, kind: .undo, context: current))
    check(commands.contains(.nativeUndo), "Command-Z must reach the pipeline as native undo")
    check(machine.currentBuffer.isEmpty && machine.isInvalidUntilBoundary, "native undo must invalidate detector synchronization")
}

run("correction sequence and context gates") {
    let base = context()
    let plan = CorrectionPlan(
        boundarySequence: 10,
        contextEpoch: base.epoch,
        targetPID: base.frontmostPID,
        editGeneration: 10,
        correctionEpoch: 0,
        deleteCount: 5,
        replacementText: "hello ",
        originalText: "руддщ",
        correctedText: "hello",
        boundaryText: " ",
        originalLayout: .ukrainian,
        targetLayout: .english
    )
    let valid = CaptureStateSnapshot(
        latestPhysicalSequence: 10,
        editGeneration: 10,
        correctionEpoch: 0,
        context: base,
        pendingInputCount: 0,
        correctionAllowed: true
    )
    check(plan.isEligible(using: valid), "matching candidate must be eligible")
    check(!plan.isEligible(using: CaptureStateSnapshot(
        latestPhysicalSequence: 11,
        editGeneration: 11,
        correctionEpoch: 0,
        context: base,
        pendingInputCount: 0,
        correctionAllowed: true
    )), "later physical input must cancel a candidate")

    let staleContexts = [
        context(epoch: 2),
        context(pid: 101),
        context(allowed: false),
        context(epoch: 2, layout: .ukrainian, sourceID: "com.test.ukrainian"),
        context(focus: .unknown),
        context(focus: .secure),
    ]
    for stale in staleContexts {
        let state = CaptureStateSnapshot(
            latestPhysicalSequence: 10,
            editGeneration: 10,
            correctionEpoch: 0,
            context: stale,
            pendingInputCount: 0,
            correctionAllowed: true
        )
        check(!plan.isEligible(using: state), "app/layout/focus/security epoch changes must cancel candidates")
    }
    let reset = CaptureStateSnapshot(
        latestPhysicalSequence: 10,
        editGeneration: 10,
        correctionEpoch: 0,
        context: base,
        pendingInputCount: 0,
        correctionAllowed: false
    )
    check(!plan.isEligible(using: reset), "tap reset or overload must disable correction eligibility")
}

run("secure focus fails closed") {
    check(AccessibilityFocusCoordinator.classifyFocus(
        role: "AXTextField",
        subrole: "AXSecureTextField",
        subroleQueryDefinitive: true
    ) == .secure, "AX secure-text subrole must classify as secure")
    check(AccessibilityFocusCoordinator.classifyFocus(
        role: "AXTextField",
        subrole: nil,
        subroleQueryDefinitive: false
    ) == .unknown, "failed AX subrole query must remain unknown")
    check(AccessibilityFocusCoordinator.resolveFocus(
        accessibilityState: .unknown,
        secureInputEnabled: true
    ) == .secure, "secure-input mode must protect inaccessible password fields")
    check(AccessibilityFocusCoordinator.resolveFocus(
        accessibilityState: .unknown,
        secureInputEnabled: false
    ) == .notSecure, "normal inaccessible web editors must remain available")
    for focus in [SecureFocusState.unknown, .secure] {
        let current = context(focus: focus)
        var machine = automaticMachine(current)
        _ = machine.consume(input(sequence: 1, kind: .character("s"), context: current))
        check(machine.currentBuffer.isEmpty, "unknown and secure focus must never buffer text")
    }
}

run("layout-switch selection source script") {
    check(
        ScriptAnalyzer.containsScript(for: .english, in: "hello [test]"),
        "Latin selections must be eligible when switching from English"
    )
    check(
        !ScriptAnalyzer.containsScript(for: .english, in: "привіт [тест]"),
        "Cyrillic selections must not be converted as English text"
    )
    check(
        ScriptAnalyzer.containsScript(for: .ukrainian, in: "привіт [тест]"),
        "Cyrillic selections must be eligible when switching from Ukrainian"
    )
}

run("64 grapheme cap") {
    let current = context()
    var machine = automaticMachine(current)
    let grapheme = "👨‍👩‍👧‍👦"
    for sequence in UInt64(1)...UInt64(64) {
        _ = machine.consume(input(sequence: sequence, kind: .character(grapheme), context: current))
    }
    check(machine.currentBuffer.count == 64, "64 grapheme clusters must be accepted")
    let overflow = machine.consume(input(sequence: 65, kind: .character(grapheme), context: current))
    check(machine.currentBuffer.isEmpty && machine.isInvalidUntilBoundary, "65th grapheme must invalidate the buffer")
    check(overflow.contains(.invalidate(.bufferOverflow)), "overflow must emit an invalidation")
    _ = machine.consume(input(sequence: 66, kind: .boundary(" "), context: current))
    _ = machine.consume(input(sequence: 67, kind: .character("a"), context: current))
    check(machine.currentBuffer == "a", "boundary must rebuild state after overflow")
}

run("queue overload") {
    let current = context()
    let store = CaptureStateStore(
        context: current,
        hotkeys: HotkeyConfiguration(hotkeyModifiers: 0)
    )
    var overflowMarkers = 0
    for sequence in UInt64(1)...UInt64(300) {
        let captured = input(sequence: sequence, kind: .character("x"), context: current)
        switch store.reserveEnqueue(for: captured) {
        case .enqueue(let reserved):
            if reserved.kind == .queueOverflow { overflowMarkers += 1 }
        case .drop:
            break
        }
    }
    check(overflowMarkers == 1, "queue overload must enqueue one invalidation marker")
    check(!store.snapshot().correctionAllowed, "queue overload must disable correction")
    switch store.reserveEnqueue(for: input(sequence: 301, kind: .boundary(" "), context: current)) {
    case .enqueue:
        check(true, "boundary controls must not be dropped during overload")
    case .drop:
        check(false, "boundary controls must not be dropped during overload")
    }
}

run("tap reset recovery") {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    var machine = automaticMachine(current)
    let reset = store.capture(
        timestamp: 1,
        kind: .tapReset,
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    )
    _ = machine.consume(reset)
    _ = machine.consume(store.capture(
        timestamp: 2,
        kind: .character("x"),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    check(machine.currentBuffer.isEmpty && !store.snapshot().correctionAllowed, "tap reset must disable buffering and correction")
    _ = machine.consume(store.capture(
        timestamp: 3,
        kind: .boundary(" "),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    _ = machine.consume(store.capture(
        timestamp: 4,
        kind: .character("y"),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    check(machine.currentBuffer == "y" && store.snapshot().correctionAllowed, "a new boundary context must rebuild detector state after tap reset")
}

run("bounded tagged event batch") {
    let current = context()
    let plan = CorrectionPlan(
        boundarySequence: 1,
        contextEpoch: 1,
        targetPID: current.frontmostPID,
        editGeneration: 1,
        correctionEpoch: 0,
        deleteCount: 4,
        replacementText: "code ",
        originalText: "сщву",
        correctedText: "code",
        boundaryText: " ",
        originalLayout: .ukrainian,
        targetLayout: .english
    )
    let events = TextCorrector.eventDescriptors(for: plan)
    let deletes = events.filter {
        $0.kind == .deleteKeyDown || $0.kind == .deleteKeyUp
    }
    let unicode = events.filter {
        if case .unicodeKeyDown = $0.kind { return true }
        if case .unicodeKeyUp = $0.kind { return true }
        return false
    }
    check(deletes.count == 8, "N deletes must produce exactly N tagged key pairs")
    check(unicode.count == 2, "replacement must produce one Unicode key pair")
    check(events.allSatisfy { $0.sourceUserData == switchFixEventMarker }, "every generated event must carry the marker")
}

run("undo generation") {
    let originalContext = context(epoch: 4, pid: 100)
    let plan = CorrectionPlan(
        boundarySequence: 7,
        contextEpoch: 4,
        targetPID: 100,
        editGeneration: 7,
        correctionEpoch: 0,
        deleteCount: 4,
        replacementText: "code ",
        originalText: "сщву",
        correctedText: "code",
        boundaryText: " ",
        originalLayout: .ukrainian,
        targetLayout: .english
    )
    let valid = CaptureStateSnapshot(
        latestPhysicalSequence: 8,
        editGeneration: 7,
        correctionEpoch: 0,
        context: originalContext,
        pendingInputCount: 0,
        correctionAllowed: true
    )
    check(TextCorrector.isUndoEligible(
        recordedPlan: plan,
        sequence: 8,
        context: originalContext,
        latest: valid
    ), "undo must be available only in its original app, epoch, and edit generation")
    let edited = CaptureStateSnapshot(
        latestPhysicalSequence: 9,
        editGeneration: 8,
        correctionEpoch: 0,
        context: originalContext,
        pendingInputCount: 0,
        correctionAllowed: true
    )
    check(!TextCorrector.isUndoEligible(
        recordedPlan: plan,
        sequence: 9,
        context: originalContext,
        latest: edited
    ), "next physical edit must invalidate undo")
    let otherApp = context(epoch: 5, pid: 101)
    let moved = CaptureStateSnapshot(
        latestPhysicalSequence: 8,
        editGeneration: 7,
        correctionEpoch: 0,
        context: otherApp,
        pendingInputCount: 0,
        correctionAllowed: true
    )
    check(!TextCorrector.isUndoEligible(
        recordedPlan: plan,
        sequence: 8,
        context: otherApp,
        latest: moved
    ), "undo must not target a different app or context epoch")
}

run("missing dictionary seam") {
    check(!AutomaticDictionaryReadiness.prepare(.english), "missing binary dictionary must report unavailable without parsing text fallback")
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let detectionCalled = DispatchSemaphore(value: 0)
    let correctionCalled = DispatchSemaphore(value: 0)
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { _ in
            detectionCalled.signal()
            return nil
        },
        correctionEmission: { _ in
            correctionCalled.signal()
            return true
        }
    )
    engine.enqueue(store.capture(
        timestamp: 1,
        kind: .character("x"),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    engine.enqueue(store.capture(
        timestamp: 2,
        kind: .boundary(" "),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    check(detectionCalled.wait(timeout: .now() + 1) == .success, "unavailable exact detector must complete")
    check(correctionCalled.wait(timeout: .now() + 0.05) == .timedOut, "unavailable dictionary must produce no correction")
}

run("disabling invalidates queued corrections") {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let detectionEntered = DispatchSemaphore(value: 0)
    let releaseDetection = DispatchSemaphore(value: 0)
    let correctionCalled = DispatchSemaphore(value: 0)
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { request in
            detectionEntered.signal()
            _ = releaseDetection.wait(timeout: .now() + 5)
            return DetectionResult(
                sourceLayout: .english,
                targetLayout: .ukrainian,
                convertedWord: "ч",
                originalWord: request.word,
                shouldSwitchLayout: false
            )
        },
        correctionEmission: { _ in
            correctionCalled.signal()
            return true
        }
    )
    engine.enqueue(store.capture(
        timestamp: 1,
        kind: .character("x"),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    engine.enqueue(store.capture(
        timestamp: 2,
        kind: .boundary(" "),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    check(detectionEntered.wait(timeout: .now() + 1) == .success, "queued detection must start")

    let initialEpoch = store.snapshot().correctionEpoch
    engine.updatePreferences(InputPreferencesSnapshot(isEnabled: false, correctionMode: .automatic))
    let disabled = store.snapshot()
    check(!disabled.correctionAllowed, "disabling must synchronously block correction")
    check(disabled.correctionEpoch != initialEpoch, "disabling must invalidate existing correction plans")

    engine.updatePreferences(InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic))
    let reenabled = store.snapshot()
    check(reenabled.correctionEpoch != disabled.correctionEpoch, "re-enabling must not revive invalidated plans")

    releaseDetection.signal()
    check(
        correctionCalled.wait(timeout: .now() + 0.2) == .timedOut,
        "a detection queued before disable must not emit after re-enable"
    )
}

run("100,000 event stress") {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let recorder = DetectionRecorder()
    let detectionsComplete = DispatchSemaphore(value: 0)
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { request in
            if recorder.record(request.sequence) == 50_000 {
                detectionsComplete.signal()
            }
            return nil
        }
    )

    for sequence in UInt64(1)...UInt64(100_000) {
        let kind: CapturedInput.Kind = sequence.isMultiple(of: 2) ? .boundary(" ") : .character("x")
        let event = store.capture(
            timestamp: sequence,
            kind: kind,
            keyCode: 0,
            flagsRawValue: 0,
            isAutorepeat: false,
            sourcePID: 1,
            sourceUserData: 0
        )
        engine.enqueue(event)
        if sequence.isMultiple(of: 10) {
            engine.enqueue(input(
                sequence: sequence + 1_000_000,
                kind: .character("z"),
                context: current,
                marker: switchFixEventMarker
            ))
        }
        if sequence.isMultiple(of: 128) {
            let drained = DispatchSemaphore(value: 0)
            engine.drain { drained.signal() }
            check(drained.wait(timeout: .now() + 1) == .success, "engine batch must drain without loss")
        }
    }
    let drained = DispatchSemaphore(value: 0)
    engine.drain { drained.signal() }
    check(drained.wait(timeout: .now() + 1) == .success, "final engine batch must drain")
    check(detectionsComplete.wait(timeout: .now() + 30) == .success, "all boundary detections must complete")

    let sequences = recorder.snapshot()
    check(sequences.count == 50_000, "stress stream must lose or duplicate no physical words")
    check(sequences.enumerated().allSatisfy { index, sequence in
        sequence == UInt64((index + 1) * 2)
    }, "stress stream must preserve physical ordering")
    check(store.snapshot().latestPhysicalSequence == 100_000, "tagged events must not alter physical sequence")

    let inspected = DispatchSemaphore(value: 0)
    engine.inspectState { buffer, invalid, sequence in
        check(buffer.isEmpty && !invalid, "final detector state must match the physical stream")
        check(sequence == 100_000, "engine must process the final physical sequence")
        inspected.signal()
    }
    check(inspected.wait(timeout: .now() + 1) == .success, "final engine state must be observable")
}

private enum BlockedCollaborator {
    case dictionary
    case accessibility
    case correction
}

private func assertRoutingContinues(while blocked: BlockedCollaborator) {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let routed = DispatchSemaphore(value: 0)

    let detection: InputEngine.ExactDetection = { request in
        if blocked == .dictionary {
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
            return nil
        }
        return DetectionResult(
            sourceLayout: .english,
            targetLayout: .ukrainian,
            convertedWord: "ф",
            originalWord: request.word,
            shouldSwitchLayout: false
        )
    }
    let emission: InputEngine.CorrectionEmission = { _ in
        if blocked == .correction {
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
        }
        return true
    }
    let selected: InputEngine.SelectedTextRequest = { _, _, completion in
        if blocked == .accessibility {
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
        }
        completion(nil)
    }
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: detection,
        correctionEmission: emission,
        selectedTextRequest: selected
    )

    func enqueue(_ kind: CapturedInput.Kind, timestamp: UInt64) {
        engine.enqueue(store.capture(
            timestamp: timestamp,
            kind: kind,
            keyCode: 0,
            flagsRawValue: 0,
            isAutorepeat: false,
            sourcePID: 1,
            sourceUserData: 0
        ))
    }

    switch blocked {
    case .dictionary, .correction:
        enqueue(.character("a"), timestamp: 1)
        enqueue(.boundary(" "), timestamp: 2)
    case .accessibility:
        enqueue(.hotkey, timestamp: 1)
    }
    check(entered.wait(timeout: .now() + 1) == .success, "blocked collaborator must be exercised")
    enqueue(.character("b"), timestamp: 3)
    engine.drain { routed.signal() }
    check(routed.wait(timeout: .now() + 1) == .success, "input routing must not wait for blocked collaborator")
    release.signal()
}

run("blocked collaborators") {
    assertRoutingContinues(while: .dictionary)
    assertRoutingContinues(while: .accessibility)
    assertRoutingContinues(while: .correction)
}

private func runIntegrationSmoke() {
    guard Permissions.isAccessibilityGranted(), Permissions.isInputMonitoringGranted() else {
        print("SKIP: integration smoke requires Accessibility and Input Monitoring")
        return
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    application.finishLaunching()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    let textView = NSTextView(frame: window.contentView?.bounds ?? .zero)
    window.contentView = textView
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(textView)
    application.activate(ignoringOtherApps: true)
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
        print("SKIP: integration smoke could not make its NSTextView frontmost")
        window.close()
        return
    }
    textView.string = "wrong "
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

    let smokeContext = context(pid: getpid())
    let plan = CorrectionPlan(
        boundarySequence: 1,
        contextEpoch: smokeContext.epoch,
        targetPID: getpid(),
        editGeneration: 1,
        correctionEpoch: 0,
        deleteCount: 6,
        replacementText: "fixed ",
        originalText: "wrong",
        correctedText: "fixed",
        boundaryText: " ",
        originalLayout: .english,
        targetLayout: nil
    )
    let snapshot = CaptureStateSnapshot(
        latestPhysicalSequence: 1,
        editGeneration: 1,
        correctionEpoch: 0,
        context: smokeContext,
        pendingInputCount: 0,
        correctionAllowed: true
    )
    let corrector = TextCorrector()
    DispatchQueue.main.async {
        check(corrector.apply(plan, latestCaptureState: { snapshot }), "integration event batch should post")
        let utf16 = Array("x".utf16)
        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
            utf16.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            keyDown.postToPid(getpid())
            keyUp.postToPid(getpid())
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if textView.string != "fixed x" {
                print("  integration received: \(String(reflecting: textView.string))")
            }
            check(textView.string == "fixed x", "NSTextView must preserve untagged input after the correction batch")
            window.close()
            application.stop(nil)
            if let wakeEvent = NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            ) {
                application.postEvent(wakeEvent, atStart: false)
            }
        }
    }
    application.run()
}

if CommandLine.arguments.contains("--integration-smoke") {
    runIntegrationSmoke()
}

print("\nInput pipeline: \(passed) passed, \(failed) failed")
if failed > 0 {
    exit(1)
}

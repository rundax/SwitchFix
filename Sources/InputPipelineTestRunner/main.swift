import AppKit
import Core
import CoreGraphics
import Darwin
import Foundation
import IOKit.hidsystem
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

run("delete on empty buffer preserves subsequent characters") {
    let current = context()
    var machine = automaticMachine(current)
    let deleteCommands = machine.consume(input(sequence: 1, kind: .delete, context: current))
    check(!machine.isInvalidUntilBoundary, "delete on empty buffer must not invalidate until boundary")
    check(deleteCommands == [.invalidate(.navigation)], "delete on empty buffer emits navigation invalidation")
    _ = machine.consume(input(sequence: 2, kind: .character("I"), context: current))
    let flushes = machine.consume(input(sequence: 3, kind: .boundary(" "), context: current))
        .compactMap { command -> String? in
            if case .flush(let word, _, _, _) = command { return word }
            return nil
        }
    check(flushes == ["I"], "word typed after delete on empty buffer must flush")
}

run("navigation and repeated untracked deletes suppress in-word correction") {
    let current = context()
    var machine = automaticMachine(current)

    for (index, character) in ["w", "o", "r"] .enumerated() {
        _ = machine.consume(input(
            sequence: UInt64(index + 1),
            kind: .character(character),
            context: current
        ))
    }
    _ = machine.consume(input(sequence: 4, kind: .navigation, context: current))
    check(machine.isInvalidUntilBoundary, "navigation must invalidate the tracked word")
    _ = machine.consume(input(sequence: 5, kind: .character("d"), context: current))
    _ = machine.consume(input(sequence: 6, kind: .character("s"), context: current))
    check(machine.currentBuffer.isEmpty, "characters typed after navigation must stay untracked")
    check(
        machine.consume(input(sequence: 7, kind: .boundary(" "), context: current)).isEmpty,
        "boundary after navigation must not flush an in-word fragment"
    )

    _ = machine.consume(input(sequence: 8, kind: .delete, context: current))
    _ = machine.consume(input(sequence: 9, kind: .delete, context: current))
    check(machine.isInvalidUntilBoundary, "repeated deletes beyond the buffer must invalidate until boundary")
}

run("delete across boundary restores previous word and re-buffers edits") {
    let current = context()
    var machine = automaticMachine(current)
    _ = machine.consume(input(sequence: 1, kind: .character("c"), context: current))
    _ = machine.consume(input(sequence: 2, kind: .character("a"), context: current))
    _ = machine.consume(input(sequence: 3, kind: .character("t"), context: current))
    _ = machine.consume(input(sequence: 4, kind: .boundary(" "), context: current))
    let delSpace = machine.consume(input(sequence: 5, kind: .delete, context: current))
    check(delSpace == [.deleteLast], "deleting boundary emits deleteLast")
    check(machine.currentBuffer == "cat", "deleting boundary restores committed word to buffer")
    _ = machine.consume(input(sequence: 6, kind: .delete, context: current))
    check(machine.currentBuffer == "ca", "deleting character removes last character")
    _ = machine.consume(input(sequence: 7, kind: .character("r"), context: current))
    check(machine.currentBuffer == "car", "typing character appends to restored word")
    let flushes = machine.consume(input(sequence: 8, kind: .boundary(" "), context: current))
        .compactMap { command -> String? in
            if case .flush(let word, _, _, _) = command { return word }
            return nil
        }
    check(flushes == ["car"], "edited word must flush full revised word")
}

run("deleting previous word completely and typing new word") {
    let ukContext = context(layout: .ukrainian, sourceID: "com.apple.keylayout.Ukrainian")
    var machine = automaticMachine(ukContext)
    _ = machine.consume(input(sequence: 1, kind: .character("Я"), context: ukContext))
    _ = machine.consume(input(sequence: 2, kind: .boundary(" "), context: ukContext))
    _ = machine.consume(input(sequence: 3, kind: .delete, context: ukContext))
    check(machine.currentBuffer == "Я", "deleting boundary restores Я")
    _ = machine.consume(input(sequence: 4, kind: .delete, context: ukContext))
    check(machine.currentBuffer.isEmpty, "deleting character empties buffer")
    check(!machine.isInvalidUntilBoundary, "buffer must not be invalid")
    _ = machine.consume(input(sequence: 5, kind: .character("Ш"), context: ukContext))
    check(machine.currentBuffer == "Ш", "Ш must be buffered")
    let flushes = machine.consume(input(sequence: 6, kind: .boundary(" "), context: ukContext))
        .compactMap { command -> String? in
            if case .flush(let word, _, _, _) = command { return word }
            return nil
        }
    check(flushes == ["Ш"], "Ш must flush cleanly after previous word deletion")
}

private func type(_ text: String, into machine: inout InputStateMachine, from sequence: inout UInt64, context: InputContextSnapshot) {
    for character in text {
        sequence += 1
        _ = machine.consume(input(sequence: sequence, kind: .character(String(character)), context: context))
    }
}

private func press(_ kind: CapturedInput.Kind, into machine: inout InputStateMachine, from sequence: inout UInt64, context: InputContextSnapshot) -> [InputStateCommand] {
    sequence += 1
    return machine.consume(input(sequence: sequence, kind: kind, context: context))
}

run("run keeps the words typed back-to-back") {
    let current = context()
    var machine = automaticMachine(current)
    var sequence: UInt64 = 0
    type("cat", into: &machine, from: &sequence, context: current)
    _ = press(.boundary(" "), into: &machine, from: &sequence, context: current)
    type("dog", into: &machine, from: &sequence, context: current)
    _ = press(.boundary(" "), into: &machine, from: &sequence, context: current)
    check(machine.run.map(\.text) == ["cat", "dog"], "each flushed word must join the run in order")
    check(machine.run.allSatisfy { $0.boundary == " " && $0.isAnchored }, "flushed words are anchored and keep their boundary")
    check(machine.run.map(\.id) == [4, 8], "a run token is identified by the boundary that committed it")

    _ = press(.delete, into: &machine, from: &sequence, context: current)
    check(machine.currentBuffer == "dog" && machine.run.map(\.text) == ["cat"], "deleting the boundary reopens the last word and takes it off the run")
    for _ in 0..<3 { _ = press(.delete, into: &machine, from: &sequence, context: current) }
    check(machine.currentBuffer.isEmpty && machine.run.map(\.text) == ["cat"], "emptying the reopened word leaves the earlier run intact")
    let reopened = press(.delete, into: &machine, from: &sequence, context: current)
    check(reopened == [.deleteLast] && machine.currentBuffer == "cat" && machine.run.isEmpty, "the next delete reopens the word before it")
}

run("run ends wherever the screen and the journal may disagree") {
    let current = context()
    var sequence: UInt64 = 0

    var machine = automaticMachine(current)
    type("cat", into: &machine, from: &sequence, context: current)
    _ = press(.boundary(" "), into: &machine, from: &sequence, context: current)
    _ = press(.boundary(" "), into: &machine, from: &sequence, context: current)
    check(machine.run.isEmpty, "a boundary with no word before it is on screen but in no token")

    for kind in [CapturedInput.Kind.navigation, .focusMayChange, .undo, .hotkey, .revertHotkey, .tapReset, .queueOverflow] {
        machine = automaticMachine(current)
        type("cat", into: &machine, from: &sequence, context: current)
        _ = press(.boundary(" "), into: &machine, from: &sequence, context: current)
        _ = press(kind, into: &machine, from: &sequence, context: current)
        check(machine.run.isEmpty, "\(kind) must end the run")
    }

    machine = automaticMachine(current)
    type("cat", into: &machine, from: &sequence, context: current)
    _ = press(.boundary(" "), into: &machine, from: &sequence, context: current)
    _ = machine.updateContext(context(epoch: 2))
    check(machine.run.isEmpty, "a context change must end the run")
}

run("word typed after untracked deletes is held, not judged") {
    let current = context()
    var machine = automaticMachine(current)
    var sequence: UInt64 = 0
    _ = press(.delete, into: &machine, from: &sequence, context: current)
    _ = press(.delete, into: &machine, from: &sequence, context: current)
    type("asx", into: &machine, from: &sequence, context: current)
    _ = press(.delete, into: &machine, from: &sequence, context: current)
    type("k", into: &machine, from: &sequence, context: current)
    check(machine.currentBuffer.isEmpty, "a possible fragment must never enter the tracked buffer")
    let held = press(.boundary(" "), into: &machine, from: &sequence, context: current)
    check(held == [.untrackedWordHeld(length: 3)], "the fragment is held without a flush")
    check(
        machine.run == [RunToken(id: sequence, text: "ask", boundary: " ", isAnchored: false)],
        "the held word starts the run unanchored, with in-fragment deletes applied"
    )

    type("me", into: &machine, from: &sequence, context: current)
    let flushed = press(.boundary(" "), into: &machine, from: &sequence, context: current)
    check(flushed.count == 1 && machine.run.map(\.text) == ["ask", "me"], "the next word flushes with the held word before it")

    _ = press(.delete, into: &machine, from: &sequence, context: current)
    for _ in 0..<2 { _ = press(.delete, into: &machine, from: &sequence, context: current) }
    _ = press(.delete, into: &machine, from: &sequence, context: current)
    check(
        machine.isInvalidUntilBoundary && machine.currentBuffer.isEmpty && machine.run.isEmpty,
        "reopening a held word must not promote it to a tracked word"
    )
    type("s", into: &machine, from: &sequence, context: current)
    let reheld = press(.boundary(" "), into: &machine, from: &sequence, context: current)
    check(reheld == [.untrackedWordHeld(length: 4)] && machine.run.map(\.text) == ["asks"], "a reopened held word keeps recording")
}

run("held words are limited to delete-caused gaps in automatic mode") {
    let current = context()
    var sequence: UInt64 = 0

    var machine = automaticMachine(current)
    _ = press(.navigation, into: &machine, from: &sequence, context: current)
    type("ask", into: &machine, from: &sequence, context: current)
    check(press(.boundary(" "), into: &machine, from: &sequence, context: current).isEmpty && machine.run.isEmpty, "typing after navigation stays unrecorded")

    machine = automaticMachine(current)
    _ = press(.delete, into: &machine, from: &sequence, context: current)
    _ = press(.delete, into: &machine, from: &sequence, context: current)
    _ = press(.queueOverflow, into: &machine, from: &sequence, context: current)
    type("ask", into: &machine, from: &sequence, context: current)
    check(press(.boundary(" "), into: &machine, from: &sequence, context: current).isEmpty && machine.run.isEmpty, "dropped events must stop the recording")

    machine = InputStateMachine(
        context: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .hotkey)
    )
    _ = press(.delete, into: &machine, from: &sequence, context: current)
    _ = press(.delete, into: &machine, from: &sequence, context: current)
    type("ask", into: &machine, from: &sequence, context: current)
    check(press(.boundary(" "), into: &machine, from: &sequence, context: current).isEmpty && machine.run.isEmpty, "hotkey mode holds nothing")
}

run("detection request carries the preceding run") {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let lock = NSLock()
    var requests: [DetectionRequest] = []
    let detected = DispatchSemaphore(value: 0)
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { request in
            lock.lock()
            requests.append(request)
            lock.unlock()
            detected.signal()
            return nil
        },
        correctionEmission: { _ in true }
    )
    func send(_ kind: CapturedInput.Kind) {
        engine.enqueue(store.capture(
            timestamp: 0,
            kind: kind,
            keyCode: 0,
            flagsRawValue: 0,
            isAutorepeat: false,
            sourcePID: 1,
            sourceUserData: 0
        ))
    }
    send(.delete)
    send(.delete)
    for character in ["a", "s", "k"] { send(.character(character)) }
    send(.boundary(" "))
    for character in ["m", "e"] { send(.character(character)) }
    send(.boundary(" "))
    check(detected.wait(timeout: .now() + 1) == .success, "the tracked word must reach detection")
    for character in ["n", "o", "w"] { send(.character(character)) }
    send(.boundary(" "))
    check(detected.wait(timeout: .now() + 1) == .success, "the next word must reach detection")
    send(.delete)
    for character in ["s"] { send(.character(character)) }
    send(.boundary(" "))
    check(detected.wait(timeout: .now() + 1) == .success, "the reopened word must reach detection")

    lock.lock()
    let seen = requests
    lock.unlock()
    check(seen.map(\.word) == ["me", "now", "nows"], "the held word itself must never be detected on its own")
    check(
        seen.first?.precedingRun.map(\.text) == ["ask"] && seen.first?.precedingRun.first?.isAnchored == false,
        "the first tracked word must be offered the held word before it"
    )
    check(seen.dropFirst().first?.precedingRun.map(\.text) == ["ask", "me"], "each request lists the words still on screen before it")
    check(seen.last?.precedingRun.map(\.text) == ["ask", "me"], "a reopened word must not appear in its own preceding run")
}

run("manual hotkey resyncs buffer") {
    let current = context()
    var machine = automaticMachine(current)
    for (index, character) in ["g", "h", "b", "d", "t", "n"].enumerated() {
        _ = machine.consume(input(
            sequence: UInt64(index + 1),
            kind: .character(character),
            context: current
        ))
    }
    let hotkeyCommands = machine.consume(input(sequence: 7, kind: .hotkey, context: current))
    guard case .requestManualCorrection(let word?, _, _) = hotkeyCommands.first else {
        check(false, "hotkey must request manual correction with the buffered word")
        return
    }
    check(word == "ghbdtn", "hotkey must hand the buffered word to correction")
    check(machine.currentBuffer.isEmpty, "buffer must drop the word handed to correction")

    // The correction rewrites the word via tagged events the pipeline ignores,
    // so only post-hotkey typing may remain in the buffer.
    for (index, character) in ["d", "r", "u", "g"].enumerated() {
        _ = machine.consume(input(
            sequence: UInt64(8 + index),
            kind: .character(character),
            context: current
        ))
    }
    let flushed = machine.consume(input(sequence: 12, kind: .boundary(" "), context: current))
        .compactMap { command -> String? in
            if case .flush(let word, _, _, _) = command { return word }
            return nil
        }
    check(flushed == ["drug"], "stale pre-correction text must never be re-deleted at the next boundary")
}

run("revert hotkey resyncs buffer") {
    let current = context()
    var machine = automaticMachine(current)
    _ = machine.consume(input(sequence: 1, kind: .character("x"), context: current))
    let commands = machine.consume(input(sequence: 2, kind: .revertHotkey, context: current))
    guard case .requestRevert(let word?, _, _) = commands.first else {
        check(false, "revert hotkey must request revert with the buffered word")
        return
    }
    check(word == "x", "revert must hand the buffered word to the undo path")
    check(machine.currentBuffer.isEmpty, "revert must drop the buffered word to avoid desync")
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
        trigger: .automaticBoundary,
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

run("identical original and converted text avoids text deletion") {
    let current = context(focus: .notSecure)
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    var emittedPlan: CorrectionPlan?
    let correctionCalled = DispatchSemaphore(value: 0)

    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { request in
            DetectionResult(
                sourceLayout: .english,
                targetLayout: .ukrainian,
                convertedWord: request.word,
                originalWord: request.word,
                shouldSwitchLayout: true
            )
        },
        correctionEmission: { plan in
            emittedPlan = plan
            correctionCalled.signal()
            return true
        }
    )

    engine.enqueue(store.capture(
        timestamp: 1,
        kind: .character("де"),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 100,
        sourceUserData: 0
    ))
    engine.enqueue(store.capture(
        timestamp: 2,
        kind: .boundary(" "),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 100,
        sourceUserData: 0
    ))

    check(correctionCalled.wait(timeout: .now() + 1) == .success, "identical text with switch must emit plan")
    check(emittedPlan?.deleteCount == 0, "identical text must have deleteCount 0 to avoid erasing on-screen message")
    check(emittedPlan?.replacementText.isEmpty == true, "identical text must have empty replacementText")
    check(emittedPlan?.targetLayout == .ukrainian, "identical text must preserve target layout switch")

    // Verify TextCorrector handles layout-only plan without errors
    let corrector = TextCorrector()
    if let emittedPlan {
        let applied = corrector.apply(emittedPlan, latestCaptureState: store.snapshot)
        check(applied, "TextCorrector must apply layout-only plan without deleting text")
    }

    // Now test that identical text WITHOUT layout switch is completely cancelled
    let noSwitchCalled = DispatchSemaphore(value: 0)
    let noSwitchEngine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { request in
            DetectionResult(
                sourceLayout: .english,
                targetLayout: .ukrainian,
                convertedWord: request.word,
                originalWord: request.word,
                shouldSwitchLayout: false
            )
        },
        correctionEmission: { _ in
            noSwitchCalled.signal()
            return true
        }
    )

    noSwitchEngine.enqueue(store.capture(
        timestamp: 3,
        kind: .character("тест"),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 100,
        sourceUserData: 0
    ))
    noSwitchEngine.enqueue(store.capture(
        timestamp: 4,
        kind: .boundary(" "),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 100,
        sourceUserData: 0
    ))

    check(noSwitchCalled.wait(timeout: .now() + 0.05) == .timedOut, "identical text without layout switch must be cancelled")
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
        trigger: .automaticBoundary,
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
    check(unicode.count == 2, "single chunk <= 20 chars produces 1 Unicode key pair")
    check(events.allSatisfy { $0.sourceUserData == switchFixEventMarker }, "every generated event must carry the marker")

    let longPlan = CorrectionPlan(
        trigger: .automaticBoundary,
        boundarySequence: 1,
        contextEpoch: 1,
        targetPID: 100,
        editGeneration: 1,
        correctionEpoch: 0,
        deleteCount: 0,
        replacementText: "12345678901234567890EXTRA",
        originalText: "x",
        correctedText: "x",
        boundaryText: "",
        originalLayout: .english,
        targetLayout: nil
    )
    let longEvents = TextCorrector.eventDescriptors(for: longPlan)
    let longUnicode = longEvents.filter {
        if case .unicodeKeyDown = $0.kind { return true }
        if case .unicodeKeyUp = $0.kind { return true }
        return false
    }
    check(longUnicode.count == 4, "25 chars across 2 chunks must produce 2 Unicode key pairs")
}

run("undo generation") {
    let originalContext = context(epoch: 4, pid: 100)
    let plan = CorrectionPlan(
        trigger: .automaticBoundary,
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

run("SwitchFix's own layout switch keeps the correction revertable") {
    let pid: pid_t = 100
    let start = context(epoch: 4, pid: pid)
    let store = CaptureStateStore(context: start, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let corrector = TextCorrector()
    let engine = InputEngine(
        captureState: store,
        initialContext: start,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        corrector: corrector
    )
    let begin = store.snapshot()
    corrector.recordUndoForTesting(CorrectionPlan(
        trigger: .automaticBoundary,
        boundarySequence: begin.latestPhysicalSequence,
        contextEpoch: start.epoch,
        targetPID: pid,
        editGeneration: begin.editGeneration,
        correctionEpoch: begin.correctionEpoch,
        deleteCount: 7,
        replacementText: "привет ",
        originalText: "ghbdtn",
        correctedText: "привет",
        boundaryText: " ",
        originalLayout: .english,
        targetLayout: .russian
    ))

    // Mirrors AppDelegate: willSelect, then the input source notification, which refreshes the
    // detection configuration (a new correction epoch) before publishing the generated context.
    let willSelect = store.replaceContext(
        frontmostPID: pid, appAllowed: true, layout: .russian,
        inputSourceID: "com.test.russian", secureFocus: .unknown
    )
    engine.handleGeneratedLayoutContext(willSelect)
    let notified = store.replaceContext(
        frontmostPID: pid, appAllowed: true, layout: .russian,
        inputSourceID: "com.test.russian", secureFocus: .unknown
    )
    engine.updateDetectionConfiguration(
        allowedLayouts: [.english, .russian],
        ukrainianFromVariant: .standard,
        ukrainianToVariant: .standard
    )
    engine.handleGeneratedLayoutContext(notified)
    guard let resolved = store.resolveFocus(.notSecure, frontmostPID: pid, epoch: notified.epoch) else {
        check(false, "focus for the generated context must resolve")
        return
    }
    engine.updateContext(resolved)
    let drained = DispatchSemaphore(value: 0)
    engine.drainPipeline { drained.signal() }
    _ = drained.wait(timeout: .now() + 2)

    let revert = store.capture(
        timestamp: 1, kind: .revertHotkey, keyCode: 57, flagsRawValue: 0,
        isAutorepeat: false, sourcePID: 1, sourceUserData: 0
    )
    guard let recorded = corrector.recordedUndoPlan else {
        check(false, "the generated switch must keep the undo record")
        return
    }
    check(TextCorrector.isUndoEligible(
        recordedPlan: recorded,
        sequence: revert.sequence,
        context: resolved,
        latest: store.snapshot()
    ), "the revert hotkey must still undo a correction after SwitchFix's own layout switch")

    engine.updatePreferences(InputPreferencesSnapshot(isEnabled: false, correctionMode: .automatic))
    check(!TextCorrector.isUndoEligible(
        recordedPlan: recorded,
        sequence: revert.sequence,
        context: resolved,
        latest: store.snapshot()
    ), "disabling SwitchFix must still make the correction unrevertable")
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

run("access revocation invalidates queued corrections") {
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
    engine.enqueue(store.capture(timestamp: 1, kind: .character("x"), keyCode: 0, flagsRawValue: 0, isAutorepeat: false, sourcePID: 1, sourceUserData: 0))
    engine.enqueue(store.capture(timestamp: 2, kind: .boundary(" "), keyCode: 0, flagsRawValue: 0, isAutorepeat: false, sourcePID: 1, sourceUserData: 0))
    check(detectionEntered.wait(timeout: .now() + 1) == .success, "queued detection must start before access loss")

    let originalEpoch = store.snapshot().correctionEpoch
    engine.updateAccessAllowed(false)
    let revoked = store.snapshot()
    check(!revoked.correctionAllowed, "revoked access must synchronously block correction")
    check(revoked.correctionEpoch != originalEpoch, "revoked access must invalidate existing plans")
    engine.updateAccessAllowed(true)
    check(store.snapshot().correctionEpoch != revoked.correctionEpoch, "restored access must not revive stale plans")

    releaseDetection.signal()
    check(correctionCalled.wait(timeout: .now() + 0.2) == .timedOut, "a detection queued before access loss must not emit after recovery")
}

run("effective listening access does not verify the Input Monitoring toggle") {
    check(RuntimeReadinessSnapshot().keyboardListeningStatus == .checking, "unchecked keyboard access must remain checking")
    // Real macOS reproduction: only the Accessibility TCC row exists, yet even
    // IOHIDCheckAccess(ListenEvent) returns Granted. Mock that actual result below,
    // not the incorrect assumption that a missing ListenEvent row returns Unknown.
    for access in [kIOHIDAccessTypeUnknown, kIOHIDAccessTypeDenied, kIOHIDAccessTypeGranted] {
        var checkedListenEvent = false
        let granted = Permissions.isKeyboardListeningAvailable { requestType in
            checkedListenEvent = requestType == kIOHIDRequestTypeListenEvent
            return access
        }
        check(checkedListenEvent, "listening capability must query ListenEvent")
        check(granted == (access == kIOHIDAccessTypeGranted), "only Granted indicates effective listening capability")

        var readiness = RuntimeReadinessSnapshot()
        readiness.checked = true
        readiness.accessibilityGranted = true
        readiness.postingGranted = true
        readiness.keyboardListeningAvailable = granted
        if !granted {
            check(readiness.missingPermissions == ["Input Monitoring"], "unavailable listening access must retain Input Monitoring guidance")
            check(readiness.status == .setupNeeded && readiness.needsSetup, "unavailable listening capability must keep setup open")
            check(!readiness.hasRequiredAccess && !readiness.canTryCorrection, "unavailable listening capability must block correction")
            check(readiness.keyboardListeningStatus == .unavailable, "unavailable keyboard access must retain Settings guidance")
        } else {
            check(readiness.missingPermissions.isEmpty, "effective access clears runtime permission blockers")
            check(readiness.hasRequiredAccess, "effective authorization can support correction without a separate ListenEvent row")
            check(readiness.keyboardListeningStatus == .available, "effective keyboard access must not be permanently marked unverified")
            check(readiness.keyboardListeningStatus.label == "Available", "capability label must describe access, not claim the Input Monitoring toggle is Allowed")
            check(readiness.keyboardListeningStatus.symbolName == "checkmark.circle.fill", "verified runtime access must show its completed capability state")
            readiness.accessibilityGranted = false
            check(readiness.keyboardListeningStatus == .available, "keyboard access remains a separate capability from Accessibility")
            check(!readiness.setupComplete, "keyboard access alone cannot complete setup")
        }
    }

    for result in [false, true] {
        var requestedListenEvent = false
        let granted = Permissions.requestKeyboardListeningAccess { requestType in
            requestedListenEvent = requestType == kIOHIDRequestTypeListenEvent
            return result
        }
        check(requestedListenEvent, "listening requests must address ListenEvent")
        check(granted == result, "requests must preserve the effective authorization result, not assert toggle membership")
    }
}

run("readiness states reflect permission and mode prerequisites") {
    var readiness = RuntimeReadinessSnapshot()
    check(readiness.status == .checking, "unknown runtime state must remain checking")

    readiness.checked = true
    readiness.accessibilityGranted = true
    check(readiness.status == .setupNeeded, "missing Input Monitoring keeps setup blocked")
    check(readiness.missingPermissions == ["Input Monitoring"], "only the missing required grant is listed")

    readiness.keyboardListeningAvailable = true
    readiness.postingGranted = false
    check(readiness.status == .needsAttention, "posting capability failure is not a third permission category")

    readiness.postingGranted = true
    readiness.monitor = .active
    readiness.installedLayouts = [.english, .russian]
    readiness.dictionaryLayouts = [.english, .russian]
    readiness.dictionariesLoaded = true
    readiness.appAllowed = true
    readiness.secureFocus = .notSecure
    readiness.sourceSupported = true
    check(readiness.status == .working, "working requires effective access, monitor, dictionaries, and a supported context")
    check(readiness.canTryCorrection, "an unverified separate toggle must not block an operational typing test")
    check(readiness.setupComplete, "a working runtime must show Setup complete rather than perpetual Check in Settings")
    check(readiness.keyboardListeningStatus == .available, "a working runtime must show keyboard input access as Available")

    readiness.runtimeFailure = "Keyboard monitoring keeps stopping."
    check(readiness.status == .needsAttention && readiness.message == readiness.runtimeFailure, "persistent runtime failures remain visible")
    readiness.runtimeFailure = nil

    readiness.mode = .hotkey
    readiness.dictionaryLayouts = []
    readiness.dictionariesLoaded = false
    check(readiness.status == .working, "manual correction mode does not depend on automatic dictionaries")

    var retries = MonitorRetryBudget()
    check(retries.canAttempt, "monitor retry begins available")
    retries.recordFailure()
    retries.recordFailure()
    check(retries.canAttempt, "monitor retries remain available within the bounded budget")
    retries.recordFailure()
    check(!retries.canAttempt, "monitor retries stop after three failures")
    retries.reset()
    check(retries.canAttempt, "explicit recovery resets the retry budget")
}

run("setup completion follows live access and survives temporary pauses") {
    var readiness = RuntimeReadinessSnapshot()
    check(!readiness.setupComplete, "unchecked setup cannot be complete")
    readiness.checked = true
    readiness.accessibilityGranted = true
    readiness.keyboardListeningAvailable = true
    readiness.installedLayouts = [.english, .russian]
    readiness.dictionaryLayouts = [.english, .russian]
    readiness.dictionariesLoaded = true
    check(!readiness.setupComplete, "Accessibility with listening access but no posting must not complete setup")

    // Match the reported relaunch: permissions authorized, posting ready, tap active.
    readiness.postingGranted = true
    check(!readiness.setupComplete, "authorized permissions with a stopped monitor are not complete")
    readiness.monitor = .active
    check(readiness.setupComplete, "authorized access plus a live monitor and prerequisites completes setup")
    check(!readiness.needsSetup, "completed setup must not reopen missing-permission guidance")
    check(readiness.status == .paused, "a disallowed frontmost context only pauses correction")
    check(readiness.setupComplete, "a temporary app/focus pause must not undo completed setup")

    readiness.isEnabled = false
    check(readiness.setupComplete && !readiness.canTryCorrection, "user-disabled correction retains setup completion but blocks the exercise")
    readiness.isEnabled = true
    readiness.runtimeFailure = "Monitor stopped"
    check(!readiness.setupComplete, "a runtime failure clears completion")
    readiness.runtimeFailure = nil
    readiness.monitor = .failed
    check(!readiness.setupComplete, "monitor failure clears completion")
    readiness.monitor = .active
    readiness.keyboardListeningAvailable = false
    check(!readiness.setupComplete && readiness.keyboardListeningStatus == .unavailable, "Check Again must reflect live access revocation")
    readiness.keyboardListeningAvailable = true
    check(readiness.setupComplete, "Check Again must restore completion after access returns")
    readiness.accessibilityGranted = false
    check(!readiness.setupComplete, "revoked Accessibility clears completion even with input access")
    readiness.accessibilityGranted = true
    readiness.dictionariesLoaded = false
    check(!readiness.setupComplete, "automatic mode waits for dictionaries")
    readiness.mode = .hotkey
    check(readiness.setupComplete, "manual mode does not require automatic dictionaries")
    readiness.installedLayouts = [.english]
    check(!readiness.setupComplete, "setup still requires two supported layouts")
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
            check(drained.wait(timeout: .now() + 3) == .success, "engine batch must drain without loss")
        }
    }
    let drained = DispatchSemaphore(value: 0)
    engine.drain { drained.signal() }
    check(drained.wait(timeout: .now() + 3) == .success, "final engine batch must drain")
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

run("drainPipeline and request assembly") {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    var emissionCalled = false
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { request in
            check(request.word == "test", "assembled word must match")
            check(request.boundary == " ", "assembled boundary must match")
            return DetectionResult(
                sourceLayout: .english,
                targetLayout: .ukrainian,
                convertedWord: "тест",
                originalWord: request.word,
                shouldSwitchLayout: false
            )
        },
        correctionEmission: { plan in
            emissionCalled = true
            return true
        }
    )

    engine.enqueue(store.capture(timestamp: 1, kind: .character("t"), keyCode: 17, flagsRawValue: 0, isAutorepeat: false, sourcePID: 1, sourceUserData: 0))
    engine.enqueue(store.capture(timestamp: 2, kind: .character("e"), keyCode: 14, flagsRawValue: 0, isAutorepeat: false, sourcePID: 1, sourceUserData: 0))
    engine.enqueue(store.capture(timestamp: 3, kind: .character("s"), keyCode: 1, flagsRawValue: 0, isAutorepeat: false, sourcePID: 1, sourceUserData: 0))
    engine.enqueue(store.capture(timestamp: 4, kind: .character("t"), keyCode: 17, flagsRawValue: 0, isAutorepeat: false, sourcePID: 1, sourceUserData: 0))
    engine.enqueue(store.capture(timestamp: 5, kind: .boundary(" "), keyCode: 49, flagsRawValue: 0, isAutorepeat: false, sourcePID: 1, sourceUserData: 0))

    let drained = DispatchSemaphore(value: 0)
    engine.drainPipeline {
        drained.signal()
    }
    check(drained.wait(timeout: .now() + 2) == .success, "drainPipeline must hop all queues and complete")
    check(emissionCalled, "drainPipeline must guarantee all correction stages have executed")
}

run("personal exceptions pipeline integration and invalidation") {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    var emissionCount = 0
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { request in
            return DetectionResult(
                sourceLayout: .english,
                targetLayout: .ukrainian,
                convertedWord: "тест",
                originalWord: request.word,
                shouldSwitchLayout: false
            )
        },
        correctionEmission: { plan in
            emissionCount += 1
            return true
        }
    )

    // Set personal exceptions containing "protected"
    engine.updatePersonalExceptions(PersonalExceptionsPolicy(words: ["protected"]))
    let drained1 = DispatchSemaphore(value: 0)
    engine.drainPipeline { drained1.signal() }
    check(drained1.wait(timeout: .now() + 2) == .success, "pipeline drain after exception update")

    // 1. Enqueue protected word "protected "
    for (idx, char) in "protected".enumerated() {
        engine.enqueue(store.capture(timestamp: UInt64(idx + 1), kind: .character(String(char)), keyCode: 0, flagsRawValue: 0, isAutorepeat: false, sourcePID: 1, sourceUserData: 0))
    }
    engine.enqueue(store.capture(timestamp: 10, kind: .boundary(" "), keyCode: 49, flagsRawValue: 0, isAutorepeat: false, sourcePID: 1, sourceUserData: 0))

    let drained2 = DispatchSemaphore(value: 0)
    engine.drainPipeline { drained2.signal() }
    check(drained2.wait(timeout: .now() + 2) == .success, "pipeline drain after protected word")
    check(emissionCount == 0, "protected word must not emit correction even with exactDetection")

    // 2. Invalidate configuration increments epoch without changing enabled state
    let initialEpoch = store.snapshot().correctionEpoch
    let newEpoch = store.invalidateCorrectionConfiguration()
    check(newEpoch == initialEpoch + 1, "invalidateCorrectionConfiguration must increment epoch")
    check(store.snapshot().correctionAllowed, "enabled state remains allowed after invalidation")

    // A plan created with old epoch must not be eligible
    let stalePlan = CorrectionPlan(
        trigger: .automaticBoundary,
        boundarySequence: 10,
        contextEpoch: current.epoch,
        targetPID: current.frontmostPID,
        editGeneration: 10,
        correctionEpoch: initialEpoch,
        deleteCount: 4,
        replacementText: "test ",
        originalText: "тест",
        correctedText: "test",
        boundaryText: " ",
        originalLayout: .ukrainian,
        targetLayout: .english
    )
    check(!stalePlan.isEligible(using: store.snapshot()), "plan with stale epoch must fail isEligible")

    // 3. Exception and layout configuration updates invalidate in-flight correction before emission.
    for updateLayoutConfiguration in [false, true] {
        let addStore = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
        var addEmissionCount = 0
        let detectionStarted = DispatchSemaphore(value: 0)
        let releaseDetection = DispatchSemaphore(value: 0)
        let engine2 = InputEngine(
            captureState: addStore,
            initialContext: current,
            preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
            exactDetection: { request in
                detectionStarted.signal()
                _ = releaseDetection.wait(timeout: .now() + 5)
                return DetectionResult(
                    sourceLayout: .english,
                    targetLayout: .ukrainian,
                    convertedWord: "тест",
                    originalWord: request.word,
                    shouldSwitchLayout: false
                )
            },
            correctionEmission: { _ in
                addEmissionCount += 1
                return true
            }
        )

        // Type word "test "
        engine2.enqueue(addStore.capture(timestamp: 1, kind: .character("t"), keyCode: 0, flagsRawValue: 0, isAutorepeat: false, sourcePID: 1, sourceUserData: 0))
        engine2.enqueue(addStore.capture(timestamp: 2, kind: .boundary(" "), keyCode: 49, flagsRawValue: 0, isAutorepeat: false, sourcePID: 1, sourceUserData: 0))

        check(detectionStarted.wait(timeout: .now() + 1) == .success, "detection started")
        if updateLayoutConfiguration {
            engine2.updateDetectionConfiguration(
                allowedLayouts: [.english],
                ukrainianFromVariant: .standard,
                ukrainianToVariant: .standard
            )
        } else {
            engine2.updatePersonalExceptions(PersonalExceptionsPolicy(words: ["newexception"]))
        }
        releaseDetection.signal()

        let drained3 = DispatchSemaphore(value: 0)
        engine2.drainPipeline { drained3.signal() }
        check(drained3.wait(timeout: .now() + 2) == .success, "pipeline drained after mid-flight configuration update")
        check(addEmissionCount == 0, "in-flight correction must be invalidated by configuration update")
    }
}

private final class ExceptionPipelineHarness {
    private final class Recorder {
        private let lock = NSLock()
        private var plans: [CorrectionPlan] = []
        private var selections: [(CorrectionTrigger, String)] = []

        func record(_ plan: CorrectionPlan) {
            lock.lock(); defer { lock.unlock() }
            plans.append(plan)
        }

        func record(_ trigger: CorrectionTrigger, _ selectedText: String) {
            lock.lock(); defer { lock.unlock() }
            selections.append((trigger, selectedText))
        }

        func snapshot() -> (plans: [CorrectionPlan], selections: [(CorrectionTrigger, String)]) {
            lock.lock(); defer { lock.unlock() }
            return (plans, selections)
        }
    }

    let store: CaptureStateStore
    let engine: InputEngine
    private let recorder = Recorder()
    private let selectionEmitted = DispatchSemaphore(value: 0)
    private var timestamp: UInt64 = 0

    var plans: [CorrectionPlan] { recorder.snapshot().plans }
    var selections: [(CorrectionTrigger, String)] { recorder.snapshot().selections }

    init(
        mode: InputCorrectionMode,
        focus: SecureFocusState = .notSecure,
        selectedText: String? = nil,
        detectionStarted: DispatchSemaphore? = nil,
        releaseDetection: DispatchSemaphore? = nil
    ) {
        let current = context(focus: focus)
        let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
        let recorder = self.recorder
        let selectionEmitted = self.selectionEmitted
        self.store = store
        engine = InputEngine(
            captureState: store,
            initialContext: current,
            preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: mode),
            exactDetection: { request in
                detectionStarted?.signal()
                if let releaseDetection { _ = releaseDetection.wait(timeout: .now() + 5) }
                return DetectionResult(
                    sourceLayout: .english,
                    targetLayout: .ukrainian,
                    convertedWord: "тест",
                    originalWord: request.word,
                    shouldSwitchLayout: false
                )
            },
            correctionEmission: { plan in
                recorder.record(plan)
                return true
            },
            selectedTextRequest: selectedText.map { text in
                { _, _, completion in completion(text) }
            },
            selectionEmission: { trigger, selected, _ in
                recorder.record(trigger, selected)
                selectionEmitted.signal()
            }
        )
    }

    func enqueue(_ kind: CapturedInput.Kind) {
        timestamp += 1
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

    func type(_ text: String) {
        for character in text { enqueue(.character(String(character))) }
    }

    /// Selected-text correction hops through the selection queue, which `drainPipeline` does not cover.
    func waitForSelection() -> Bool {
        selectionEmitted.wait(timeout: .now() + 2) == .success
    }

    func drain() -> Bool {
        let done = DispatchSemaphore(value: 0)
        engine.drainPipeline { done.signal() }
        return done.wait(timeout: .now() + 2) == .success
    }

    func switchSource(to layout: Layout) {
        let previous = store.snapshot().context
        let next = store.replaceContext(
            frontmostPID: previous.frontmostPID,
            appAllowed: previous.appAllowed,
            layout: layout,
            inputSourceID: "com.test.\(layout.rawValue)",
            secureFocus: previous.secureFocus
        )
        engine.updateDetectionConfiguration(
            allowedLayouts: [.english, .ukrainian],
            activeSourceSupportedLayouts: [layout],
            ukrainianFromVariant: .standard,
            ukrainianToVariant: .standard
        )
        engine.handleLayoutChange(from: previous.layout, to: layout, context: next, fromVariant: .standard, toVariant: .standard)
    }
}

run("configuration change keeps the next word") {
    let current = context()
    func flushes(_ commands: [InputStateCommand]) -> [String] {
        commands.compactMap { command -> String? in
            if case .flush(let word, _, _, _) = command { return word }
            return nil
        }
    }

    var idle = automaticMachine(current)
    idle.resetForConfigurationChange()
    var commands: [InputStateCommand] = []
    for (index, character) in "next".enumerated() {
        commands += idle.consume(input(sequence: UInt64(index + 1), kind: .character(String(character)), context: current))
    }
    commands += idle.consume(input(sequence: 10, kind: .boundary(" "), context: current))
    check(flushes(commands) == ["next"], "with nothing in progress, the next word after a configuration change is judged")

    var midWord = automaticMachine(current)
    _ = midWord.consume(input(sequence: 1, kind: .character("p"), context: current))
    _ = midWord.consume(input(sequence: 2, kind: .character("a"), context: current))
    midWord.resetForConfigurationChange()
    commands = []
    for (index, character) in "rt".enumerated() {
        commands += midWord.consume(input(sequence: UInt64(index + 3), kind: .character(String(character)), context: current))
    }
    commands += midWord.consume(input(sequence: 5, kind: .boundary(" "), context: current))
    for (index, character) in "next".enumerated() {
        commands += midWord.consume(input(sequence: UInt64(index + 6), kind: .character(String(character)), context: current))
    }
    commands += midWord.consume(input(sequence: 10, kind: .boundary(" "), context: current))
    check(flushes(commands) == ["next"], "a word in progress is skipped to its boundary, never judged as a fragment")
}

run("personal exceptions: explicit triggers bypass, automatic stays blocked") {
    let protected = PersonalExceptionsPolicy(words: ["protected"])

    let automatic = ExceptionPipelineHarness(mode: .automatic)
    automatic.engine.updatePersonalExceptions(protected)
    // No drain here: the published policy must precede input enqueued right after it.
    automatic.type("protected")
    automatic.enqueue(.boundary(" "))
    check(automatic.drain(), "automatic pipeline drains")
    check(automatic.plans.isEmpty, "configuration published before new input blocks the automatic correction")
    automatic.type("protected")
    automatic.enqueue(.hotkey)
    check(automatic.drain(), "hotkey pipeline drains")
    check(automatic.plans.map(\.trigger) == [.hotkey], "hotkey correction of a protected word is applied")
    check(automatic.plans.first?.originalText == "protected", "hotkey correction converts the protected word itself")

    let layoutSwitch = ExceptionPipelineHarness(mode: .layoutSwitch)
    layoutSwitch.engine.updatePersonalExceptions(protected)
    layoutSwitch.type("protected")
    check(layoutSwitch.drain(), "layout-switch input drains before the source changes")
    layoutSwitch.switchSource(to: .ukrainian)
    check(layoutSwitch.drain(), "layout-switch pipeline drains")
    check(layoutSwitch.plans.map(\.trigger) == [.layoutSwitch], "On Layout Switch correction of a protected word is applied")
    check(layoutSwitch.plans.first?.originalText == "protected", "layout-switch correction converts the buffered protected word")

    let selection = ExceptionPipelineHarness(mode: .automatic, selectedText: "protected")
    selection.engine.updatePersonalExceptions(protected)
    selection.enqueue(.hotkey)
    check(selection.waitForSelection(), "selection hotkey correction is emitted")
    check(selection.selections.map(\.0) == [.hotkey], "selected-text hotkey correction is applied with hotkey provenance")
    check(selection.selections.first?.1 == "protected", "selected protected text is converted")

    let switchSelection = ExceptionPipelineHarness(mode: .layoutSwitch, selectedText: "protected")
    switchSelection.engine.updatePersonalExceptions(protected)
    check(switchSelection.drain(), "selection layout-switch setup drains")
    switchSelection.switchSource(to: .ukrainian)
    check(switchSelection.waitForSelection(), "selection layout-switch correction is emitted")
    check(switchSelection.selections.map(\.0) == [.layoutSwitch], "selected text converted on a layout switch carries layoutSwitch provenance")
}

run("personal exceptions: security still wins for explicit triggers") {
    let secure = ExceptionPipelineHarness(mode: .automatic, focus: .secure)
    secure.engine.updatePersonalExceptions(PersonalExceptionsPolicy(words: ["protected"]))
    secure.type("protected")
    secure.enqueue(.hotkey)
    secure.type("other")
    secure.enqueue(.boundary(" "))
    check(secure.drain(), "secure pipeline drains")
    check(secure.plans.isEmpty, "hotkey bypass of exceptions never bypasses secure-field protection")
}

run("personal exceptions: empty-policy parity and removal in flight") {
    let empty = ExceptionPipelineHarness(mode: .automatic)
    empty.engine.updatePersonalExceptions(.empty)
    let unrelated = ExceptionPipelineHarness(mode: .automatic)
    unrelated.engine.updatePersonalExceptions(PersonalExceptionsPolicy(words: ["unrelated"]))
    for harness in [empty, unrelated] {
        harness.type("test")
        harness.enqueue(.boundary(" "))
        check(harness.drain(), "parity pipeline drains")
    }
    check(empty.plans.map(\.replacementText) == ["тест "], "empty policy corrects as before")
    check(unrelated.plans.map(\.replacementText) == empty.plans.map(\.replacementText), "an unrelated exception changes no correction")

    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let removal = ExceptionPipelineHarness(mode: .automatic, detectionStarted: started, releaseDetection: release)
    removal.engine.updatePersonalExceptions(PersonalExceptionsPolicy(words: ["other", "protected"]))
    removal.type("test")
    removal.enqueue(.boundary(" "))
    check(started.wait(timeout: .now() + 1) == .success, "detection started before removal")
    removal.engine.updatePersonalExceptions(PersonalExceptionsPolicy(words: ["other"]))
    release.signal()
    check(removal.drain(), "removal pipeline drains")
    check(removal.plans.isEmpty, "removing an exception invalidates the in-flight correction")
}

run("personal exceptions: unchanged set is not republished") {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { _ in nil },
        correctionEmission: { _ in true }
    )
    let publisher = PersonalExceptionsPublisher { engine.updatePersonalExceptions($0) }
    let start = store.snapshot().correctionEpoch
    check(publisher.publishIfChanged(PersonalExceptionsPolicy(words: ["a"])), "first set is published")
    check(!publisher.publishIfChanged(PersonalExceptionsPolicy(words: ["a"])), "unchanged set is not republished")
    check(store.snapshot().correctionEpoch == start + 1, "an unrelated preference change does not invalidate corrections")
    check(publisher.publishIfChanged(PersonalExceptionsPolicy(words: ["a", "b"])), "a changed set is published")
    check(store.snapshot().correctionEpoch == start + 2, "a genuine change invalidates once")
}

run("personal exceptions: U+02BC words reach detection whole") {
    check(KeyboardMonitor.capturedKind(forText: "\u{02BC}") == .character("\u{02BC}"), "U+02BC is captured as part of a word")
    check(KeyboardMonitor.capturedKind(forText: "’") == .character("’"), "U+2019 is captured as part of a word")
    check(KeyboardMonitor.capturedKind(forText: "'") == .character("'"), "ASCII apostrophe is captured as part of a word")
    check(KeyboardMonitor.capturedKind(forText: "!") == .boundary("!"), "control: '!' is a boundary")

    let current = context(layout: .ukrainian)
    var machine = automaticMachine(current)
    var commands: [InputStateCommand] = []
    for (index, character) in "сімʼя".enumerated() {
        commands += machine.consume(input(
            sequence: UInt64(index + 1),
            kind: KeyboardMonitor.capturedKind(forText: String(character)),
            context: current
        ))
    }
    commands += machine.consume(input(sequence: 10, kind: .boundary(" "), context: current))
    let flushed = commands.compactMap { command -> String? in
        if case .flush(let word, _, _, _) = command { return word }
        return nil
    }
    check(flushed == ["сімʼя"], "the whole word including U+02BC is flushed once")
    check(PersonalExceptionsPolicy(words: ["сім'я"]).matches(rawToken: flushed.first ?? ""), "the flushed word matches its exception")
}

private func runIntegrationSmoke() {
    guard Permissions.isAccessibilityGranted(), Permissions.isKeyboardListeningAvailable() else {
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
        trigger: .automaticBoundary,
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

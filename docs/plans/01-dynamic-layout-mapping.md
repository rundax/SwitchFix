# Dynamic, source-specific keyboard layout mapping

Status: Phase A is implementation-ready; Phase B is gated on benchmark evidence (see [Phase B](#phase-b--keystroke-provenance-gated)). Revised 2026-10-19 after review against the baseline. Baseline: `4b928be`. Platform: macOS 14+, existing SwiftPM targets, no added dependencies. Lands after plan 02, which introduces the shared `invalidateCorrectionConfiguration()` primitive and `CorrectionTrigger`; if plan 02 has not landed, add the primitive here with focused tests.

## Outcome and scope

Convert mistaken-layout text using the actual installed source tables, rather than assuming every English source is US QWERTY and every Cyrillic source has standard positions. Support English ↔ Ukrainian and English ↔ Russian. Keep Ukrainian ↔ Russian excluded. Preserve existing dictionary decisions, application exclusions, secure-field checks, bounded buffers, cancellation, rollback, and native undo handling.

The work has two phases:

- **Phase A — real tables, exact sources, text-level mapping.** Build per-source tables from macOS layout data, bind every correction to exact source IDs, and convert token text through the [canonical reverse rule](#canonical-reverse-rule). This covers Dvorak, Colemak, Apple Ukrainian, Ukrainian-PC, Ukrainian-QWERTY and Russian Phonetic without carrying keystrokes through the pipeline. Supported output is stateless, single-BMP-scalar printable output on unmodified and Shift strokes. Option output, Caps-exact punctuation, dead keys/composition, surrogate pairs and multi-character output are rejected, so a ready source can still skip individual tokens.
- **Phase B — keystroke provenance.** Carry each typed key's stroke through capture, state machine, run tokens, journal and requests, and capture Option output. Start it only when Phase A benchmark results show losses caused by text-level mapping.

Phase A is sufficient for source identity: `InputStateMachine.updateContext` clears the run on every context change and the context includes `inputSourceID`, so every token in a run, including tokens reached by a sweep, was typed on the request's source.

### Measured facts behind this design

Recorded 2026-10-18 with an independent `UCKeyTranslate` probe on macOS 15.7.9 (24G830), keyboard type 91 (`LMGetKbdType()`):

- `com.apple.keylayout.Ukrainian` puts `и` on S (key 1), `і` on B (key 11) and `ґ` on `\` (key 42), keeps `/` and `?` on key 44, and types `,` and `.` with Shift+6 and Shift+7. The static `enToUkStandard` table assumes `і` on S, `ґ` on `` ` `` and `.` on `/`, which matches Ukrainian-PC. Variant probing currently covers only the S/B swap; `ґ` and the punctuation keys convert wrongly today.
- No `Ukrainian-Legacy` source exists on this macOS version; Apple `Ukrainian` itself has the arrangement the code calls "legacy". Installed Apple sources include `ABC`, `US`, `British`, `Colemak`, `Dvorak` (plus `-Left`/`-Right`), `Ukrainian`, `Ukrainian-PC`, `Ukrainian-QWERTY`, `Russian`, `RussianWin` and `Russian-Phonetic`.
- Building complete tables (128 keys × 8 Shift/Caps/Option states) for five sources took 1.7 ms. Asynchronous building is unnecessary.
- The previously proposed reverse rule ("every source stroke that emits a scalar must yield the same target output") rejected `.`, `,`, `;`, `'`, `[` and `]` on ABC → Ukrainian/Russian, and `,`/`.` on Ukrainian → ABC, because Caps Lock and numeric-keypad variants of the same character convert differently (ABC `.` → `ю`, `Ю`, `.`, `,`). Ordinary sentences such as `Ghbdsn.` were rejected. The canonical rule accepts them.

## Current implementation and required changes

- `Sources/Core/LayoutMapper.swift` owns static QWERTY character maps, permissively preserves unknown characters, and exposes Ukrainian standard/legacy variants. Keep its language eligibility policy (`isEligibleTarget`); replace its production conversion.
- `InputSourceDiscoveryEngine.swift` already probes macOS source tables. `CarbonTISPropertyAdapter.swift` returns only `.first` from a 4-unit UTF-16 buffer; this cannot represent translation validity or composition. Discovery is useful evidence, not conversion readiness.
- `InputSourceManager.swift` caches sources and preferences, including exact source selection via `switchToSource(id:layout:)`. `fallbackSupportedLayouts` returns `[.english]` for anything unmatched and `currentLayout()` defaults to English; remove that inference for correction eligibility.
- `KeyboardMonitor` has a separate Shift-only HID translation cache built from the current source with `TISCopyCurrentKeyboardLayoutInputSource` as fallback. Phase A replaces it with a lookup into the captured source's snapshot table; no other source may supply characters. Any Option-modified key is classified as `.navigation` (`KeyboardMonitor.swift:372`), which also invalidates focus; Phase A keeps that behavior.
- `LayoutDetector` converts current and prior words via `LayoutMapper` and tries alternate Ukrainian variants (`LayoutDetector.swift:440–464`, `735–751`). Phase A converts through the exact source and target tables and removes variant guessing.
- `InputEngine` reads `detectionConfiguration` at detection time (`InputEngine.swift:375`). Phase A captures the mapping snapshot in the request at creation time.
- `TextCorrector` and `performSelectionCorrection` call `switchTo(layout)` after generating text. Bind and validate the exact source used to produce the replacement, including selection correction and undo.
- `CapturedInput` records key code, flags and source ID. Add the event's keyboard type.

## Concrete data and API design

Add `Sources/Core/KeyboardLayoutMapping.swift` containing small value types and the pure mapper. Do not introduce a service hierarchy.

```swift
struct KeyStroke: Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: UInt8 // Carbon high-byte bits: Shift, Caps, Option only
}
struct SourceKey: Hashable, Sendable {
    let sourceID: String
    let keyboardType: UInt32
}
struct SourceMapping: Sendable {
    let key: SourceKey
    let layoutDataHash: UInt64
    let outputs: [KeyStroke: String]     // all eight modifier states
    let reverse: [String: [KeyStroke]]   // canonical candidates only
    let rejected: [KeyStroke: TranslationRejection]
}
struct MappingSnapshot: Sendable {
    let generation: UInt64
    let sources: [SourceKey: SourceMapping]
    let preferredSourceIDs: [Layout: String]
}
struct MappingBinding: Equatable, Sendable {
    let generation: UInt64
    let sourceID: String
    let targetID: String
    let keyboardType: UInt32
}
```

Provide `convertText(_:from:to:keyboardType:snapshot:)` returning `Result<MappedText, MappingFailure>`. `MappedText` includes the full replacement and binding. Failures distinguish unavailable source, unsupported pair, stale snapshot, unknown keyboard type, unsupported output, unmappable scalar and ambiguous reverse mapping, each with a stable reason code the benchmark can report. Do not return partially converted strings. Keep failures internal except for a short manual-correction status message; never log token contents. `outputs` keeps all eight modifier states so fixture tables are complete and Phase B can use them; `reverse` holds only the canonical subset.

Language identity remains separate from physical mapping: the request includes source/target `Layout` values for dictionary and eligibility logic, plus exact source IDs. Reuse `LayoutMapper.isEligibleTarget`; add explicit opposite-script validation before mapping.

## Native table builder

Extend `CarbonTISPropertyAdapter` with a translation result API that preserves the complete UTF-16 output, status and returned dead-key state. Keep `translatedCharacter` as a guarded discovery wrapper until its callers migrate. Add a fake translator at this boundary for runnable fixtures.

Build synchronously on the main thread inside `refreshInstalledSources()`: enumerate enabled keyboard-layout sources as today, copy `kTISPropertyUnicodeKeyLayoutData` into owned `Data`, build immutable tables for the current keyboard type, and publish descriptors and tables together under the existing state lock. `AppDelegate` first touches `InputSourceManager.shared` on the main thread; add a main-thread precondition. No background builder, request counter or "mapping unavailable" window is needed. TIS objects and unowned pointers never leave the builder; layout pointers remain inside `withUnsafeBytes`.

For virtual keys 0..<128 and all eight Shift/Caps/Option combinations:

1. Translate with `kUCKeyActionDown`, dead state initialized to zero and options zero. Any nonzero returned dead state marks that stroke unsupported, even if a spacing character was emitted.
2. For a stateless result, decode the complete output buffer. Allocate 255 UTF-16 units, check status/length, and reject invalid UTF-16 instead of using replacement-character decoding.
3. Accept exactly one BMP scalar, excluding surrogate code units, controls, private-use function-key output and nonprinting output. Allow ordinary space only for explicit separator handling; never include Return/Tab/function/navigation keys in a printable map.
4. Populate `outputs`, then build `reverse` from the canonical candidates only.

Use Carbon modifier constants shifted right eight bits, not raw `CGEventFlags`. Map the flags explicitly. Command/Control combinations remain commands and invalidate tracking as today.

`kUCKeyTranslateNoDeadKeysBit` is passed as an options mask at three sites. The bit constant is zero; the corresponding mask is `1 << kUCKeyTranslateNoDeadKeysBit`. Treat each site differently:

- `CarbonTISPropertyAdapter.swift:56` (discovery): switch to the mask. Discovery may show a dead key's spacing character.
- `Utils/KeyCodeMapping.swift:28` (hotkey label in Settings): switch to the mask.
- `KeyboardMonitor.swift:454` (HID capture): **do not** switch to the mask. With options zero a dead key returns no characters, so the event falls through to `.navigation` and tracking stops, which is the safe outcome. The mask would put the spacing accent into the buffer while the application composes a different character, so buffer and screen would disagree. Phase A replaces this translation with a snapshot lookup in which dead-key strokes have no entry.

Apple documents full-string output, modifier-byte conversion, keyboard type and dead-state behavior in [UCKeyTranslate](https://developer.apple.com/documentation/coreservices/1390584-uckeytranslate); the [bit constant definition](https://developer.apple.com/documentation/coreservices/1390507-key_translation_options_flag/kuckeytranslatenodeadkeysbit?language=objc) explains the mask distinction. UCKeyTranslate is used here because the request concerns a specific inactive source's layout data, with an existing Carbon implementation; keep it isolated.

## Canonical reverse rule

Phase A uses one rule for typed tokens and selected text. For each scalar:

1. Candidates are strokes on main-block keys only. Exclude numeric-keypad key codes (65, 67, 69, 71, 75, 76, 78, 81–89, 91, 92, 95) and every non-printing key. Allowed modifier states are unmodified and Shift. Caps Lock and Option strokes are never reverse candidates: selected text carries no Caps state, and Option output is not captured in Phase A.
2. Use the lowest tier that contains the scalar (unmodified before Shift).
3. Every candidate in that tier must produce the same supported output in the target table; otherwise reject the whole token or selection. Identical outputs from duplicate keys are safe. No dictionary-based tie-breaking.
4. Spaces, tabs and line breaks in selections are copied as separators. Emoji, combining sequences, non-BMP characters and scalars with no candidate reject the whole selection. No normalization or accent stripping. This is intentionally stricter than the current preserve-unknown behavior. When a selection is rejected, do not silently convert a buffered word instead; leave the selection untouched and report briefly.

Case: uppercase letters come from the Shift tier. Keep the detector's existing `applyCase`, so an all-caps word typed under Caps Lock still converts to all caps (`GHBDSN,` → `ПРИВІТб` → `ПРИВІТБ` on Ukrainian-PC). Punctuation typed under Caps Lock inside a mixed-case word converts as unshifted; Phase B addresses that if the benchmark shows it matters.

Known consequence: Apple Ukrainian types `,` and `.` with Shift+6 and Shift+7, so key-for-key inversion of `Руддщ, цщкдв.` is `Hello^ world&`. This is physically correct but rarely intended. Keep key-for-key behavior in Phase A, give it a benchmark stratum, and treat any change as a product decision.

Measured expectations to seed fixtures (re-verify against native on-screen output in the manual matrix):

| From → to | Input | Expected |
| --- | --- | --- |
| ABC → Ukrainian-PC | `ghbdsn` | `привіт` |
| ABC → Ukrainian (Apple) | `Ghsdbn.` | `Привітю` |
| Ukrainian (Apple) → ABC | `руддщ цщкдв` | `hello world` |
| Ukrainian (Apple) → ABC | `Руддщ, цщкдв.` | `Hello^ world&` |

## Typed text and keyboard type

Convert the captured token text with the canonical rule, using the request's exact source (`context.inputSourceID`), the keyboard type captured with the word, and the preferred target source captured in the snapshot. Sweeps use the same source because the run is cleared on any context change. If the source or target is not ready, abstain. Dictionary casing helpers may only apply case as described above. Preserve existing punctuation guards and script checks.

Each key event carries its keyboard type in `CGEventField.keyboardEventKeyboardType` (raw value 10). Record it in `CapturedInput`. The snapshot holds tables per `(source ID, keyboard type)`. The first key event whose keyboard type has no tables marks the current word untracked until the next boundary and schedules a main-thread build for that type (about 0.35 ms per source), which publishes a new generation. A word is never converted with another keyboard's table, so switching between ANSI, ISO and JIS keyboards is handled rather than documented as a limitation. Selected text uses the keyboard type of the most recent key event.

The `KeyboardMonitor` HID fallback looks up the captured source's table for the event's keyboard type and Shift/Caps state. It never falls back to `TISCopyCurrentKeyboardLayoutInputSource` or another source. Dead-key strokes have no entry, so those events stay `.navigation`.

## Snapshot lifecycle, readiness, and cancellation

`InputSourceManager` publishes one immutable snapshot through its existing lock. Generations are monotonic. Rebuild synchronously on enabled-source changes, preferred-source changes, a new keyboard type, wake and an explicit readiness refresh. Compare layout-data hashes so a content change under an unchanged source ID publishes a new generation. Avoid filesystem watchers: explicit refresh/restart covers third-party resource edits that macOS does not announce.

Every publication calls `CaptureStateStore.invalidateCorrectionConfiguration()`, so buffered run, detector journal, pending detection, selection callbacks, correction emission and delayed source selection are invalidated by the existing correction-epoch checks. Snapshot generation identifies table provenance; `correctionEpoch` remains the single authorization check for configuration changes. Check the binding at request creation, before deletion/paste, between existing emission phases and again on the main-thread selection hop. Do not weaken focus, PID, permission, secure-state or edit-generation checks.

Separate three states: discovery identifies a language; support permits an English/Cyrillic pair; readiness proves exact source tables and a usable pair exist. `availableLayouts` can still populate menus, but runtime readiness and detector allowed targets must use ready preferred-source pairs. Unknown sources and input methods never default to ready English. Hybrid metadata cannot promise letters absent from its tables, and existing same-source automatic-switch suppression remains.

## Every correction mode and undo

Automatic and hotkey-buffer correction bind the observed source plus the preferred target ID captured in the snapshot. Selection correction binds the explicit source and target used by the canonical rule. Layout-switch mode converts the buffered word from the old exact source (`AppDelegate.previousInputSourceID`) to the user's newly selected exact source, only for an eligible opposite-script pair; source IDs replace `fromVariant`/`toVariant` in `handleLayoutChange`. Switching between sources of the same language or script invalidates tracked state without converting text; preserve the existing no same-script conversion policy.

Extend `CorrectionPlan` and selection requests with the mapping binding and exact source IDs. `rebaseUndoContext` (`TextCorrector.swift:202`) rebuilds plans field by field and must copy the binding. Replace all layout-only post-correction switches with `switchToSource(id:layout:)`. Validate selectability before text emission and recheck before switching. If source selection subsequently fails, keep the applied text, report the failure and never choose another source silently. Preserve current rollback behavior for interrupted text emission.

Undo stores literal original/corrected strings and the original exact source ID; it must not reconvert text. Allow existing safe immediate undo across SwitchFix's own expected source transition, while rejecting external source changes, stale generations, missing original source and all current edit/focus failures. Native Cmd-Z continues to invalidate tracking as today.

## Ordered implementation and commits (Phase A)

1. **Lock mapping safety and add the native builder.** Translation result API and fake, pure mapper with the canonical rule, and fixture checks in `Sources/TestRunner/main.swift` using the frozen tables from plan 03 (`Benchmarks/layout-tables/v1`). Switch only the discovery and hotkey-label call sites to the no-dead-keys mask. Production conversion stays unchanged.
2. **Publish ready snapshots synchronously.** Manager, keyboard-type capture in `CapturedInput`/`KeyboardMonitor`, AppDelegate refresh plumbing, runtime readiness and status messages, invalidation through `invalidateCorrectionConfiguration()`. Test unavailable sources, unknown keyboard types and content changes under one source ID.
3. **Convert through exact sources.** Detector (current word and sweeps), hotkey, selection and layout-switch paths, and the `KeyboardMonitor` HID lookup. Requests carry the snapshot. Remove the Ukrainian variant fallbacks.
4. **Bind source selection and undo.** `CorrectionPlan`/selection bindings, `switchToSource(id:layout:)` everywhere, `rebaseUndoContext` and undo.
5. **Remove static maps, verify hardware, document.** Delete production static maps once no call site uses them; keep variant metadata only where useful for discovery labels. Run the manual matrix, add concise user guidance, and rerun the benchmark against the frozen baseline.

Each commit must build and pass its applicable runner. Expected values come from the frozen fixture tables and native on-screen observations, never from the function under test. No XCTest target registration is necessary.

## Phase B — keystroke provenance (gated)

Start Phase B only if the post-Phase-A benchmark attributes missed or wrong repairs to text-level mapping (reason codes `ambiguous_reverse`, `caps_punctuation`, `option_output`), and record that decision in this file. Scope at that point:

- Add `TypedUnit { text; stroke }` and store units alongside the bounded current buffer. A delete removes the last unit only for the existing single-character deletion. A mismatch, multi-unit edit, overflow, navigation, tap reset or untracked deletion clears provenance in the same state transition.
- Extend `RunToken`, `DetectionRequest` and journal entries with bounded units. Sweeps map each token with its own units; already corrected tokens contribute display text only. Stop a sweep at missing provenance or an incompatible generation. Keep the 16-token bound.
- Convert stroke by stroke through the target table, retaining modifiers including Caps, and verify the reconstructed source text equals the token. Physical outputs then override `applyCase`.
- Capture Option output by reclassifying Option-only key events in `KeyboardMonitor.classify` as characters when the snapshot has a stateless output for that stroke. Option+Delete deletes a word and must stay an untracked deletion rather than `.delete`; Option+Space types U+00A0 and must not be treated as an ordinary space; Option+arrows and Option+Forward-Delete stay navigation; Command/Control remain commands.
- Detect empty/dead-key events before a composed character can enter a word as ordinary typing.

## Verification and acceptance

Run from repository root:

```sh
swift build
swift run -c release TestRunner
swift run -c release InputPipelineTestRunner
swift build -c release
```

`Tests/SwitchFixTests/LayoutMapperTests.swift` is a placeholder comment and is not registered in `Package.swift`; existing mapper coverage lives in `TestRunner`, so add new cases there. Run the native-source smoke probe through a small explicit opt-in mode in TestRunner, separate from deterministic fixtures, and print skipped source IDs when the machine lacks them. The pipeline check `TextCorrector must apply layout-only plan without deleting text` (`InputPipelineTestRunner/main.swift:584`) needs Accessibility and fails in sessions without it; record that as environment-dependent, not a regression.

Required deterministic Phase A cases: the measured expectations above; US/ABC/British parity; Dvorak/Colemak fixtures; Apple Ukrainian versus Ukrainian-PC versus Ukrainian-QWERTY positions, including `ґ` on key 42; Russian and Russian Phonetic; keypad duplicates of `.`, `/`, `*`, `+`, `-` and `=` ignored; Caps-only and Option-only strokes ignored by the reverse rule; unmodified-before-Shift tier selection; duplicate main-block keys with matching and conflicting target output; dead state with and without visible output; empty/invalid/multi-unit/non-BMP output; partial unmappable word and selection; zero postings on rejection; unknown/missing source; unknown keyboard type marks the word untracked; same ID with changed data; source removal or preference change while detection or clipboard work waits; target source identity preserved through delayed switch and immediate undo; a rebased undo plan keeps its binding.

Manual matrix: built-in ANSI plus an ISO external keyboard (keys 10/50 differ), including switching keyboards mid-session; JIS is required before advertising JIS support. Test each available ABC/US, British, Dvorak, Colemak, Ukrainian/Ukrainian-PC/Ukrainian-QWERTY, Russian/RussianWin/Phonetic source against its actual on-screen output in TextEdit and a browser textarea. Exercise all three modes, selections with punctuation/newlines, undo, fast typing during correction, secure fields, source removal, sleep/wake, keyboard reconnection and a dead-key English source. Record OS/build, keyboard type, source IDs, expected/actual text, exact active source after correction and any skipped hardware. Do not infer hardware coverage from fixture success.

Acceptance: no production QWERTY fallback; no partial conversion; no source-ID drift; unsupported tokens remain untouched; stale work emits nothing; all existing trust-boundary checks remain; all runners pass apart from documented permission-dependent checks; supported hardware cases match native output. The benchmark must show no unexplained regression against the frozen baseline; any changed abstention is recorded explicitly with its reason code.

## Integration contracts and non-goals

Personal exceptions (plan 02) receive the original token before conversion and may veto an automatic correction; they do not alter source tables or resolve mapping ambiguity. Mapping publication reuses plan 02's `invalidateCorrectionConfiguration()`; mapping generation identifies source provenance rather than creating a competing authorization scheme. Benchmark fixture tables live in `Benchmarks/layout-tables/v1` (plan 03); Core exposes a pure loader for them so benchmarks never depend on the operator's installed sources. Mapping rejections are reported with reason codes, separately from dictionary abstention.

Non-goals: new languages, spell correction, IME/composition emulation, arbitrary Unicode deletion semantics, per-device HID identification (keyboard type is used instead), cloud sync, new dependencies, copying Klavko implementation, or broader detector threshold tuning. Intentional ceilings should receive small `ponytail:` comments in the eventual mapper naming the unmodified/Shift-only reverse tiers and the single-BMP/stateless limit, and when to revisit them (Phase B evidence).

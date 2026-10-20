# Personal automatic-correction exceptions

Status: implementation-ready plan; no feature code is included. Revised 2026-10-19 after review against the baseline.

Baseline: SwitchFix commit `4b928be`. This plan lands before plan 01 and introduces the shared `CaptureStateStore.invalidateCorrectionConfiguration()` primitive and `CorrectionTrigger`, which plan 01 reuses. Run its cases through the shared benchmark. Keep existing correction safety checks intact.

## Outcome and scope

Users can protect a word that SwitchFix repeatedly changes incorrectly. Settings contains a persistent list with Add and Remove controls. After successfully reverting a single-word automatic correction, the user can explicitly choose **Never Auto-correct Last Reverted Word** in the menu bar. Merely reverting never adds an exception.

An exception suppresses automatic text replacement and the associated automatic layout switch. It does not change dictionary validity, language detection outside the protected token, manually requested correction, excluded-app behavior, or access requirements. No dependency, learned-word database, clipboard access, or new Accessibility text read is required.

The first release has no repeated-undo prompt, counters, notifications, automatic learning, or history. The fixed menu action supplies an explicit, discoverable learning path without interrupting typing. A repeated-undo suggestion is a separate future feature requiring a specified threshold and dismissal policy; it is not a condition for completing this plan.

## Existing integration points

- `Sources/Core/InputEngine.swift` schedules automatic boundary detection, manual hotkey detection, selected-text correction, and correction emission on separate queues. Its current `DetectionRequest` does not identify why detection was requested.
- `Sources/Core/LayoutDetector.swift` maintains a journal and can extend a correction backward across preceding words in `sweepRun`. Checking only the current word would leave earlier protected words vulnerable.
- `Sources/Core/TextCorrector.swift` stores the applied `CorrectionPlan` in `UndoState`. `undo` currently returns only `Bool`; successful restoration is the authoritative point for offering an exception.
- `Sources/UI/PreferencesManager.swift` persists settings and posts `.preferencesDidChange`. `AppDelegate.preferencesDidUpdate` forwards snapshots to the engine. Core cannot import UI.
- `Sources/UI/SettingsView.swift` already supplies list/add/remove patterns for excluded apps. `StatusBarController.swift` has explicit menu-item enablement and can expose the learning action without another shortcut.
- `Sources/TestRunner/main.swift` and `Sources/InputPipelineTestRunner/main.swift` are executable assertion runners. Add tests there; do not create an XCTest-only target.

## Behavioral contract

### Matching and scope

Use one global set of original, typed tokens across applications, source IDs, and languages. This means “leave this spelling alone,” including after switching from QWERTY to Dvorak. Do not key entries by a converted candidate or current target language. This choice is independent of dynamic mapper source identity.

Add a small Core value type, `PersonalExceptionsPolicy`, with a single canonicalization implementation and immutable `Set<String>` lookup. Canonicalization is NFC normalization, locale-independent Swift `lowercased()`, replacement of U+2019 RIGHT SINGLE QUOTATION MARK and U+02BC MODIFIER LETTER APOSTROPHE with ASCII apostrophe, then NFC again. Do not use compatibility normalization, transliteration, accent stripping, stemming, or fuzzy matching. Keep backticks and hyphens distinct.

Settings trims surrounding whitespace before validation; engine lookup never trims captured fragments into a different token. Accept 1–64 Swift `Character`s and at most 256 UTF-8 bytes after normalization, containing at least one Unicode letter. Allow letters and combining marks, ASCII digits, and internal `'`, backtick, or `-`; punctuation may not be first, last, or adjacent to another punctuation character. Reject whitespace, controls, format characters, emoji, paths, URLs, and multiple tokens. A malformed persisted entry must never become a broader rule.

Derive the matching key in two steps, both from existing detector code: take the token after `splitTrailingBoundary` (`LayoutDetector.swift:1104`), then drop its leading and trailing non-letter, non-digit characters (the prefix and suffix from `splitTokenForValidation`, `LayoutDetector.swift:1073`), and canonicalize the rest. The second step is required because `splitTrailingBoundary` deliberately keeps ``, . ; ' [ ] ` < > : " { } ~`` in the token (they are letters on Cyrillic layouts), so on its own `foo,` would never match `foo`, and a word before a comma or period would stay unprotected. A protected token is left entirely as typed, including the stripped characters. Accepted trade-off: protecting `kj` also suppresses the correction of `kj,` (`лоб` typed on the wrong layout); the benchmark records this collision in the personalized profile. Put the key derivation in one shared helper used by current-token checks, sweep barriers, engine safeguards and receipt creation; do not add another tokenizer. Protect the entire core token, not a substring or prefix: protecting `foo` does not protect `foobar`; `foo-bar` remains distinct from `foo`; `cafe` remains distinct from `café`. Case variants match. Canonically equivalent composed/decomposed Unicode and the three specified apostrophes match. Settings displays the canonical stored form so its scope is visible. Duplicate Add is a harmless no-op with an inline “Already in the list” message.

Tokenization must agree with this contract: `KeyboardMonitor.boundaryCharacterSet` already permits ASCII and curly apostrophes, backticks, and hyphens. U+02BC is a modifier letter (Lm), so neither the monitor's nor the detector's boundary set contains it today; add regression cases confirming the complete word, including U+02BC, reaches detection. Do not change boundary rules as part of this work.

### Automatic versus explicit actions

Introduce `CorrectionTrigger` with `.automaticBoundary`, `.hotkey`, and `.layoutSwitch`; carry it in `DetectionRequest` and `CorrectionPlan`, including selection plans. Give it no default value in either initializer: every construction site (`InputEngine.prepareCorrection`, the undo inverse plan, `TextCorrector.rebaseUndoContext`, `performSelectionCorrection`, and test helpers) must pass it explicitly. `rebaseUndoContext` (`TextCorrector.swift:202`) rebuilds the stored plan field by field after SwitchFix's own source switch; a defaulted field there would silently turn a hotkey correction into an automatic one, which could produce a learning receipt, or drop an automatic correction's eligibility. The same applies to the single-token provenance below.

Only `.automaticBoundary` consults personal exceptions. `.hotkey` always permits deliberate current-word or selected-text conversion; `.layoutSwitch` likewise bypasses exceptions because the user explicitly changed the system layout in that correction mode. All retain existing secure-field, application, dictionary-readiness, length, sequence, and focus checks. The existing revert-hotkey fallback to manual correction remains explicit and bypasses exceptions.

For automatic detection:

1. If the current captured word matches an exception, return no correction, emit no layout switch, and reset pending confidence/switch state so this word does not vote toward a later switch.
2. Keep the token represented as a journal barrier. A backward sweep stops before any protected token and may still correct the contiguous eligible suffix after it. It must never delete and reinsert the protected token merely to reach earlier words.
3. Apply the same barrier to `journal.display` when an earlier token was already converted, in addition to its original `typed` spelling. This protects newly added exceptions against rewriting text already shown on screen.
4. Do not mark an exception “valid in every dictionary.” That would change unrelated language scoring and make manual behavior inconsistent.

Implement the check inside the detector path used by normal direct callers and the engine; filtering only after `DetectionResult` creation is insufficient because journal/confidence state can already have changed. A detector policy property or explicit parameter must default to the empty policy for source compatibility. In manual mode install the empty policy for that request. The injected `exactDetection` test seam must also pass through engine-level current-token and sweep-span safeguards so it cannot bypass protection in pipeline tests.

## Storage and configuration ordering

Add `Sources/Core/PersonalExceptionsPolicy.swift` for normalization, validation, and immutable snapshots, and `Sources/Core/PersonalExceptionsStore.swift` for a small injected-`UserDefaults` store. Keeping the store in Core allows real persistence tests without importing the UI target. `PreferencesManager` owns the production instance and exposes validated snapshots and add/remove operations; it does not expose raw mutable defaults.

Persist a property-list dictionary under `SwitchFix_personalExceptions_v1` with `schemaVersion: 1` and sorted canonical `words: [String]`. No timestamp, original casing, app identifier, target spelling, or captured context belongs on disk. Limit the set to 1,000 entries. Validate types, version, count, individual lengths and characters; reject an oversized or unknown-version envelope, skip invalid members in an otherwise bounded envelope, deduplicate valid members, and report a generic recoverable settings message. Do not overwrite an unreadable value merely by opening Settings. A subsequent explicit edit may replace it with the sanitized v1 list. Inject an isolated defaults suite for tests and remove that suite afterward.

Publish validated immutable snapshots through the existing preference-update path; never read `UserDefaults` from the event tap or detection hot path. Serialize production edits on the main thread. On a genuine set change:

1. Invalidate pending correction work immediately through `CaptureStateStore.invalidateCorrectionConfiguration()`, which increments the existing `correctionEpoch` under its lock. Reuse the same method as the dynamic-mapping plan; do not introduce a second staleness counter.
2. Queue the new snapshot and returned epoch on `inputQueue`, reset the run/buffer, and enqueue detector policy/reset changes on `detectionQueue` before scheduling subsequent requests. Each request uses the policy associated with its epoch rather than reading a newer policy mid-flight.
3. Retain the existing eligibility checks before and during event emission. Old queued requests cannot apply after an edit; if an edit interrupts an active replacement, use the current rollback behavior. A correction completed before invalidation is not retroactively undone.

Do not rely on `updateCorrectionEnabled` for this invalidation: it does not increment the epoch when enabled state is unchanged. Adding/removing exceptions must work while SwitchFix remains enabled. This plan adds the shared invalidation primitive with focused tests; plan 01 calls the same method for mapping publication. `InputEngine` keeps its own copy of the epoch for new requests, so the primitive's caller must also push the returned epoch to the engine, as `updatePreferences` does today.

## Explicit learning after revert

Add enough provenance to an applied plan to distinguish a captured single automatic token from a sweep, selection, layout-only action, and manual correction. Do not infer it by splitting `originalText`: the detector can return a multiword span and selected text can resemble a single word.

Replace or supplement the internal Boolean undo result with a typed `UndoOutcome` exposing an optional `RevertedTokenReceipt` only after the entire inverse text emission succeeds. The receipt contains only the trigger and the matching key derived from the plan's original token by the shared helper above; if that key fails validation, issue no receipt. Keep the external fallback behavior: a failed/stale undo can still request manual correction, but never issues a learning receipt. Layout-only undo, interrupted/rolled-back inverse emission, native application Undo, multiword sweep, selected text, and manual-correction undo produce no candidate.

Use the original typed spelling from the stored plan, never `correctedText`, the current buffer, selected text, or an Accessibility read. Publish the receipt from the engine to `AppDelegate` on the main thread. Hold at most one in-memory candidate, expiring ten minutes after successful revert; check expiry when refreshing the menu and executing the action. Clear it on the next successful correction, replacement by another successful revert, permissions loss, focus resolved as secure, or successful save. Do not clear it on unknown focus: every mouse-down, including the click that opens the SwitchFix menu, is captured as `.focusMayChange` and sets focus to unknown (`KeyboardMonitor.swift:323`, `CapturedInput.swift:371`), so clearing there would make the menu action unreachable. Keeping an already captured receipt while opening the menu does not authorize another text read or edit.

The menu item uses the fixed label **Never Auto-correct Last Reverted Word**, with no raw word in menu titles, tooltips, or logs. Enable only for a current valid candidate not already protected and while storage capacity permits. Clicking it only adds that original token to preferences and consumes the candidate; it does not touch the frontmost application. The user can review/remove the word in Settings. An already-saved duplicate is safe and consumes the candidate. Show a short inline/settings status for capacity or persistence problems; do not silently discard an explicit Add.

## UI tasks

Add a **Personal Exceptions** section to `SettingsView.swift`, between layouts and excluded apps. Include concise copy: “These words stay as typed during automatic correction. Hotkey and layout-switch corrections still work.” Use a selectable list, one text field, Add, and Remove Selected. Display an empty state, count/limit, validation messages, and keyboard-accessible controls with labels for icon-only buttons. Add supports Return; Remove requires a selection. No bulk import/export or additional window is needed.

`SettingsViewModel` refreshes the list on `.preferencesDidChange`, using equality checks to avoid notification loops. `StatusBarController` exposes a candidate-update/action callback; `AppDelegate` owns engine-to-UI wiring and calls the preferences operation. UI code must not reach into the corrector's undo lock. A fixed confirmation/status text may indicate the save succeeded; never write user tokens to `SwitchFixLog` or analytics.

## Verification and acceptance

Extend `TestRunner` with table-driven normalization/validation cases: case variants, NFC/NFD, all three apostrophes, diacritics, backticks, hyphens, digits, duplicates, no prefix/substring match, multiword/URL/control/emoji rejection, character/byte ceilings, and 1,000-entry capacity. Matching-key cases: protected `foo` matches `foo,`, `foo.` and `"foo` and leaves the punctuation on screen; protected `kj` suppresses `kj,` (the documented trade-off); a U+02BC word reaches detection whole. Persistence cases cover empty startup, restart, removal, malformed types, unknown version, oversized envelope, invalid entries, deterministic serialization, and isolated defaults cleanup.

Extend detector tests with protected current word, layout-only prediction suppression, confidence reset, protected earlier word, barrier beside already-converted journal entries, protected-token-at-run-start/middle/end, newline boundaries, and empty-policy parity. Assert exact resulting replacement spans, not just “no crash.” Use a known existing correction fixture and protect its original spelling; do not rely on dictionary additions to invent a false positive.

Extend `InputPipelineTestRunner` using existing injected detection/emission and semaphore patterns: a blocked automatic request cannot emit after Add or Remove; configuration publication precedes new input; selected text and hotkey/layout-switch bypass work; focus/access/security cancellation still wins; empty policies preserve baseline behavior. Add deterministic success/failure seams around undo outcome generation so these tests require no system permissions or synthesized keystrokes. Verify only a completed single automatic revert offers the original token; all ineligible cases above do not. A plan rebased by `rebaseUndoContext` keeps its trigger and provenance. A `.focusMayChange` input after the revert keeps the candidate; a secure focus resolution clears it. Test candidate expiry with an injected clock rather than sleeping ten minutes.

Run from the repository root on macOS:

```sh
swift build
swift run -c release TestRunner
swift run -c release InputPipelineTestRunner
```

Manually verify Settings Add/Remove/relaunch, duplicate and capacity messages, menu learning after a real revert, protected typing, explicit override, and a sweep beside a protected word in TextEdit. Verify VoiceOver labels/tab navigation. Do not claim hardware integration is covered by injected tests. The shared benchmark adds paired empty-policy/protected-policy cases; a policy-created abstention on a positive example is a missed correction, not a false-positive reduction without cost.

Acceptance: all existing runners pass; an empty list preserves existing results; a protected token is never included in an automatic replacement span or associated automatic switch; explicit correction still works; stale work is invalidated; persistence survives restart; no undo path silently learns; no captured word is logged. Document any unavailable manual checks.

## Commit slices and dependencies

1. **Preserve intentional spellings consistently:** Core policy/store, bounds, persistence tests. No UI/pipeline behavior yet.
2. **Respect exceptions without rewriting protected context:** trigger provenance, detector current-token/sweep barriers, `invalidateCorrectionConfiguration()`, pipeline regressions. Plan 01 builds on these `CapturedInput.swift`, `InputEngine.swift`, and `TextCorrector.swift` changes; keep them additive.
3. **Let users manage protected words:** PreferencesManager/AppDelegate wiring, Settings list and operations; verify restart and accessibility.
4. **Learn only from an explicit successful revert:** typed undo outcome, candidate lifecycle, menu action, focused tests and manual verification.
5. **Measure correction tradeoffs:** add the exception fixtures to plan 03's versioned corpus once its schema exists. The feature itself does not depend on the benchmark runner or dynamic source tables.

Remaining risks are intentional global scope (one spelling is protected everywhere), case/apostrophe equivalence, and reduced automatic recall for protected words. Keep those visible in UI copy and benchmark results. Revisit source-specific rules only if real user evidence shows global behavior is insufficient.

# Live dictionary suggestions while typing

Status: design proposal for owner review; no feature code is included. Prepared 2026-10-22 on branch `fix/v0.0.13-bug-reports` (base `a77f218`).

This plan extends [02 — Personal exceptions](02-personal-exceptions.md). Plan 02 deliberately shipped without prompts, counters, or learning ("Merely reverting never adds an exception", slice 4 still TODO). Requesting live suggestions is an owner decision that widens that scope. The decisions listed at the end must be confirmed before implementation starts (EXECUTION.md marks behavior beyond a plan as BLOCKED).

## Outcome

While the user types, SwitchFix notices the moments when it got a word wrong and offers, without interrupting typing, to remember the user's choice:

| Situation | What SwitchFix saw | Offer |
| --- | --- | --- |
| SwitchFix changed a word the user wanted as typed | Automatic correction, then the user reverted it | **Keep "vnc" as typed** → adds a personal exception (exists today) |
| SwitchFix left a word the user wanted changed | No automatic correction, then the user fixed the same word manually | **Always correct "ghbdsn" → "привіт"** → adds a personal correction (new list) |

The user can ignore every offer. Nothing is stored unless they click.

## Signals, strongest first

All signals already exist in the pipeline; none needs to read text through Accessibility.

1. **Explicit revert of an automatic correction ("keep").** `TextCorrector.undo` succeeds for a single-word plan with trigger `.automaticBoundary`. This is plan 02 slice 4's `UndoOutcome` with a `RevertedTokenReceipt`; build it first, exactly as plan 02 specifies (receipt only after the full inverse emission succeeds; none for sweeps, selections, layout-only or manual corrections). Offer immediately: the user just made an explicit choice.
2. **Manual fix of a word automatic mode declined ("always correct").** In automatic mode, a `.hotkey` correction succeeds for a word that automatic detection evaluated and left alone (the word is still in `InputStateMachine.run` / the detector journal, typically reopened with Backspace). Offer immediately.
3. **Delete and retype (implicit, both directions).** The user deletes a whole word (run token popped and emptied by deletes), switches layout, and types the word whose conversion matches the deleted token, or deletes an automatic correction and retypes the original. Ambiguous on its own, so offer only after the **second** occurrence of the same token in the session (in-memory counter, never persisted).

Never offer for words typed in secure fields, excluded apps, or tokens the detector already treats as codes, URLs, mixed scripts or all-caps acronyms. Never offer for the hotkey workflow in **Hotkey Only** mode: there the hotkey is the normal path, not a miss.

## Presentation: unobtrusive and focus-safe

- **Suggestion chip.** A small non-activating `NSPanel` (`.nonactivatingPanel`, `.hudWindow` look, `becomesKeyOnlyIfNeeded`) under the menu bar icon: `Keep “vnc” as typed?  [Keep]  [×]`. It never takes keyboard focus, so typing continues uninterrupted. It fades after 6 seconds.
- **Menu bar dot.** While a suggestion is pending, the "Ab" icon shows a small dot. The menu gains the same action at the top. The pending suggestion expires 10 minutes after the event (plan 02's candidate lifetime) or on the next successful correction, permission loss, or secure field. It is not cleared on unknown focus, because the click on the chip or menu itself produces unknown focus.
- **One at a time.** A newer suggestion replaces an older one. **Not now** suppresses that word for the session. **Settings → Suggest additions to my dictionary** turns the feature off (default on).
- **Caret-anchored chip (phase 3, optional).** Placing the chip at the caret needs `kAXBoundsForRangeParameterizedAttribute`, a new Accessibility query that plan 02 rules out, and Electron apps and browsers often report poor bounds. Keep the menu-bar anchor as the default.

## Data model

- **Keep as typed**: the existing `PersonalExceptionsPolicy` / `PersonalExceptionsStore` (1,000 entries, NFC + lowercase + apostrophe normalization). No change.
- **Always correct** (new): `PersonalCorrectionsStore` under `SwitchFix_personalCorrections_v1`. Each entry is the canonical typed token, its source script, and the corrected text, using the same normalization and limits as exceptions. A forced correction bypasses dictionary validity and confidence but never the safety gates: secure fields, excluded apps, the 64-character cap, the Cyrillic↔Cyrillic ban, and personal exceptions, which win over corrections.
- **Candidates** live only in memory, on the main thread, at most one pending. Words never go to `SwitchFixLog`, analytics, or disk unless accepted. The chip shows the word because the user cannot decide without it. This is a deliberate exception to plan 02's "no raw word in UI chrome" rule (decision 2).

## Implementation outline

| Slice | Content | Tests |
| --- | --- | --- |
| 1 | Plan 02 slice 4 as written: typed `UndoOutcome`, receipt, candidate lifecycle with an injected clock, menu action | Plan 02 slice 4 tests |
| 2 | `SuggestionCenter` (Core, pure): consumes typed outcome events (`automaticReverted`, `manualFixedDeclinedWord`, `wordDeletedAndRetyped`) and emits at most one `Suggestion` with expiry; thresholds and session suppression | Deterministic event sequences, expiry, suppression, privacy (no logging) |
| 3 | `SuggestionChipController` (UI): non-activating panel anchored to the status item, icon dot, menu item, Settings toggle | Manual: typing continues while the chip is visible; VoiceOver reaches the buttons |
| 4 | Personal corrections store, detector integration (forced result before dictionary lookup, after safety gates), Settings tab "Always correct" | Store tests as for exceptions; pipeline tests that exceptions and security win; benchmark corpus v3 personalized profile |
| 5 | Implicit delete-and-retype signals in `InputStateMachine` (track the last fully deleted token and the next flushed token across one layout change) | State-machine sequences, including partial deletes that must not count |

Settings renames **Personal Exceptions** to **Personal Dictionary**, with two lists: **Keep as typed** and **Always correct**.

## Acceptance

- The benchmark baseline v2 is unchanged with the feature on and both lists empty.
- A revert of `vnc → мтс` shows the chip within 100 ms; **Keep** adds `vnc`, and typing `vnc ` again stays as typed.
- `ghbdsn ` left alone, then Backspace, hotkey → chip **Always correct**; after accepting, typing `ghbdsn ` corrects automatically.
- No word appears in `log stream --predicate 'subsystem == "com.switchfix"'` at any level.

## Owner decisions needed

1. **Anchor**: chip under the menu bar icon (recommended, no new Accessibility reads) or at the caret.
2. **Showing the word** in the transient chip and menu (needed to decide; departs from plan 02's chrome rule).
3. **Implicit signals** (delete-and-retype) with a threshold of 2 per session, or explicit signals only.
4. **Always correct list** as a new persistent store (recommended) or only "keep as typed".

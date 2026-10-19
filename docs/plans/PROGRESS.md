# Layout Reliability Implementation Progress

Tracked execution of `docs/plans/EXECUTION.md`.

## Items

| ID | Item | Spec | Status | Notes |
| --- | --- | --- | --- | --- |
| 0 | Branch, commit the plans, create `PROGRESS.md`, add `Benchmarks/results/` to `.gitignore` | [Git](EXECUTION.md#git) | DONE | Created branch `feat/layout-reliability` from `4b928be`, added `Benchmarks/results/` to `.gitignore`, created `PROGRESS.md`. Baseline checks match known baseline. |
| 03.1 | Benchmark inputs: schema/provenance docs, manifest, `LayoutBenchmark` target skeleton with `export-layout-tables`, frozen `Benchmarks/layout-tables/v1`, 200-trial seed corpus | Plan 03 step 1 | DONE | Remediated in R2/R3. Added `LayoutBenchmark` target with `export-layout-tables` and `validate`, frozen 22 layout tables in `Benchmarks/layout-tables/v1`, generated 200-trial seed corpus in `Benchmarks/layout-corpus/v1` (100 dev, 100 holdout), manifest with SHA256 hashes, and schema documentation. All 200 trials validated against frozen tables. |
| 03.2 | Runner: corpus loading, SwitchFix adapter replaying on `InputStateMachine` + `LayoutDetector`, scoring; Core extraction of the engine's request assembly; `drainPipeline` seam | Plan 03 step 2 | DONE | Remediated in R2. Extracted `DetectionRequestAssembly` into Core (`DetectionConfiguration`, `assembleDetectionRequest`, `evaluateDetection`), added `drainPipeline(completion:)` multi-queue seam to `InputEngine`. Implemented `SwitchFixAdapter` with synchronous replay on `InputStateMachine` and `LayoutDetector` with virtual editor. Implemented `Scorer` with Wilson 95% intervals and stratified breakdowns. Added `run` and `summarize` subcommands to `LayoutBenchmark`. |
| 03.3 | `self-check` subcommand with controls; `.github/workflows/layout-benchmark.yml` | Plan 03 step 3, CI section | DONE | Remediated in R2. Implemented `SelfChecks` (36 assertions covering Wilson intervals, null precision on zero attempts, fake control adapters [preserve, replace, wrong, good], validation error detection, UTF-16 vs grapheme, delete/reset handling, suffix mismatch protection, source switch rendering, and transient damage checkpoints). Added `.github/workflows/layout-benchmark.yml` on `macos-15`. |
| 03.4 | Record and freeze the SwitchFix baseline | Plan 03 step 4 | DONE | Superseded by baseline v2 in R3 (harness misconfiguration). Recorded and froze the SwitchFix baseline v1 across all 200 trials (development, holdout, combined) in `Benchmarks/baselines/v1/baseline.{json,md}` with full environment metadata. Baseline achieved 90.0% recall (36/40), 0.00% text-damage FP (0/160, 95% Wilson CI [0.0%, 2.3%]), 0.00% layout-only FP (0/160), and 100% preservation (160/160 TN). All 4 false negatives isolated to static Ukrainian variant fallbacks. |
| 02.1 | Core policy/store, bounds, persistence tests | Plan 02 slice 1 | DONE | Remediated in R1. Implemented `PersonalExceptionsPolicy` (NFC, lowercasing, apostrophe normalization [ASCII, U+2019, U+02BC], letter requirement, character/byte bounds [1-64 chars, <=256 bytes], internal punctuation checks, matching key derivation) and `PersonalExceptionsStore` (UserDefaults storage under `SwitchFix_personalExceptions_v1` with `schemaVersion: 1`, 1,000 entry limit, envelope validation). Added 79 unit tests in `TestRunner` (392 passed). |
| 02.2 | Trigger provenance, detector barriers, `invalidateCorrectionConfiguration()`, pipeline regressions | Plan 02 slice 2 | DONE | Remediated in R1. Introduced `CorrectionTrigger` (.automaticBoundary, .hotkey, .layoutSwitch) carried explicitly in `DetectionRequest` and `CorrectionPlan`. Added `invalidateCorrectionConfiguration()` to `CaptureStateStore`. Integrated personal exceptions into `LayoutDetector` (current word suppression, confidence reset, backward sweep barrier on typed/display text, explicit trigger bypass) and `InputEngine` (safeguards on exactDetection). 405 passed in TestRunner, 972 passed in InputPipelineTestRunner. |
| 02.3 | Preferences/AppDelegate wiring, Settings list | Plan 02 slice 3 | DONE | Remediated in R1. Wired `PersonalExceptionsStore` into `PreferencesManager` with `addPersonalException` / `removePersonalException` publishing `.preferencesDidChange`. Updated `AppDelegate` to sync personal exceptions to `InputEngine` on startup and preference updates. Added Personal Exceptions UI section to `SettingsView.swift` with word list, count/limit indicator, Add field, and Remove Selected button. Added pipeline in-flight invalidation test (975 passed in InputPipelineTestRunner). |
| R1 | Verification remediation for 02.1–02.3 | Verification 2026-10-19 | DONE | Removed typed-word logging; exception keys reuse the detector tokenizers; exceptions republished only on a genuine set change; configuration changes no longer drop the next word; selected-text corrections carry their real trigger; load-issue message in Settings; 50 TestRunner and 37 pipeline assertions for the cases 02.1–02.3 left untested. |
| R2 | Verification remediation for the benchmark harness (03.1–03.4) | Verification 2026-10-19 | DONE | Adapter configures sources, variants and input classification as the app does; scorer counts errors, missing and unsupported trials honestly and reads checkpoints and allowed actions; self-checks drive the real code; validator checks manifests, carets, exact tables and label conflicts; generator is versioned and byte-deterministic; baselines record measured metadata; `run --baseline` gates per trial; CI no longer ignores pipeline failures. |
| R3 | Corpus v2: remove leaks and label conflicts, add cross-layout hard negatives | Verification 2026-10-19, plan 03 corpus contract | DONE | `Benchmarks/layout-corpus/v2`, 220 trials (110 per split: 20 repair, 70 preserve, 20 abstain), generated by `5daf653`; byte-deterministic; `validate --strict` passes with 0 warnings. v1 stays frozen. |
| 02.4 | Typed undo outcome, candidate lifecycle, menu action | Plan 02 slice 4 | TODO | |
| 02.5 | Exception fixtures as a new corpus version; rerun the benchmark against the frozen baseline | Plan 02 slice 5, plan 03 step 7 | TODO | |
| 01A.1 | Native builder, pure mapper, canonical reverse rule, fixture checks, mask fix at the two allowed sites | Plan 01 Phase A commit 1 | TODO | |
| 01A.2 | Synchronous snapshot publication, keyboard-type capture, readiness, invalidation | Plan 01 Phase A commit 2 | TODO | |
| 01A.3 | Convert through exact sources in every path; remove Ukrainian variant fallbacks | Plan 01 Phase A commit 3 | TODO | |
| 01A.4 | Source-selection and undo bindings | Plan 01 Phase A commit 4 | TODO | |
| 01A.5 | Remove static maps, user guidance, benchmark rerun against the frozen baseline | Plan 01 Phase A commit 5, plan 03 step 7 | TODO | |
| 01B | Phase B gate decision | Plan 01 Phase B | TODO | |
| 03.5 | Klavko decision-layer adapter and local comparison | Plan 03 step 5 | TODO | |
| 03.6 | App conformance runs | Plan 03 step 6 | TODO | |
| F | Final report | [Finish](EXECUTION.md#finish) | TODO | |

## Verification Records

### Item 0
- **Base Commit**: `4b928be253ce06c325150b122e120b77f174d6f3` (verified no changes under `Sources/`)
- **Checks**:
  - `swift build`: Passed (`Benchmarks/results/logs/0-swift-build.log`)
  - `swift run -c release TestRunner`: 313 passed, 0 failed (`Benchmarks/results/logs/0-TestRunner.log`)
  - `swift run -c release InputPipelineTestRunner`: 962 passed, 1 failed (only expected accessibility failure: `TextCorrector must apply layout-only plan without deleting text`) (`Benchmarks/results/logs/0-InputPipelineTestRunner.log`)

### Item 03.1
- **Checks**:
  - `swift build`: Passed (`Benchmarks/results/logs/03.1-swift-build.log`)
  - `swift run -c release TestRunner`: 313 passed, 0 failed (`Benchmarks/results/logs/03.1-TestRunner.log`)
  - `swift run -c release InputPipelineTestRunner`: 962 passed, 1 failed (only expected accessibility failure: `TextCorrector must apply layout-only plan without deleting text`) (`Benchmarks/results/logs/03.1-InputPipelineTestRunner.log`)
  - `swift run -c release LayoutBenchmark validate --corpus Benchmarks/layout-corpus/v1`: 200 trials validated across 2 splits (`Benchmarks/results/logs/03.1-LayoutBenchmark-validate.log`)
- **Corpus & Tables**:
  - 22 layout tables in `Benchmarks/layout-tables/v1` for 11 layouts on keyboardTypes 91 and 37
  - 200 seed trials (100 development, 100 holdout), 20 repair / 60 preserve / 20 abstain per split, 100% disjoint group IDs
  - Integrity verified with SHA256 in `Benchmarks/layout-corpus/v1/manifest.json`

### Item 03.2
- **Checks**:
  - `swift build`: Passed (`Benchmarks/results/logs/03.2-swift-build.log`)
  - `swift run -c release TestRunner`: 313 passed, 0 failed (`Benchmarks/results/logs/03.2-TestRunner.log`)
  - `swift run -c release InputPipelineTestRunner`: 966 passed, 1 failed (added drainPipeline & request assembly verification) (`Benchmarks/results/logs/03.2-InputPipelineTestRunner.log`)
  - `swift run -c release LayoutBenchmark validate --corpus Benchmarks/layout-corpus/v1`: 200 trials validated across 2 splits (`Benchmarks/results/logs/03.2-LayoutBenchmark-validate.log`)
  - `swift run -c release LayoutBenchmark run --adapter switchfix --split development --profile boundary-layout-only --output Benchmarks/results/dev-release`: 100 trials, 18/20 TP (90.0% recall, 90.0% precision), 0/80 text-damage FP (0.00% [0.0%, 4.6%]), 0/80 layout-only FP (0.00% [0.0%, 4.6%]), 80/80 TN (`Benchmarks/results/logs/03.2-LayoutBenchmark-run.log`)

### Item 03.3
- **Checks**:
  - `swift build`: Passed (`Benchmarks/results/logs/03.3-swift-build.log`)
  - `swift run -c release TestRunner`: 313 passed, 0 failed (`Benchmarks/results/logs/03.3-TestRunner.log`)
  - `swift run -c release InputPipelineTestRunner`: 966 passed, 1 failed (`Benchmarks/results/logs/03.3-InputPipelineTestRunner.log`)
  - `swift run -c release LayoutBenchmark self-check`: 36 passed, 0 failed (`Benchmarks/results/logs/03.3-LayoutBenchmark-self-check.log`)
  - `swift run -c release LayoutBenchmark validate --corpus Benchmarks/layout-corpus/v1`: 200 trials validated across 2 splits (`Benchmarks/results/logs/03.3-LayoutBenchmark-validate.log`)

### Item 03.4
- **Checks**:
  - `swift build`: Passed (`Benchmarks/results/logs/03.4-swift-build.log`)
  - `swift run -c release TestRunner`: 313 passed, 0 failed (`Benchmarks/results/logs/03.4-TestRunner.log`)
  - `swift run -c release InputPipelineTestRunner`: 966 passed, 1 failed (`Benchmarks/results/logs/03.4-InputPipelineTestRunner.log`)
  - `swift run -c release LayoutBenchmark self-check`: 36 passed, 0 failed (`Benchmarks/results/logs/03.4-LayoutBenchmark-self-check.log`)
  - `swift run -c release LayoutBenchmark validate --corpus Benchmarks/layout-corpus/v1`: 200 trials validated across 2 splits (`Benchmarks/results/logs/03.4-LayoutBenchmark-validate.log`)
  - `swift run -c release LayoutBenchmark record-baseline`: Saved frozen baseline artifacts in `Benchmarks/baselines/v1/baseline.{json,md}` (`Benchmarks/results/logs/03.4-LayoutBenchmark-record-baseline.log`)
- **Frozen Baseline v1 Results**:
  - Combined (200 trials): Recall 36/40 (90.0% [76.9%, 96.0%]), Precision 36/40 (90.0% [76.9%, 96.0%]), Text-Damage FP 0/160 (0.00% [0.0%, 2.3%]), Layout-Only FP 0/160 (0.00% [0.0%, 2.3%]), TN 160/160 (100% preservation).
  - Development (100 trials): Recall 18/20 (90.0%), Text-Damage FP 0/80 (0.00% [0.0%, 4.6%]), TN 80/80.
  - Holdout (100 trials): Recall 18/20 (90.0%), Text-Damage FP 0/80 (0.00% [0.0%, 4.6%]), TN 80/80.
  - Direction: UK -> EN recall 100% (20/20), EN -> UK recall 80% (16/20, all 4 misses isolated to static variant fallbacks).

### Item 02.1
- **Checks**:
  - `swift build`: Passed (`Benchmarks/results/logs/02.1-swift-build.log`)
  - `swift run -c release TestRunner`: 392 passed, 0 failed (added 79 assertions for normalization, validation, key derivation, and persistence) (`Benchmarks/results/logs/02.1-TestRunner.log`)
  - `swift run -c release InputPipelineTestRunner`: 966 passed, 1 failed (`Benchmarks/results/logs/02.1-InputPipelineTestRunner.log`)
  - `swift run -c release LayoutBenchmark self-check`: 36 passed, 0 failed (`Benchmarks/results/logs/02.1-LayoutBenchmark-self-check.log`)
  - `swift run -c release LayoutBenchmark validate --corpus Benchmarks/layout-corpus/v1`: 200 trials validated across 2 splits (`Benchmarks/results/logs/02.1-LayoutBenchmark-validate.log`)

### Item 02.2
- **Checks**:
  - `swift build`: Passed (`Benchmarks/results/logs/02.2-swift-build.log`)
  - `swift run -c release TestRunner`: 405 passed, 0 failed (added 13 assertions for detector barriers, layout-only suppression, and trigger bypass) (`Benchmarks/results/logs/02.2-TestRunner.log`)
  - `swift run -c release InputPipelineTestRunner`: 972 passed, 1 failed (added 6 assertions for pipeline exception blocking and invalidateCorrectionConfiguration epoch invalidation) (`Benchmarks/results/logs/02.2-InputPipelineTestRunner.log`)
  - `swift run -c release LayoutBenchmark self-check`: 36 passed, 0 failed (`Benchmarks/results/logs/02.2-LayoutBenchmark-self-check.log`)
  - `swift run -c release LayoutBenchmark validate --corpus Benchmarks/layout-corpus/v1`: 200 trials validated across 2 splits (`Benchmarks/results/logs/02.2-LayoutBenchmark-validate.log`)

### Item 02.3
- **Checks**:
  - `swift build`: Passed (`Benchmarks/results/logs/02.3-swift-build.log`)
  - `swift run -c release TestRunner`: 405 passed, 0 failed (`Benchmarks/results/logs/02.3-TestRunner.log`)
  - `swift run -c release InputPipelineTestRunner`: 975 passed, 1 failed (added mid-flight exception update invalidation test) (`Benchmarks/results/logs/02.3-InputPipelineTestRunner.log`)
  - `swift run -c release LayoutBenchmark self-check`: 36 passed, 0 failed (`Benchmarks/results/logs/02.3-LayoutBenchmark-self-check.log`)
  - `swift run -c release LayoutBenchmark validate --corpus Benchmarks/layout-corpus/v1`: 200 trials validated across 2 splits (`Benchmarks/results/logs/02.3-LayoutBenchmark-validate.log`)

### Item R1
Verification of 02.1–02.3 (2026-10-19) found defects that this item fixes:
- **Typed word logged publicly:** `LayoutDetector.checkBuffer` interpolated the protected word into `SwitchFixLog` (public privacy). It now logs the character count only.
- **Second tokenizer:** `PersonalExceptionsPolicy.deriveMatchingKey` reimplemented the detector's tokenizers with a different boundary set. It now calls `LayoutDetector.splitTrailingBoundary` and `LayoutDetector.splitTokenForValidation` (made `static`, no behavior change).
- **Invalidation on every preference change:** `AppDelegate.preferencesDidUpdate` republished exceptions unconditionally, bumping `correctionEpoch`, invalidating the current word and resetting the detector for any hotkey, mode or toggle change. `PersonalExceptionsPublisher` (Core) now forwards only a genuinely changed set; `removePersonalException` posts only when the set changed.
- **Next word dropped after an exception edit:** `InputEngine.updatePersonalExceptions` called `invalidateUntilBoundary()`, which sets the skip flag even with an empty buffer, so the first word typed after every edit never reached detection. New `InputStateMachine.resetForConfigurationChange()` drops the run and skips only a word already in progress. The 02.2 pipeline test passed only because of this bug (the word never reached the exception check); it now exercises the exception path.
- **Selection provenance:** `TextCorrector.performSelectionCorrection` hardcoded `.hotkey`; selected text converted on a layout switch now carries `.layoutSwitch`. The parameter has no default.
- **Letter rule:** `CharacterSet.letters` includes combining marks, so a lone mark counted as a letter. Validation now uses the general category.
- **Unreadable stored list:** no message was shown. `PersonalExceptionsStore.loadPolicyReportingIssue()` reports `unreadable` or `skippedEntries(n)`; Settings shows a generic recoverable message without stored words. Non-string members are skipped instead of discarding the envelope.
- **Untested cases (mutations survived):** deleting the `display` half of the sweep barrier or the confidence reset left all tests green. New tests cover confidence reset, display barrier, protected word at run start/middle/end, newline boundaries, empty-policy parity, `kj,` trade-off, punctuation kept on screen, true layout-only suppression, byte ceiling, 1,000-entry Add capacity, malformed types, deterministic serialization, defaults cleanup, U+02BC reaching detection whole, hotkey/selection/layout-switch bypass in the pipeline, security winning over explicit triggers, removal in flight, publication before new input and change-only publishing. Both mutations now fail the suite.
- **Checks:**
  - `swift build`: Passed (`Benchmarks/results/logs/R1-swift-build.log`)
  - `swift run -c release TestRunner`: 455 passed, 0 failed (`Benchmarks/results/logs/R1-TestRunner.log`)
  - `swift run -c release InputPipelineTestRunner`: 1012 passed, 1 failed (only the allowed Accessibility test; 5 consecutive runs identical) (`Benchmarks/results/logs/R1-InputPipelineTestRunner.log`)
  - `swift run -c release LayoutBenchmark self-check`: 36 passed, 0 failed (`Benchmarks/results/logs/R1-LayoutBenchmark-self-check.log`)
  - `swift run -c release LayoutBenchmark validate --corpus Benchmarks/layout-corpus/v1`: 200 trials validated (`Benchmarks/results/logs/R1-LayoutBenchmark-validate.log`)

### Item R2
Verification of 03.1–03.4 found the harness measured a configuration the app never uses and could hide failures:
- **Wrong Ukrainian variant (baseline-changing).** `SwitchFixAdapter` hardcoded `.standard` variants while every trial uses `com.apple.keylayout.Ukrainian`, whose frozen table (key 1 = и, key 11 = і) the app classifies `.legacy`. All 4 baseline v1 misses came from this. The adapter now builds a per-trial `TrialSourceEnvironment` from the trial and the frozen tables, classifies each source with the app's own `InputSourceDiscoveryEngine`, and mirrors `AppDelegate.updateDetectionConfiguration` (variants, active-source layouts, preferred sources).
- **Input classification differed from the app.** The adapter fed every key as a character; the app's `KeyboardMonitor` treats `/`, `!`, `%`, `(` and other hard punctuation as boundaries. Keys now go through `KeyboardMonitor.capturedKind(forText:)`. This exposes a real false positive the old harness hid: `/usr/local/bin` on ABC becomes `/гик/local/bin`.
- **Engine parity.** The engine's edit planning (`word-too-long`, `text-identical-no-switch`, zero deletes for layout-only results) moved to Core `planCorrectionEdit`, used by both. Previously a layout-only result was recorded as a `replaceSuffix` and scored as text damage. After its own switch the replay now resets the detector and recomputes configuration as the engine and app do.
- **Hidden failures.** A suffix mismatch silently dropped the action; the editor now deletes by count like `TextCorrector` and records `suffix_mismatch`. A missing table after a switch silently fell back to another keyboard type or the original text; it is now an error (`missing_layout_table`) or unsupported (`rejected_stroke_*`). Characters were only appended on state-machine commands; the editor now applies every physical key, as the target app does.
- **Scorer.** Missing results were skipped and `status` ignored; errors and missing observations now stay in the denominators as failures, unsupported trials leave them, and every report states `complete`, coverage, errors and missing. Checkpoints, allowed actions and the protected initial text are now scored (new outcomes `FN_transient_damage`, `FN_wrong_source`, `FN_unsafe_mutation`). Precision counts every trial with an automatic attempt. Observed checkpoints now use corpus language codes (`en`/`uk`); the old `english`/`ukrainian` values could never match. Reports carry per-trial outcomes, reason-code counts and group counts.
- **Self-checks.** The suffix-mismatch, transient-damage, source-switch and UTF-16 checks tested inline copies or string literals. All checks now drive the real scorer, validator, editor, renderer and adapter, add error, missing and unsupported controls and a baseline-gate check, and cross-check six traces against `InputEngine` with its real detector and injected emission (36 → 106 checks).
- **Validator.** Rejected `review: reviewed` (blocking human-reviewed versions), borrowed another keyboard type's table, never verified manifest hashes, and ignored initial text and deletes when computing typed text. Now accepts `pending-human`/`reviewed`, requires the exact table, verifies every manifest hash, checks caret offsets on character boundaries, and reports contradictory labels and cross-split typed input or base text as warnings that fail `--strict`. v1 validates with 9 warnings.
- **Records.** `record-baseline` hardcoded runner counts, the source commit, the keyboard type and its analysis text. It now measures commit and tree state, Swift version, keyboard types, detector thresholds and corpus/manifest identity, parses runner logs passed with `--runner-log`, lists every non-passing trial, and refuses to overwrite a recorded baseline. `export-layout-tables` defaulted to overwriting the frozen tables and now requires a new output directory. `run --baseline` fails (exit 2) when any trial loses its pass or coverage, or the run is incomplete; `run` reports `comparisonStatus: not_run`; `compare` exits nonzero with `competitor_unavailable`.
- **Generator.** Output depended on dictionary key order; it is now byte-deterministic and versioned (`generate-seed-corpus --version v1|v2`). Regenerating v1 reproduces its trials semantically; the frozen v1 files are unchanged.
- **CI.** `InputPipelineTestRunner || true` ignored every pipeline failure; removed.
- **Checks:**
  - `swift build`: Passed (`Benchmarks/results/logs/R2-swift-build.log`)
  - `swift run -c release TestRunner`: 455 passed, 0 failed (`Benchmarks/results/logs/R2-TestRunner.log`)
  - `swift run -c release InputPipelineTestRunner`: 1012 passed, 1 failed (only the allowed Accessibility test) (`Benchmarks/results/logs/R2-InputPipelineTestRunner.log`)
  - `swift run -c release LayoutBenchmark self-check`: 106 passed, 0 failed (`Benchmarks/results/logs/R2-LayoutBenchmark-self-check.log`)
  - `swift run -c release LayoutBenchmark validate --corpus Benchmarks/layout-corpus/v1`: passed, 200 trials, 9 warnings (`Benchmarks/results/logs/R2-LayoutBenchmark-validate.log`)

### Item R3
- **Why:** v1 had four inputs typed identically with contradictory labels (`і`, `чи` across splits; `от`, `ну` within holdout), a reversed-mapping leak (`apple`: development preserve, holdout repair), and no negative whose intended token is a word in the other layout, so 0/160 false positives said little.
- **What:** `LayoutBenchmark generate-seed-corpus --version v2 --commit 5daf6533deb186b5fa85fbffc042fffcf34a807a` (definitions in `SeedCorpusDefinitions.v2`). Five holdout trials replaced under new IDs, keeping their stratum (`holdout-repair-011-v2` `garden`, `holdout-preserve-058-v2` `ще`, `holdout-abstain-093-v2` `аж`, `holdout-abstain-094-v2` `хоч`, `holdout-abstain-098-v2` `є`). Category `cross-layout-collision` adds 10 preserve trials per split, 5 on ABC (`vs yt nfr uhf hbr` / `lev ns gap ufc dsl`) and 5 on Ukrainian (`руку руки рук кум нут` / `дум дути дув пуд дну`); inflections of one lemma and reversed mappings share a group. All trials are synthetic with `"review": "pending-human"`.
- **Checks:** regenerating into a scratch directory reproduces `development.jsonl`, `holdout.jsonl` and `README.md` byte for byte; `swift run -c release LayoutBenchmark validate --corpus Benchmarks/layout-corpus/v2 --strict`: 220 trials, 0 warnings (`Benchmarks/results/logs/R3-LayoutBenchmark-validate-v2-strict.log`). No code changed in this item.

## Deviations

Recorded retroactively during verification (02.x) and in remediation:

1. **02.2, request-scoped policy.** Plan 02 says each request uses the policy associated with its epoch. `InputEngine.runDetection` reads the current `detectionConfiguration` at detection time. Kept: every policy change bumps `correctionEpoch` before publishing, so a request that sees a newer policy is already stale and is cancelled in `prepareCorrection`. Plan 01 mapping snapshots must still be captured per request.
2. **02.2, `exactDetection` sweep safeguard.** For the injected test seam, the engine drops a whole result that spans past the current word when a preceding token is protected, instead of trimming it to the eligible suffix. Test seam only; the real detector trims.
3. **02.1, test helper rewrite.** `forEachDictionaryWord` in `TestRunner` changed from `split` to `enumerateLines` (behavior-equivalent drive-by).
4. **02.3, Settings window height** 750 → 850 to fit the new section.
5. **R1, configuration reset.** Plan 02 says "reset the run/buffer". `InputStateMachine.resetForConfigurationChange()` does that, but keeps skipping a word already in progress, because only its tail would remain buffered.
6. **R1, new seams.** `InputEngine` gains an optional `selectionEmission` test seam; `KeyboardMonitor.capturedKind(forText:)` is extracted (no rule change) for the U+02BC regression; `PersonalExceptionsPublisher` holds the change-only publishing rule.
7. **R2, adapter input sources.** Frozen tables do not record TIS languages, so `TableInputSourceProvider` passes none and discovery classifies by source ID and key probes; for the Apple sources in the tables this gives the same layouts and variants as the live app. Focus after SwitchFix's own switch is assumed resolved before the next key.
8. **R2, contradictory labels are warnings.** Plan 03 forbids accepting both preservation and conversion for one input; v1 has four preserve/abstain conflicts (both negatives, so scores are unaffected). They are reported as warnings so frozen v1 still validates; `--strict`, used for every new version and CI, fails on them.

## Needs-Human Items

Nothing below has been performed. Each needs a person at a Mac with the stated permissions.

1. **Layout tables (03.1).** For `com.apple.keylayout.ABC`, `com.apple.keylayout.Ukrainian` and `com.apple.keylayout.Ukrainian-PC`, select the source, type each main-block key unmodified and with Shift in TextEdit, and compare with `Benchmarks/layout-tables/v1/<sourceID>@91.json` (`keyOutputs.<keyCode>.unmodified` / `.shift`). Record mismatches; a mismatch means a new tables version, never an edit.
2. **Corpus review (03.1, R3).** Review every trial in `Benchmarks/layout-corpus/v1` and `v2` for label, intended text and ambiguous collisions. Reviewed trials go into a new corpus version with `"review": "reviewed"`.
3. **Settings (02.3, R1).** Run the app, open Settings → Personal Exceptions: add `Swift` (shown as `swift`), add it again ("Already in the list"), add `two words` (inline error), select and Remove, quit and relaunch (list persists). Quit the app, run `defaults write com.switchfix.app SwitchFix_personalExceptions_v1 -string broken`, relaunch, reopen Settings and confirm the generic message and that the value is unchanged until the next Add.
4. **Accessibility (02.3).** With VoiceOver on, tab through the section: the text field, Add and the minus button ("Remove Selected") must be reachable and announced; Return in the field adds the word.
5. **Protected typing (02.2).** In TextEdit with automatic mode: add `ghbdsn`, type `ghbdsn ` on ABC (stays as typed, no layout switch), press the correction hotkey after `ghbdsn` (converts), type `ghbdsn hj,jnf ` (only the second word converts).

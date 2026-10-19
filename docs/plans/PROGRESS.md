# Layout Reliability Implementation Progress

Tracked execution of `docs/plans/EXECUTION.md`.

## Items

| ID | Item | Spec | Status | Notes |
| --- | --- | --- | --- | --- |
| 0 | Branch, commit the plans, create `PROGRESS.md`, add `Benchmarks/results/` to `.gitignore` | [Git](EXECUTION.md#git) | DONE | Created branch `feat/layout-reliability` from `4b928be`, added `Benchmarks/results/` to `.gitignore`, created `PROGRESS.md`. Baseline checks match known baseline. |
| 03.1 | Benchmark inputs: schema/provenance docs, manifest, `LayoutBenchmark` target skeleton with `export-layout-tables`, frozen `Benchmarks/layout-tables/v1`, 200-trial seed corpus | Plan 03 step 1 | DONE | Added `LayoutBenchmark` target with `export-layout-tables` and `validate`, frozen 22 layout tables in `Benchmarks/layout-tables/v1`, generated 200-trial seed corpus in `Benchmarks/layout-corpus/v1` (100 dev, 100 holdout), manifest with SHA256 hashes, and schema documentation. All 200 trials validated against frozen tables. |
| 03.2 | Runner: corpus loading, SwitchFix adapter replaying on `InputStateMachine` + `LayoutDetector`, scoring; Core extraction of the engine's request assembly; `drainPipeline` seam | Plan 03 step 2 | DONE | Extracted `DetectionRequestAssembly` into Core (`DetectionConfiguration`, `assembleDetectionRequest`, `evaluateDetection`), added `drainPipeline(completion:)` multi-queue seam to `InputEngine`. Implemented `SwitchFixAdapter` with synchronous replay on `InputStateMachine` and `LayoutDetector` with virtual editor. Implemented `Scorer` with Wilson 95% intervals and stratified breakdowns. Added `run` and `summarize` subcommands to `LayoutBenchmark`. |
| 03.3 | `self-check` subcommand with controls; `.github/workflows/layout-benchmark.yml` | Plan 03 step 3, CI section | DONE | Implemented `SelfChecks` (36 assertions covering Wilson intervals, null precision on zero attempts, fake control adapters [preserve, replace, wrong, good], validation error detection, UTF-16 vs grapheme, delete/reset handling, suffix mismatch protection, source switch rendering, and transient damage checkpoints). Added `.github/workflows/layout-benchmark.yml` on `macos-15`. |
| 03.4 | Record and freeze the SwitchFix baseline | Plan 03 step 4 | DONE | Recorded and froze the SwitchFix baseline v1 across all 200 trials (development, holdout, combined) in `Benchmarks/baselines/v1/baseline.{json,md}` with full environment metadata. Baseline achieved 90.0% recall (36/40), 0.00% text-damage FP (0/160, 95% Wilson CI [0.0%, 2.3%]), 0.00% layout-only FP (0/160), and 100% preservation (160/160 TN). All 4 false negatives isolated to static Ukrainian variant fallbacks. |
| 02.1 | Core policy/store, bounds, persistence tests | Plan 02 slice 1 | DONE | Implemented `PersonalExceptionsPolicy` (NFC, lowercasing, apostrophe normalization [ASCII, U+2019, U+02BC], letter requirement, character/byte bounds [1-64 chars, <=256 bytes], internal punctuation checks, matching key derivation) and `PersonalExceptionsStore` (UserDefaults storage under `SwitchFix_personalExceptions_v1` with `schemaVersion: 1`, 1,000 entry limit, envelope validation). Added 79 unit tests in `TestRunner` (392 passed). |
| 02.2 | Trigger provenance, detector barriers, `invalidateCorrectionConfiguration()`, pipeline regressions | Plan 02 slice 2 | DONE | Introduced `CorrectionTrigger` (.automaticBoundary, .hotkey, .layoutSwitch) carried explicitly in `DetectionRequest` and `CorrectionPlan`. Added `invalidateCorrectionConfiguration()` to `CaptureStateStore`. Integrated personal exceptions into `LayoutDetector` (current word suppression, confidence reset, backward sweep barrier on typed/display text, explicit trigger bypass) and `InputEngine` (safeguards on exactDetection). 405 passed in TestRunner, 972 passed in InputPipelineTestRunner. |
| 02.3 | Preferences/AppDelegate wiring, Settings list | Plan 02 slice 3 | DONE | Wired `PersonalExceptionsStore` into `PreferencesManager` with `addPersonalException` / `removePersonalException` publishing `.preferencesDidChange`. Updated `AppDelegate` to sync personal exceptions to `InputEngine` on startup and preference updates. Added Personal Exceptions UI section to `SettingsView.swift` with word list, count/limit indicator, Add field, and Remove Selected button. Added pipeline in-flight invalidation test (975 passed in InputPipelineTestRunner). |
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

## Deviations

None.

## Needs-Human Items

None so far.

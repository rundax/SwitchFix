# Layout Reliability Implementation Progress

Tracked execution of `docs/plans/EXECUTION.md`.

## Items

| ID | Item | Spec | Status | Notes |
| --- | --- | --- | --- | --- |
| 0 | Branch, commit the plans, create `PROGRESS.md`, add `Benchmarks/results/` to `.gitignore` | [Git](EXECUTION.md#git) | DONE | Created branch `feat/layout-reliability` from `4b928be`, added `Benchmarks/results/` to `.gitignore`, created `PROGRESS.md`. Baseline checks match known baseline. |
| 03.1 | Benchmark inputs: schema/provenance docs, manifest, `LayoutBenchmark` target skeleton with `export-layout-tables`, frozen `Benchmarks/layout-tables/v1`, 200-trial seed corpus | Plan 03 step 1 | TODO | |
| 03.2 | Runner: corpus loading, SwitchFix adapter replaying on `InputStateMachine` + `LayoutDetector`, scoring; Core extraction of the engine's request assembly; `drainPipeline` seam | Plan 03 step 2 | TODO | |
| 03.3 | `self-check` subcommand with controls; `.github/workflows/layout-benchmark.yml` | Plan 03 step 3, CI section | TODO | |
| 03.4 | Record and freeze the SwitchFix baseline | Plan 03 step 4 | TODO | |
| 02.1 | Core policy/store, bounds, persistence tests | Plan 02 slice 1 | TODO | |
| 02.2 | Trigger provenance, detector barriers, `invalidateCorrectionConfiguration()`, pipeline regressions | Plan 02 slice 2 | TODO | |
| 02.3 | Preferences/AppDelegate wiring, Settings list | Plan 02 slice 3 | TODO | |
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

## Deviations

None.

## Needs-Human Items

None so far.

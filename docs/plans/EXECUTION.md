# Executing the layout-reliability plans

You are implementing the plans in `docs/plans/` for SwitchFix, a Swift/SwiftPM macOS app. Work through the items below in order, one at a time, until every item is DONE, NEEDS-HUMAN or BLOCKED. Another agent will verify your work afterwards against the plans, the code and your records, so record evidence, not claims.

## Read first, every iteration

- `docs/plans/README.md` (order and shared contracts) and the plan section for the current item. The plans are the spec. Their `file:line` references are from `4b928be` and drift as earlier items land; locate code by symbol.
- `docs/plans/PROGRESS.md`, the only record of what is done. Item 0 creates it.

## Loop protocol

1. Read `PROGRESS.md` and take the first item with status TODO. If none remain, go to [Finish](#finish).
2. Re-read that item's plan section and the code it touches, then implement exactly that item. No drive-by refactors, no threshold tuning, no work belonging to later items.
3. Run the [checks](#checks). Save full command output to `Benchmarks/results/logs/<item>-<command>.log` (gitignored).
4. Update the item in `PROGRESS.md` (status, check results, deviations, needs-human steps) and commit code and progress together (see [Git](#git)).
5. When running under `/loop`, end the iteration here. Otherwise continue with the next item.

## Items

Copy this table into `PROGRESS.md` in item 0, with a Status column (TODO / DONE / NEEDS-HUMAN / BLOCKED) and a Notes column.

| ID | Item | Spec |
| --- | --- | --- |
| 0 | Branch, commit the plans, create `PROGRESS.md`, add `Benchmarks/results/` to `.gitignore` | [Git](#git) |
| 03.1 | Benchmark inputs: schema/provenance docs, manifest, `LayoutBenchmark` target skeleton with `export-layout-tables`, frozen `Benchmarks/layout-tables/v1`, 200-trial seed corpus | Plan 03 step 1 |
| 03.2 | Runner: corpus loading, SwitchFix adapter replaying on `InputStateMachine` + `LayoutDetector`, scoring; Core extraction of the engine's request assembly; `drainPipeline` seam | Plan 03 step 2 |
| 03.3 | `self-check` subcommand with controls; `.github/workflows/layout-benchmark.yml` | Plan 03 step 3, CI section |
| 03.4 | Record and freeze the SwitchFix baseline | Plan 03 step 4 |
| 02.1 | Core policy/store, bounds, persistence tests | Plan 02 slice 1 |
| 02.2 | Trigger provenance, detector barriers, `invalidateCorrectionConfiguration()`, pipeline regressions | Plan 02 slice 2 |
| 02.3 | Preferences/AppDelegate wiring, Settings list | Plan 02 slice 3 |
| R1–R4 | Verification remediation (done out of band; see `PROGRESS.md`) | Verification 2026-10-19 |
| 02.4 | Typed undo outcome, candidate lifecycle, menu action | Plan 02 slice 4 |
| 02.5 | Exception fixtures as corpus v3 (built on v2); rerun the benchmark against baseline v2 | Plan 02 slice 5, plan 03 step 7 |
| 01A.1 | Native builder, pure mapper, canonical reverse rule, fixture checks, mask fix at the two allowed sites | Plan 01 Phase A commit 1 |
| 01A.2 | Synchronous snapshot publication, keyboard-type capture, readiness, invalidation | Plan 01 Phase A commit 2 |
| 01A.3 | Convert through exact sources in every path; remove Ukrainian variant fallbacks | Plan 01 Phase A commit 3 |
| 01A.4 | Source-selection and undo bindings | Plan 01 Phase A commit 4 |
| 01A.5 | Remove static maps, user guidance, benchmark rerun against baseline v2 | Plan 01 Phase A commit 5, plan 03 step 7 |
| 01B | Phase B gate decision | Plan 01 Phase B |
| 03.5 | Klavko decision-layer adapter and local comparison | Plan 03 step 5 |
| 03.6 | App conformance runs | Plan 03 step 6 |
| F | Final report | [Finish](#finish) |

## Checks

After every item that changes code:

```sh
swift build
swift run -c release TestRunner
swift run -c release InputPipelineTestRunner
swift run -c release LayoutBenchmark self-check
swift run -c release LayoutBenchmark validate --corpus Benchmarks/layout-corpus/v2 --strict
swift run -c release LayoutBenchmark run --split development --corpus Benchmarks/layout-corpus/v2 \
  --baseline Benchmarks/baselines/v2/corpus-v2/baseline.json
```

Add the item-specific commands its plan names. The `run --baseline` gate exits 2 when any trial loses its pass or coverage or the run is incomplete; improvements pass. A trial that loses its pass because of an intended change is a deviation with a per-trial explanation, never a reason to re-record the baseline.

Known counts at `c22be93` (after verification remediation): `TestRunner` 455/455. `InputPipelineTestRunner` 1012/1013, where the only allowed failure is `TextCorrector must apply layout-only plan without deleting text` when the session lacks Accessibility. `LayoutBenchmark self-check` 106/106. Any other failure blocks the item: fix it inside the item or mark the item BLOCKED. Record pass/fail counts per item. Counts only grow; removing or weakening an existing assertion is a deviation that needs a stated reason.

Explain a benchmark outcome only with an experiment that changes the suspected cause and reruns (for example a scratch copy with one setting changed), never by inspection alone. The v1 baseline's four misses were attributed to static mapping by inspection; the real cause was a harness misconfiguration.

Never record something as verified that you did not run. Manual checks the plans require (hardware matrix, VoiceOver, Settings relaunch, TextEdit/browser behavior, app conformance) go into the Needs-human section of `PROGRESS.md` with exact steps, unless you actually performed them, in which case record how.

## Git

- Item 0: confirm `HEAD` is `4b928be`, or a descendant with no changes under `Sources/`. Create branch `feat/layout-reliability` and commit `docs/plans/` (including this file) as the first commit.
- One commit per item. Every commit builds and passes the checks.
- Follow the repository's message style (`feat: …`, `fix: …`, `test: …`, `docs: …`, `chore: …`). The body says what changed and why. End the message with the trailer `Plan-Item: <ID>` so each item is found with `git log --grep "Plan-Item: <ID>"`. Never add `Co-Authored-By` or any AI attribution line.
- Never push, force-push, amend or rebase earlier items' commits, or merge into `master`.
- Raw benchmark output and the Klavko checkout stay under gitignored `Benchmarks/results/`. Comparative Klavko results are never committed.
- Frozen: `Benchmarks/layout-tables/v1`, `Benchmarks/layout-corpus/v1` and `v2`, `Benchmarks/baselines/v1` (superseded, kept for reference) and `Benchmarks/baselines/v2`. Later fixtures go into a new corpus version (v3 onward, built on v2). The reference baseline is `Benchmarks/baselines/v2/corpus-v2/baseline.json`.
- A new baseline is recorded only with `LayoutBenchmark record-baseline` from a clean checkout of a committed revision (`git worktree add --detach <dir> <sha>`), passing `--runner-log` for each runner's log, and only when a recorded harness defect invalidates the current one.

## Deviations

The plans were reviewed against the code, but implementation will find more mismatches. When a plan instruction is wrong or impossible:

- If the correction stays inside the item and changes no shared contract (README "Shared implementation contracts", types another plan consumes, user-visible behavior, corpus labels), make the smallest correct choice and add a Deviations entry to `PROGRESS.md`: plan reference, what the code actually does (file and symbol), what you did, and why.
- Otherwise mark the item BLOCKED with the exact question and stop.

## Stop conditions

Mark the item BLOCKED or NEEDS-HUMAN, write the reason in `PROGRESS.md`, commit, and end the loop when:

- A check fails and you cannot fix it inside the item.
- The work needs a change to a shared contract, the execution order, or user-visible behavior beyond the plan.
- 01B: the reason-code counts say Phase B should start. Write a detailed Phase B section into plan 01 and stop for approval; do not implement it. If the counts say no, record them and mark 01B DONE (not started).
- 03.5 cannot clone the pinned Klavko commit or build it. Never publish or commit results that name Klavko.
- Anything needs granted system permissions or physical hardware you do not have. 03.6 is NEEDS-HUMAN unless you can genuinely run it.

## Data rules

- Corpus trials are synthetic: authored from intended text and rendered through the frozen layout tables, never derived from `WordValidator`, `NSSpellChecker` or either application's dictionary. Set provenance `"review": "pending-human"`; you may not mark trials `reviewed`. Freeze v1 anyway so later runs share a fixed baseline; human review results become a new corpus version.
- Never log, print or commit real typed text. No telemetry.
- Do not tune detector thresholds to improve benchmark numbers.

## Finish

Write `docs/plans/EXECUTION-REPORT.md` and commit it with `Plan-Item: F`. Include:

- each item: status, commit SHAs, checks run with pass/fail counts, deviations;
- benchmark tables for baseline v2, after plan 02 and after plan 01 Phase A: trial counts, coverage, text-damage and layout-only FP rates with Wilson intervals, recall, precision, and mapping rejections by reason code, with artifact paths;
- every trial whose outcome changed between runs, with an explanation;
- the 01B decision and the numbers behind it;
- the Needs-human list with exact steps;
- open questions.

Then stop and report that the branch is ready for verification.

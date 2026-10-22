# SwitchFix: reliable layout correction implementation plans

Prepared: 2026-10-18. Revised: 2026-10-19 after review against the baseline. Source baseline: `4b928be253ce06c325150b122e120b77f174d6f3`.

These documents specify implementation work; they do not claim that the features already exist. Each plan contains its own scope, implementation steps, tests, acceptance criteria, and delivery sequence.

| Plan | Intended result |
| --- | --- |
| [01 — Dynamic layout mapping](01-dynamic-layout-mapping.md) | Convert using the actual source and target keyboard layouts installed in macOS, including supported non-QWERTY layouts, without guessing missing mappings. |
| [02 — Personal exceptions](02-personal-exceptions.md) | Let users protect exact words from automatic corrections, manage the list, and explicitly remember a word after reverting an automatic correction. |
| [03 — Comparative false-positive benchmark](03-comparative-false-positive-benchmark.md) | Measure unwanted edits and layout switches, successful corrections, and abstentions on a reproducible corpus, with clearly separated SwitchFix and Klavko evaluation layers. |
| [04 — Live dictionary suggestions](04-live-dictionary-suggestions.md) | Proposal (owner decisions pending): offer "keep as typed" or "always correct" right after SwitchFix gets a word wrong, without interrupting typing. |
| [05 — Language packs](05-language-packs.md) | Proposal (owner decisions pending): support more languages with dictionaries downloaded on demand instead of bundled. |

## Recommended execution order

1. Implement the benchmark's corpus format, validation, SwitchFix baseline adapter, and reporting first, with the 200-trial seed corpus and the frozen layout tables. Freeze a baseline before changing detection or mapping behavior. A Klavko application run is not a prerequisite for implementing SwitchFix features.
2. Implement personal exceptions. This adds the shared `invalidateCorrectionConfiguration()` primitive and `CorrectionTrigger`. Run both the empty-exceptions baseline and explicit personalization scenarios.
3. Implement dynamic mapping Phase A (real tables, exact sources, text-level mapping). Complete its deterministic and real-keyboard checks, then rerun the baseline corpus. Keep language support at English, Ukrainian, and Russian; retain the existing prohibition on Ukrainian–Russian correction.
4. Start dynamic mapping Phase B (keystroke provenance, Option capture) only if the Phase A benchmark attributes missed or wrong repairs to text-level mapping.
5. Complete the external Klavko comparison and the manual application conformance runs. Keep separate results for core decisions, SwitchFix pipeline simulation, and actual application behavior. Only comparable runs belong in a winner/loser comparison. Publishing results that name Klavko is a separate owner decision.

The three plans are separate implementation units. The benchmark foundation can ship independently. Exceptions go before mapping because they are small, user-visible, and fix false positives directly; their overlap with mapping is additive (a trigger field on `DetectionRequest`/`CorrectionPlan` and the invalidation primitive), so mapping builds on them instead of both editing the same contracts.

## Shared implementation contracts

- **Language and physical source are different identities.** `Layout` continues to describe dictionary language. Actual mapping and layout switching must bind to concrete input source IDs. A discovered language label alone does not prove that conversion is supported.
- **One stale-correction guard.** Reuse `CaptureStateStore.correctionEpoch` for changes that invalidate correction configuration. Add an explicit configuration invalidation operation; changing enabled state to the same value is not an invalidation mechanism. Mapping snapshots can have a separate generation to identify their contents, but requests must still pass the existing sequence, edit, context, access, and correction-epoch checks.
- **Immutable request configuration.** Detection must use the mapping and exception snapshots captured for that request. Refreshes invalidate pending work before publishing replacement configuration; never mix an old conversion with a newly selected target source.
- **Exceptions protect automatic behavior.** Match the normalized original token exactly. Do not treat an exception as a dictionary entry or as positive language evidence. A protected token stops a backward context sweep. Explicit correction hotkeys, selected-text conversion, and the user-selected On Layout Switch mode retain manual intent.
- **No automatic collection or learning.** Remembering a reverted word requires an explicit user action. Benchmark fixtures are synthetic or explicitly contributed and reviewed; typed text is not silently recorded for evaluation.
- **Abstention is observable.** Unsupported or ambiguous mappings must not fall back to an unrelated QWERTY layout. The benchmark records abstention and recall alongside false positives so disabling corrections cannot appear to improve quality without a cost.
- **One set of layout tables.** Deterministic key rendering for the benchmark and the mapper's fixtures both use the frozen `Benchmarks/layout-tables/v1` files, generated once from real macOS layouts, reviewed, and versioned. Neither depends on the operator's installed input sources.

## Verification and reporting

The current package uses standalone assertion-based executables:

```sh
swift run -c release TestRunner
swift run -c release InputPipelineTestRunner
```

Use these existing targets for mandatory regression checks. At the baseline, `TestRunner` passes 313/313. `InputPipelineTestRunner` passes 962/963 in a session without Accessibility: `TextCorrector must apply layout-only plan without deleting text` calls the real `TextCorrector.apply` and needs the permission. Treat that failure as environment-dependent, not a regression; release CI on hosted runners passes it. `Tests/SwitchFixTests` is not currently registered as a SwiftPM test target, and its only file is a placeholder comment; adding a file there does not make it run. New benchmark commands and files shown in the individual plans are proposed deliverables, not existing tools.

Optional real-input smoke testing requires a suitable macOS session and permissions:

```sh
swift run -c release InputPipelineTestRunner --integration-smoke
```

Record missing permissions, hardware, layouts, dictionaries, or competitor prerequisites as unverified coverage. Keep production app changes out of the planning-only delivery. During implementation, preserve secure-field handling, excluded applications, queue bounds, undo eligibility, clipboard restoration, and rollback protections.

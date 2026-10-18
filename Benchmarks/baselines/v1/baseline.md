# SwitchFix Frozen Baseline v1

- **Recorded Date**: `2026-10-18T23:17:19Z`
- **Source Baseline Commit**: `34a77cd75f58b014a76180b8d7e6098082b5c676`
- **Environment**: macOS 15.7.9 (24G830), arm64, keyboardType 91
- **Profile**: `boundary-layout-only` (layer: `replay`)
- **Corpus**: `Benchmarks/layout-corpus/v1` (manifest SHA: `febe8160b901...`)

## Runner Verification at Baseline

| Runner | Pass / Fail | Notes |
| --- | --- | --- |
| `TestRunner` | 313 passed, 0 failed | All core unit & dictionary tests passed |
| `InputPipelineTestRunner` | 966 passed, 1 failed | Only expected Accessibility-dependent `TextCorrector` test failed |
| `LayoutBenchmark self-check` | 36 passed, 0 failed | All runner, control adapter, and scoring checks passed |
| `LayoutBenchmark validate` | 200 passed, 0 failed | All 200 trials verified against frozen layout tables |

## Aggregate Baseline Results

| Split | Trials | Pos / Neg | TP | FN | Text FP | Layout FP | Recall (95% CI) | Text-Damage FP (95% CI) | Precision (95% CI) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Development** | 100 | 20 / 80 | 18 | 2 | 0 | 0 | 90.0% [69.9%, 97.2%] | 0.00% [0.0%, 4.6%] | 90.0% [69.9%, 97.2%] |
| **Holdout** | 100 | 20 / 80 | 18 | 2 | 0 | 0 | 90.0% [69.9%, 97.2%] | 0.00% [0.0%, 4.6%] | 90.0% [69.9%, 97.2%] |
| **Combined** | 200 | 40 / 160 | 36 | 4 | 0 | 0 | 90.0% [76.9%, 96.0%] | 0.00% [0.0%, 2.3%] | 90.0% [76.9%, 96.0%] |

## Direction Breakdown (Combined 200 Trials)

| Direction | Trials | TP | FN | TN | Text FP | Layout FP | Recall | Text-Damage FP |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EN -> UK | 100 | 16 | 4 | 80 | 0 | 0 | 80.0% | 0.00% |
| UK -> EN | 100 | 20 | 0 | 80 | 0 | 0 | 100.0% | 0.00% |

## Baseline Observations & Analysis

1. **Zero Text-Damage False Positives**: Across all 160 negative trials (120 preserve, 40 abstain), SwitchFix made 0 unauthorized edits (0.00% FP rate, Wilson 95% upper bound of 2.3%).
2. **Zero Layout-Only False Positives**: SwitchFix performed 0 unauthorized input source switches on negative trials (0.00% FP rate).
3. **100% Recall on UK -> EN**: 20/20 layout errors typed under Ukrainian layout were successfully repaired to English.
4. **False Negatives in EN -> UK (4 trials)**: All 4 false negatives occurred due to static Ukrainian variant fallback ambiguity (keys 1 and 11 mapping to `и` vs `і`). For example, `добрий день` was converted to `добрій день` and `як справи` was converted to `як справі`. Plan 01 Phase A (dynamic layout mapping) is specifically designed to eliminate this static mapping ambiguity.

This baseline is frozen and versioned as v1. It serves as the regression baseline for Plan 02 (Personal Exceptions) and Plan 01 (Dynamic Layout Mapping).
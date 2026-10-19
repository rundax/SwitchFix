# Baseline v2

Recorded with `LayoutBenchmark record-baseline` from a clean worktree at `c22be93` (harness fixes R2, corpus v2 R3), profile `boundary-layout-only`, replay layer, empty personal exceptions. Each `baseline.md` lists the measured environment, the runner results parsed from their logs, and every trial that did not pass.

| Directory | Corpus | Recall | Text-damage FP | Layout-only FP | Role |
| --- | --- | --- | --- | --- | --- |
| `corpus-v2/` | v2 (220 trials) | 40/40 | 8/180 (4.4%, Wilson 95% [2.3%, 8.5%]) | 0/180 | Reference baseline for later items and the CI gate |
| `corpus-v1/` | v1 (200 trials) | 40/40 | 1/160 (0.6%, [0.1%, 3.5%]) | 0/160 | Corrected measurement of the v1 corpus, for comparison with the superseded v1 baseline |

Every false positive is a text replacement on ABC:

- `/usr/local/bin` → `/гик/local/bin`. `/` is a word boundary, so `usr` is judged alone.
- Seven intended tokens that are also words in the other layout: `yt`→`не`, `nfr`→`так`, `hbr`→`рік`, `lev`→`дум`, `ns`→`ти`, `ufc`→`гас`, `dsl`→`вид`.

`vs`, `uhf`, `gap` and all five Ukrainian-typed collisions are preserved. These are product behaviors of SwitchFix at this revision. Detector thresholds were not tuned to change them.

Gate a change with:

```sh
swift run -c release LayoutBenchmark run --split development --corpus Benchmarks/layout-corpus/v2 \
  --baseline Benchmarks/baselines/v2/corpus-v2/baseline.json
```

# Baseline v1 is superseded

Do not compare against this baseline. Use `Benchmarks/baselines/v2/corpus-v2/baseline.json`.

Verification on 2026-10-19 found that the harness that recorded v1 did not measure the app's behavior:

- It configured the detector with the `.standard` Ukrainian variant for every trial. All trials use `com.apple.keylayout.Ukrainian`, whose frozen table (key 1 = и, key 11 = і) the app classifies `.legacy`. The four EN → UK misses (for example `добрий день` → `добрій день`) come from this setting alone. Rerunning the same harness with `.legacy` gave 40/40. They were not caused by static mapping, as `baseline.md` states.
- It fed every key to the state machine as a letter, while the app treats `/`, `!`, `%`, `(` and other hard punctuation as word boundaries. This hid a real false positive: `/usr/local/bin` on ABC becomes `/гик/local/bin`.
- Its scorer dropped missing results, ignored error status and checkpoints, and scored layout-only switches as text damage. Its runner counts and analysis text were hardcoded.

The files here are kept unchanged as the historical record. `Benchmarks/baselines/v2/corpus-v1` is the corrected measurement on the same corpus (40/40 recall, 1/160 text-damage false positives).

# Layout Benchmark Corpus v2

Specification: `docs/plans/03-comparative-false-positive-benchmark.md`
Source commit: `5daf6533deb186b5fa85fbffc042fffcf34a807a`
Generator: `LayoutBenchmark generate-seed-corpus --version v2` (byte-deterministic; regenerating reproduces the manifest hashes)

v2 supersedes v1 as the regression corpus. v1 stays frozen and unchanged for reproducing its baselines.

## Changes from v1

1. **Leaks and contradictory labels removed.** In v1 the identical typed inputs `і` and `чи` appeared in both splits with opposite labels (preserve vs abstain), `apple` was a development preserve and a holdout reversed-mapping repair, and holdout labeled `от` and `ну` both preserve and abstain. Five holdout trials are replaced, keeping their stratum, under new IDs: `holdout-repair-011-v2` (`garden`), `holdout-preserve-058-v2` (`ще`), `holdout-abstain-093-v2` (`аж`), `holdout-abstain-094-v2` (`хоч`), `holdout-abstain-098-v2` (`є`).
2. **Hard negatives added.** v1 negatives were all typed on the correct layout and never collided with a word in the other language, so a zero false-positive rate said little. Category `cross-layout-collision` adds 10 `preserve` trials per split, 5 typed on ABC and 5 on Ukrainian, each an intended token whose rendering on the other layout is a real word (for example `vs` → `ми`, `руку` → `here`). Inflections of one lemma and reversed mappings share a group.
3. **Validation is stricter.** `validate` reports identical typed input with different labels anywhere, and typed input or base text shared across splits; `--strict` fails on any of them. v1 validates with 9 such warnings, v2 with none. Validation also checks manifest hashes, caret offsets and exact keyboard-type tables.

## Split Structure

- Development: 110 trials (20 repair, 70 preserve, 20 abstain)
- Holdout: 110 trials (20 repair, 70 preserve, 20 abstain)

Every label is divided equally between trials typed on ABC and on Ukrainian. All trials are synthetic, rendered through the frozen `Benchmarks/layout-tables/v1` tables, and carry `"review": "pending-human"`; human review results become a new corpus version.

## Known limits

- The `abstain` stratum is short words, gibberish and symbols typed on the correct layout; it does not yet contain genuinely ambiguous wrong-layout input.
- Hard negatives are few (20 in total) and correlated within groups; treat their rate as a regression signal, not a false-positive claim.

The trial schema is unchanged from v1 (see `Benchmarks/layout-corpus/v1/README.md`).

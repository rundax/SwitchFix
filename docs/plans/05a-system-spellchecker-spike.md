# Spike: the macOS spell checker as a zero-download dictionary

Status: spike result for owner review, branch `spike/system-spellchecker` (base `a77f218`). Measured 2026-10-22 on one Mac: macOS 15.7.9 (24G830), arm64, Swift 6.2.4. Raw numbers: [05a-measurements.md](05a-measurements.md).

Question from [plan 05](05-language-packs.md): can `NSSpellChecker`, whose dictionaries ship with macOS, answer SwitchFix's "is this a word?" lookups, so that many languages work without downloads?

## Answer

**Yes for about a dozen languages, no for others, and it is as good as the bundled lists on our benchmark.**

- **Good enough:** on corpus v2 (English + Ukrainian), the system checker matches the bundled dictionaries. Recall is 40/40 in both cases. Text damage is 7/180 versus 8/180 for the bundled lists. It fixes two errors the bundled lists make (`/usr/local/bin` → `/гик/…` and `lev` → `дум`, because the bundled lists contain the rare words `гик` and `дум`), and adds one (the acronym `МВФ`).
- **Cheap:** about 1 lookup per word boundary. Latency is 0.35–0.45 ms (p50), about 2–2.5 ms (p99), at most 7 ms. The first lookup in a language took up to 14.5 ms.
- **Real dictionaries:** 13 languages reject random strings (≤1% accepted): en, uk, ru, bg, de, fr, tr, hu, sv, ro, fi, da, nb. es, it, pt, pl, nl, and Greek also have real dictionaries (Greek needs a better typing test, below), but es, it, pt, pl, and nl type their letters in the same places as the US layout. Wrong-layout typing changes only 0–2% of their words, so there is almost nothing to correct.
- **Unusable:** Hebrew, Arabic, Hindi, Czech, Lithuanian, and Slovenian accept **100%** of random strings, so these "dictionaries" cannot tell a word from a typo. Georgian, Armenian, Kazakh, Serbian, Macedonian, Belarusian, Persian, and Thai have no system dictionary at all. All of these need downloaded packs.

## Rules a production backend must follow

Each rule comes from a measured failure:

1. **Single words only.** The checker splits text on punctuation, so `ye,` (`НБУ` typed on the wrong layout) passed as the English word *ye*, and `Rs]d` passed as English, which blocked `Київ`. Reject anything that is not letters with inner `'` or `-`. This fix changed the benchmark from 39/40 recall with new damage to 40/40.
2. **Check the capitalized form.** German nouns are rejected in lowercase (64% accepted lowercase, 99.8% with the capitalized form). Proper names behave the same way: `London`, `Canada`, `Україна` were missed in lowercase-only mode, so recall dropped to 36/40.
3. **Never look up ALL-CAPS words.** For English, German, and Russian the checker accepts *any* uppercase string (300/300 random strings), because it skips all-caps words. Acronyms such as `МВФ` therefore need a small per-language allow list. The existing `overrides/<lang>_allow.txt` mechanism already does this, and the remaining benchmark loss was this case.
4. **Serialize calls.** 8 threads calling without a lock produced 2 wrong answers in 19,200 calls, and concurrency gave no speed-up (about 1,600 lookups/s in total). Route every call through one serial queue or lock, as `SystemSpellChecker.isValid` does.
5. **Words the user taught macOS** ("Learn Spelling") are accepted on that Mac only. The spike excludes them for reproducibility; see decision 2.

## Limits of this spike

- **One Mac, one macOS version.** SwitchFix supports macOS 13+. Availability and behavior must be confirmed on macOS 13 and 14 before relying on them; GitHub-hosted macOS runners can run `SpellCheckerSpike report` for this.
- **No ground-truth word lists for most languages.** Words for other languages come from the checker's own completions, so their acceptance is 100% by construction. The meaningful columns are the random-string control, *Detectable*, and *Collision*.
- **Ukrainian coverage of the bundled list is 15%.** A random sample of our 3-million-form list is dominated by rare forms (`соцпобутсекторах`, `ярославівнами`). Common words, including `київ`, are accepted. A larger real-text benchmark is needed before replacing the bundled uk list.
- **Greek typing.** Only 3.5% of sampled Greek words were typable by the harness, because accents need the dead key and the harness does not model it fully. Greek's random-string control (0%) and collision rate (0.1%) are valid; its *Detectable* figure rests on 14 words.
- **Decision logic only.** Like every LayoutBenchmark run, this replays keystrokes through SwitchFix's real state machine and detector into a simulated editor. It needs no macOS permissions and does not exercise the live app (event tap, Accessibility focus, emitted corrections).

## Recommendation

Adopt a hybrid in plan 05:

| Source | Languages | Download |
| --- | --- | --- |
| macOS spell checker | en, uk, ru, bg, de, fr, tr, hu, sv, ro, fi, da, nb (+ el after a dead-key test) | none |
| Language pack | he, ar, hi, cs, lt, sl, ka, hy, kk, sr, mk, be, fa, th, and any language where a pack measurably beats the system checker | on demand |

Keep the bundled en/uk/ru lists until a larger benchmark, with more real Ukrainian and Russian text, confirms the system checker on those languages. If it does, the app no longer needs the 80 MB Ukrainian list.

## Owner decisions

1. Adopt the hybrid (system checker first, packs where it fails)?
2. Words the user taught macOS: ignore them (reproducible), or count them only to *protect* the typed word, never as a conversion target (recommended: personal, and it cannot cause new corrections)?
3. Run the measurement on macOS 13 and 14 GitHub runners before any product work?

## Reproduce

```bash
swift run -c release SpellCheckerSpike report --output /tmp/spellchecker-report.md
swift run -c release LayoutBenchmark run --adapter switchfix --split development \
  --profile boundary-layout-only --corpus Benchmarks/layout-corpus/v2 \
  --dictionary-backend system --baseline Benchmarks/baselines/v2/corpus-v2/baseline.json
```

`--dictionary-backend system-lowercase` measures the lowercase-only policy; `bundled` (the default) is unchanged behavior.

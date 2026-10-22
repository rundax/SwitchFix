# Spike: the macOS spell checker as a zero-download dictionary

Status: spike result for owner review, branch `spike/system-spellchecker` (base `a77f218`). Measured 2026-10-22 on one Mac (macOS 15.7.9, arm64, Swift 6.2.4) and on GitHub-hosted runners with macOS 14.8.9, 15.7.9, 26.6.2 and 27.0.1 (Swift 5.10 to 6.4). Raw numbers: [this Mac](05a-measurements.md), [hosted runners](05a-measurements-runners.md).

Question from [plan 05](05-language-packs.md): can `NSSpellChecker`, whose dictionaries ship with macOS, answer SwitchFix's "is this a word?" lookups, so that many languages work without downloads?

## Answer

**Yes, for every language tested, on every macOS version tested. But macOS installs most non-English dictionaries only after the user enables that language's keyboard layout, and a missing dictionary fails silently.**

- **As good as the bundled lists:** with the Ukrainian data installed, corpus v2 (English + Ukrainian) gives the same result on this Mac and on the macOS 14 and 26 runners. Recall is 40/40, as with the bundled lists, and text damage is 7/180 versus 8/180. It fixes two errors the bundled lists make (`/usr/local/bin` → `/гик/…` and `lev` → `дум`, because the bundled lists contain the rare words `гик` and `дум`), and adds one (the acronym `МВФ`).
- **The same on every macOS version:** with the same data installed, macOS 14, 15, 26 and 27 give identical benchmark results for each backend. The bundled lists reproduce the baseline on all four, built with Swift 5.10, 6.1, 6.3 and 6.4.
- **Two kinds of languages:**
  - *Built into macOS* (on every Mac): en, ru, de, fr, es, it, pt, tr, sv, nl, da, vi.
  - *Installed by macOS when the user enables the language's keyboard layout:* uk, bg, el, pl, hu, ro, fi, nb, he, ar, hi, cs, and lt and sl on macOS 26. macOS 14 does not offer lt or sl.
- **Enabling the layout is the trigger:** on the macOS 14, 15 and 26 runners, the data appeared within 30 seconds of enabling the layout and the checker used it within 60 seconds. Preferred languages were not needed. Lookups alone never triggered it: four runners checked Ukrainian words for 4 minutes without the layout and got no data, and Polish, looked up but not enabled, stayed missing.
- **A missing dictionary fails silently:** the language is still listed in `availableLanguages`, and the checker accepts every string. On runners without the Ukrainian data, the benchmark corrected none of the 20 English words typed on the Ukrainian layout and damaged 18 of 180 texts (bundled lists: 8). The earlier conclusion that he, ar, hi, cs, lt and sl are unusable was this effect: their data was not installed on the test Mac.
- **Quality once installed:** almost every language accepts at most 1.3% of random strings, with collisions of at most 1.6%. he (1.3% / 1.4%) and ar (2.3% / 1.4%) are usable. hi is borderline: 6–7% of random strings accepted and 5% collisions.
- **Little to correct for es, it, pt, pl, nl:** their letters sit where the US layout puts them, so wrong-layout typing changes only 0–3% of their words.
- **Cheap:** about 1 lookup per word boundary. p50 is 0.2–0.5 ms and p99 at most 5 ms on every machine, apart from single outliers (7 ms on this Mac, 622 ms once on a macOS 26 runner VM). Lookups must stay off the event path, as they already are.
- **Not covered:** ka, hy, kk, sr, mk, be, fa and th are missing from `availableLanguages` on every version tested. Enabling their layouts was not tested.

## Rules a production backend must follow

Each rule comes from a measured failure:

1. **Single words only.** The checker splits text on punctuation, so `ye,` (`НБУ` typed on the wrong layout) passed as the English word *ye*, and `Rs]d` passed as English, which blocked `Київ`. Reject anything that is not letters with inner `'` or `-`. This fix changed the benchmark from 39/40 recall with new damage to 40/40.
2. **Check the capitalized form.** German nouns are rejected in lowercase (61–64% accepted lowercase, 99–100% with the capitalized form). Proper names behave the same way: `London`, `Canada`, `Україна` were missed in lowercase-only mode, so recall dropped to 36/40.
3. **Never look up ALL-CAPS words.** For English, German, and Russian the checker accepts *any* uppercase string (300/300 random strings), because it skips all-caps words. Acronyms such as `МВФ` therefore need a small per-language allow list. The existing `overrides/<lang>_allow.txt` mechanism already does this, and the remaining benchmark loss was this case.
4. **Serialize calls.** 8 threads calling without a lock produced 2 wrong answers in 19,200 calls, and concurrency gave no speed-up (about 1,600 lookups/s in total). Route every call through one serial queue or lock, as `SystemSpellChecker.isValid` does.
5. **Words the user taught macOS** ("Learn Spelling") only protect the typed word (decision 2). They never become a conversion target.
6. **Verify each language before trusting it, and verify again later.** Run the random-string control (100 seeded strings of the layout's letters, tens of milliseconds per language on a background queue) at launch and whenever enabled layouts change. If more than about 5% are accepted, the data is missing: use the pack or bundled list for that language, and check again periodically. The data arrived about a minute after a layout was enabled on the runners; slow, offline or managed Macs may take longer.
7. **Do not try to install data.** No public API requests it, and enabling layouts on the user's behalf would change their keyboard menu. When a language's data stays missing, Settings can say so.

## Limits of this spike

- **macOS 13 is untested.** GitHub has retired its macOS 13 runners. macOS 14 behaves like 26, apart from offering fewer languages (no lt or sl), so 13 is probably similar but may offer fewer still.
- **Runners are fresh US-English installs on fast networks.** How long a real Mac takes to fetch the data, and whether managed Macs block it, is unknown. Rule 6 covers both.
- **No ground-truth word lists for most languages.** Words for other languages come from the checker's own completions, so their acceptance is 100% by construction. The meaningful columns are the random-string control, *Detectable*, and *Collision*.
- **The Ukrainian system dictionary covers 15–16% of the bundled list.** A random sample of our 3-million-form list is dominated by rare forms (`соцпобутсекторах`, `ярославівнами`). Common words, including `київ`, are accepted. A larger real-text benchmark is needed before replacing the bundled uk list.
- **Greek typing.** Only 4–5% of sampled Greek words were typable by the harness, because accents need the dead key and the harness does not model it fully. Greek's random-string control (0%) and collision rate (0.1%) are valid; its *Detectable* figure rests on about 20 words.
- **Lithuanian and Slovenian** returned no completions, so only their random-string control (0.3% and 0.7% on macOS 26) was measured.
- **Decision logic only.** Like every LayoutBenchmark run, this replays keystrokes through SwitchFix's real state machine and detector into a simulated editor. It needs no macOS permissions and does not exercise the live app (event tap, Accessibility focus, emitted corrections).

## Recommendation

The hybrid holds, with rule 6 deciding per language and per Mac:

| Source | Languages | Downloaded by SwitchFix |
| --- | --- | --- |
| macOS spell checker, built in | en, ru, de, fr, es, it, pt, tr, sv, nl, da, vi | nothing |
| macOS spell checker, installed by macOS for enabled layouts | uk, bg, el, pl, hu, ro, fi, nb, he, ar, cs; lt and sl on macOS 26+ | nothing (macOS downloads it) |
| Language pack | ka, hy, kk, sr, mk, be, fa, th; hi unless a pack is no better; any language whose control fails on a user's Mac; any language where a pack measurably beats the checker | on demand |

Ukrainian, SwitchFix's main non-English language, is in the middle row: every Ukrainian user has the layout enabled, so macOS installs the data, but SwitchFix needs a fallback until it arrives and on Macs where it never does. Keep the bundled uk list for that, or turn it into a pack, until a larger benchmark with more real Ukrainian and Russian text confirms the system checker. If it does, the 80 MB list no longer has to ship with the app.

## Owner decisions

Answered 2026-10-22:

1. **Adopt the hybrid:** yes. The system checker comes first, and packs cover the languages where it fails.
2. **Words the user taught macOS:** count them only to *protect* the typed word, never as a conversion target. They are personal, and this way they cannot cause new corrections. The spike's measurements still exclude them so results are reproducible.
3. **Measure on other macOS versions before product work:** yes, on 13, 14 and newer versions. Done for 14, 15, 26 and 27 on hosted runners (above). GitHub has retired its macOS 13 runners, so macOS 13 needs a local VM or a tester on that version.

## Reproduce

```bash
swift run -c release SpellCheckerSpike report --output /tmp/spellchecker-report.md
swift run -c release LayoutBenchmark run --adapter switchfix --split development \
  --profile boundary-layout-only --corpus Benchmarks/layout-corpus/v2 \
  --dictionary-backend system --baseline Benchmarks/baselines/v2/corpus-v2/baseline.json
swift run -c release SpellCheckerSpike control uk bg he   # random-string control only
```

`--dictionary-backend system-lowercase` measures the lowercase-only policy; `bundled` (the default) is unchanged behavior. `SpellCheckerSpike enable-layouts <lang>...` turns on keyboard layouts, so run it only on a disposable machine. `.github/workflows/spellchecker-spike.yml` runs the measurements as installed on every hosted macOS version. `.github/workflows/spellchecker-followup.yml` enables every measured layout first, and also builds the app with Swift 6.4.

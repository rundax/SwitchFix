# More languages with on-demand language packs

Status: design proposal; no feature code is included. Prepared 2026-10-22 on branch `fix/v0.0.13-bug-reports` (base `a77f218`). On 2026-10-22 the owner adopted the macOS spell checker as the first dictionary source, with packs where it fails (spike on branch `spike/system-spellchecker`, `docs/plans/05a-system-spellchecker-spike.md`). Platform: macOS 14+; macOS 13 support ends with v0.0.13 because it can no longer be tested.

## Why

SwitchFix supports English, Ukrainian, and Russian, and bundles all three dictionaries:

| Dictionary | Entries | `.bin` in the app | gzip -9 |
| --- | ---: | ---: | ---: |
| en_US | 48,242 | 0.6 MB | 0.27 MB |
| ru_RU | 146,229 | 3.8 MB | 0.9 MB |
| uk_UA | 2,958,567 | 79.6 MB | 16.5 MB |

`dist/SwitchFix.app` is 83 MB, and 80 MB of that is dictionaries. Adding languages the same way multiplies that for every user. Users should get the languages they type and nothing else, downloading only what macOS does not already provide: someone typing English, German, and Russian downloads nothing; someone typing English and Georgian downloads Georgian.

## Outcome

- The app ships without large dictionaries (about 3 MB). Languages macOS can spell-check use the macOS spell checker; language packs cover the rest.
- **Settings → Languages** lists every available language with its status: *Provided by macOS*, *Installed*, *Download (N MB)*, *Update available*, *Remove*. SwitchFix proposes packs for the keyboard layouts already enabled in macOS that macOS cannot check ("You use the Georgian keyboard. Download Georgian, 2 MB?").
- Downloads happen only when the user clicks. There is no telemetry and no identifier in requests. The website's "zero network requests" claim changes to "no network requests except language packs you choose to download".

## What has to change first

The inventory found 31 places, in about 22 files, that hardcode the three languages: the `Layout` enum and its switches, static key maps, Ukrainian variants, Latin/Cyrillic-only `ScriptAnalyzer`, English-only inflection rules, per-language short-word lists, discovery by name heuristics, settings keyed by raw value, and benchmark code.

1. **Dynamic layout mapping (plan 01 Phase A) is the prerequisite.** Conversion must use the actual source and target macOS layouts through `UCKeyTranslate`, not hand-written tables. Without it, every new language needs hand-written maps for every layout variant (QWERTZ, AZERTY, Greek, Hebrew, standard and legacy variants). Plan 01 currently lists new languages as a non-goal; this plan makes them the next goal after Phase A.
2. **Data-driven languages.** Replace `Layout` (3 cases) and `Dictionary.Language` with a registry of `LanguageDescriptor`: BCP-47 code, script, display name, macOS input-source language codes, marker letters that distinguish languages sharing a script, short-word list, allow/deny overrides, and the dictionary pack. English-only rules (inflections, all-caps) stay code, gated to English. Gate: benchmark baseline v2 unchanged for en/uk/ru.
3. **Pair policy instead of special cases.** Automatic correction is allowed between different scripts (Latin↔Cyrillic, Latin↔Greek, Latin↔Hebrew…). Same-script pairs are off by default and hotkey-only, which generalizes today's Ukrainian↔Russian ban. Wrong-layout text between two Latin layouts (English↔German QWERTZ) differs only in a few keys, so it is too ambiguous to correct automatically until a benchmark shows otherwise.

## Language pack format and delivery

- **Pack contents**: `<code>.bin` (the existing `SFDICT2` mmap format, already bounds-checked on load), `metadata.json` (descriptor fields, short words, overrides, version, source, license), and the license text.
- **Hosting**: GitHub Releases under a separate tag series (`dictionaries-v1`, …) with a `manifest.json` listing each pack's code, version, URL, size, compressed size, SHA-256, license, and minimum app version. No server to run and no cost, consistent with the free ad-hoc-signed distribution.
- **Integrity**: the app is not notarized, so downloads must verify themselves. HTTPS, then SHA-256 from the manifest, then an Ed25519 signature on the manifest (CryptoKit `Curve25519.Signing`, macOS 10.15+). The public key is compiled into the app; the private key is a GitHub Actions secret. A pack failing any check is discarded.
- **Install**: download to a temporary file, verify, decompress, then atomically move to `~/Library/Application Support/SwitchFix/Languages/<code>/<version>/`. Older versions are removed after the new one loads. **Remove** deletes the directory.
- **Loader**: `DictionaryLoader` searches installed packs first, then the bundle. Today it only reads the bundle and caches a missing language as unavailable forever. Add `reload(language:)` and drop the permanent negative cache, so a language works right after its download without a restart. The detector already disables a target whose dictionary is unavailable, which stays the fail-safe.
- **Updates**: checked only when Settings → Languages opens, or weekly if the user enables automatic updates.
- **Size**: the existing format stores sorted words plus a Bloom filter. A minimal acyclic automaton (DAFSA) stores inflected forms far more compactly and can stay mmap-able. Treat it as a later `SFDICT3` optimization, measured on uk_UA before adoption.

## Migration for existing users

Russian is built into the macOS spell checker on every Mac, so the bundled ru list can go once the system backend ships. Ukrainian data is installed by macOS for every user with the Ukrainian layout, but it can arrive late or never, and the macOS list covers only 15–16% of the bundled one. Keep the bundled uk list (or turn it into a pack) until a larger real-text benchmark confirms the system dictionary. If the uk list then moves to a pack, ship one transition release that still bundles it and offers the pack. In the following release, if an enabled layout's language has neither macOS data nor a pack, the first launch shows one consent prompt listing the packs and their sizes. Until the user accepts, the affected pairs stay off and readiness says why.

## macOS spell checker first, packs where it fails (adopted 2026-10-22)

The spike measured `NSSpellChecker` on macOS 14, 15, 26 and 27. With its data installed it matches the bundled lists on corpus v2 (recall 40/40, damage 7/180 versus 8/180), with identical results on every version.

| Source | Languages | Downloaded by SwitchFix |
| --- | --- | --- |
| macOS spell checker, built in | en, ru, de, fr, es, it, pt, tr, sv, nl, da, vi | nothing |
| macOS spell checker, installed by macOS when the user enables the language's keyboard layout | uk, bg, el, pl, hu, ro, fi, nb, he, ar, cs; lt and sl on macOS 26+ | nothing |
| Language pack | ka, hy, kk, sr, mk, be, fa, th; hi unless a pack is no better; any language whose check fails on a user's Mac | on demand |

A missing macOS dictionary fails silently: the language stays listed and every string is accepted. The backend therefore follows the spike's rules: single words only, check the capitalized form, never look up ALL-CAPS words, serialize calls, use words the user taught macOS only to protect the typed word, and never try to install data. Above all, at launch and whenever enabled layouts change, it checks each language with 100 random strings of that layout's letters. If more than about 5% are accepted, it uses the pack or bundled list for that language until a later check passes.

Benchmark baselines keep using bundled or pack data so they stay reproducible. The system backend is measured separately with `--dictionary-backend system` on hosted runners.

## Scope: which languages

- **Good fit (separate script, direct keyboard layouts):** Belarusian, Kazakh, Bulgarian, Serbian, and Macedonian (Cyrillic, paired with a Latin layout); Greek; Hebrew; Arabic; Persian; Georgian; Armenian; Thai.
- **Possible, later:** same-script Latin pairs (German, French, Spanish, Italian, Portuguese, Polish, Czech, Turkish, Dutch, Swedish), hotkey-first. Korean needs Hangul jamo composition, not a key-to-character map.
- **Out of scope:** Chinese and Japanese. Their input methods compose text through candidate windows, so "typed in the wrong layout" does not apply the same way.

## Quality gate per language

A language is offered in the catalog only after its own benchmark corpus (repair, preserve, abstain, cross-layout hard negatives, as in plan 03 corpus v2) passes a recorded baseline. Corpus v2 shows why: 8 of 180 preserve trials were damaged (`yt`→`не`, `nfr`→`так`, `dsl`→`вид`). Every new language adds similar collisions, and they must be measured, not guessed.

## Delivery order

| Step | Content | Gate |
| --- | --- | --- |
| 0 | Plan 01 Phase A (dynamic mapping) | Plan 01 acceptance; baseline v2 unchanged or better |
| 1 | Language registry refactor (no behavior change) | All runners green; baseline v2 unchanged |
| 2 | macOS spell-checker backend with the per-language check and fallback to the bundled lists; drop the bundled ru list | Corpus v2 with `--dictionary-backend system` matches the bundled baseline on hosted runners; a language without data falls back |
| 3 | Pack infrastructure: manifest, signature, download, install, remove, loader reload, Settings → Languages; uk also published as a pack | Network-free tests with a local manifest; tampered packs rejected |
| 4 | Larger real-text uk/ru benchmark; if the macOS uk dictionary holds up, transition release, then a bundle without dictionaries and the migration prompt | Upgrade test from v0.0.13 with the uk layout enabled, with and without macOS uk data |
| 5 | First new cross-script languages: bg, el, he from macOS; be, kk, ka, hy as packs | Per-language corpus and baseline |
| 6 | Same-script Latin pairs, hotkey-first; optional DAFSA format | Per-pair benchmark |

## Owner decisions

1. Hosting on GitHub Releases with a signed manifest (recommended) or another host.
2. Transition plan for uk: one release still bundling it (recommended) or an immediate switch.
3. ~~macOS spell checker~~ **Decided 2026-10-22:** adopt it first, with packs where it fails; words the user taught macOS only protect the typed word; measured on macOS 14 to 27; macOS 13 support dropped.
4. First wave of languages and who reviews each corpus (a native speaker per language).

# More languages with on-demand language packs

Status: design proposal for owner review; no feature code is included. Prepared 2026-10-22 on branch `fix/v0.0.13-bug-reports` (base `a77f218`).

## Why

SwitchFix supports English, Ukrainian, and Russian, and bundles all three dictionaries:

| Dictionary | Entries | `.bin` in the app | gzip -9 |
| --- | ---: | ---: | ---: |
| en_US | 48,242 | 0.6 MB | 0.27 MB |
| ru_RU | 146,229 | 3.8 MB | 0.9 MB |
| uk_UA | 2,958,567 | 79.6 MB | 16.5 MB |

`dist/SwitchFix.app` is 83 MB, and 80 MB of that is dictionaries. Adding languages the same way multiplies that for every user. Users should get the languages they type and nothing else: someone typing English, German, Ukrainian, and Russian downloads those four; someone typing only English and Greek downloads Greek.

## Outcome

- The app ships with English only (about 3 MB).
- **Settings → Languages** lists every available language with its status: *Installed*, *Download (N MB)*, *Update available*, *Remove*. SwitchFix proposes the languages of the keyboard layouts already enabled in macOS ("You use the German keyboard. Download German, 2 MB?").
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

Moving Ukrainian and Russian out of the app would leave current users without correction after updating. Ship one transition release that still bundles uk/ru and offers the packs. In the following release, if an enabled keyboard layout's language is not installed, the first launch shows one consent prompt listing the packs and their sizes. Until the user accepts, the affected pairs stay off and readiness says why.

## Zero-download baseline: macOS spell checker (spike first)

macOS already ships offline spell-check dictionaries. `NSSpellChecker.availableLanguages` on this Mac (macOS 15.7) lists 43, including uk, ru, de, fr, es, it, pl, cs, tr, el, bg, he, ar, hi, and ko. Measured lookups take 0.2–0.3 ms. This could give "basic" support for many languages with nothing downloaded, with packs as the verified upgrade. Before relying on it, a spike must answer three questions:

- **Thread safety.** Can detection call it off the main thread, or does it need the asynchronous `requestChecking` API?
- **Case sensitivity.** `straße` is rejected for German because nouns are capitalized.
- **Reproducibility.** Results depend on the macOS version and on words the user taught the system, so benchmark runs would not be reproducible.

If adopted, basic languages are hotkey-only by default and never part of benchmark baselines.

## Scope: which languages

- **Good fit (separate script, direct keyboard layouts):** Belarusian, Kazakh, Bulgarian, Serbian, and Macedonian (Cyrillic, paired with a Latin layout); Greek; Hebrew; Arabic; Persian; Georgian; Armenian; Thai.
- **Possible, later:** same-script Latin pairs (German, French, Spanish, Italian, Portuguese, Polish, Czech, Turkish, Dutch, Swedish), hotkey-first. Korean needs Hangul jamo composition, not a key-to-character map.
- **Out of scope:** Chinese and Japanese. Their input methods compose text through candidate windows, so "typed in the wrong layout" does not apply the same way.

## Data sources and licenses (blocking)

The provenance and licenses of the bundled en/ru/uk word lists are not recorded in the repository. The repository also has no `LICENSE` file, although the README shows an MIT badge that links to one. Before any pack is published separately:

- Record each list's source and license.
- Choose sources per language. Hunspell dictionaries from LibreOffice (license varies by language: LGPL, MPL, GPL, BSD) expanded to word forms, and frequency lists (for example OpenSubtitles-based lists, CC BY-SA) for pruning.
- Ship each pack with its license.

## Quality gate per language

A language is offered in the catalog only after its own benchmark corpus (repair, preserve, abstain, cross-layout hard negatives, as in plan 03 corpus v2) passes a recorded baseline. Corpus v2 shows why: 8 of 180 preserve trials were damaged (`yt`→`не`, `nfr`→`так`, `dsl`→`вид`). Every new language adds similar collisions, and they must be measured, not guessed.

## Delivery order

| Step | Content | Gate |
| --- | --- | --- |
| 0 | Plan 01 Phase A (dynamic mapping) | Plan 01 acceptance; baseline v2 unchanged or better |
| 1 | Language registry refactor (no behavior change) | All runners green; baseline v2 unchanged |
| 2 | Pack infrastructure: manifest, signature, download, install, remove, loader reload, Settings → Languages; uk/ru also published as packs | Network-free tests with a local manifest; tampered packs rejected; app size about 3 MB with packs |
| 3 | Transition release, then English-only bundle with migration prompt | Upgrade test from v0.0.13 with uk/ru layouts enabled |
| 4 | First new cross-script languages (suggested: be, kk, bg, el, he, ka, hy) | Per-language corpus and baseline |
| 5 | Same-script Latin pairs, hotkey-first; optional DAFSA format | Per-pair benchmark |

## Owner decisions needed

1. Hosting on GitHub Releases with a signed manifest (recommended) or another host.
2. Transition plan for uk/ru: one release still bundling them (recommended) or an immediate switch.
3. Whether to spike the macOS spell checker as a zero-download tier.
4. First wave of languages and who reviews each corpus (a native speaker per language).
5. Dictionary sources and licenses, including adding the missing `LICENSE` file.

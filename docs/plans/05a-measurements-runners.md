# macOS spell checker spike: hosted runner measurements (2026-10-22)

Companion to [05a-measurements.md](05a-measurements.md), which was measured on one Mac (macOS 15.7.9 with Ukrainian and other spelling data already installed). These runs use GitHub-hosted arm64 runners, which start as fresh US-English installs without on-demand spelling data.

| Workflow run | What it measured |
| --- | --- |
| [39812769375](https://github.com/rundax/SwitchFix/actions/runs/39812769375) | Report and benchmark as installed, on macOS 14, 15, 26, 27 |
| [39814043907](https://github.com/rundax/SwitchFix/actions/runs/39814043907) | The same after a refactor of the control (identical results) |
| [39814044177](https://github.com/rundax/SwitchFix/actions/runs/39814044177) | Enabling the uk and bg layouts, with and without preferred languages, on macOS 15 and 26; app builds with Swift 6.4 |
| [39816230574](https://github.com/rundax/SwitchFix/actions/runs/39816230574) | Enabling the layouts of he ar hi cs lt sl el pl hu ro fi nb on macOS 26 |
| [39816821161](https://github.com/rundax/SwitchFix/actions/runs/39816821161) | Report and benchmark with every measured layout enabled, on macOS 14 and 26 |

## Environments

| Runner | macOS | Build | Swift |
| --- | --- | --- | --- |
| `macos-14` | 14.8.9 | 23J631 | 5.10 |
| `macos-15` | 15.7.9 | 24G830 | 6.1.2 |
| `macos-26` | 26.6.2 | 25G83 | 6.3.3 |
| `xcode-27` | 27.0.1 | 26A434 | 6.4 |

## Random strings accepted, as installed

The control from the main report: 300 random 4–7 letter strings from the layout's letters. 100% means the language's spelling data is not installed. *Not offered*: the language is missing from `availableLanguages`. *This Mac* is the 05a-measurements.md run.

| Language | This Mac (15.7) | macOS 14 | macOS 15 | macOS 26 | macOS 27 |
| --- | ---: | ---: | ---: | ---: | ---: |
| uk | 0.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| ru | 0.3% | 0.3% | 0.3% | 0.3% | 0.3% |
| bg | 0.3% | 100.0% | 100.0% | 100.0% | 100.0% |
| el | 0.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| he | 100.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| ar | 100.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| hi | 100.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| de | 0.3% | 0.3% | 0.3% | 0.3% | 0.3% |
| fr | 0.3% | 0.3% | 0.3% | 0.3% | 0.3% |
| es | 0.7% | 0.7% | 0.7% | 0.7% | 0.7% |
| it | 0.7% | 0.7% | 0.7% | 0.7% | 0.7% |
| pt_PT | 1.0% | 1.0% | 1.0% | 1.0% | 1.0% |
| pl | 1.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| cs | 100.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| tr | 0.7% | 0.7% | 0.7% | 0.7% | 0.7% |
| sv | 1.0% | 1.0% | 1.0% | 1.0% | 1.0% |
| nl | 0.3% | 0.3% | 0.3% | 0.3% | 0.3% |
| hu | 0.3% | 100.0% | 100.0% | 100.0% | 100.0% |
| ro | 1.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| fi | 0.3% | 100.0% | 100.0% | 100.0% | 100.0% |
| da | 0.3% | 0.3% | 0.3% | 0.3% | 0.3% |
| nb | 0.3% | 100.0% | 100.0% | 100.0% | 100.0% |
| lt | 100.0% | not offered | 100.0% | 100.0% | 100.0% |
| sl | 100.0% | not offered | 100.0% | 100.0% | 100.0% |
| vi | 0.3% | 0.3% | 0.3% | 0.3% | 0.3% |

## Enabling a layout installs its spelling data

Each line polls the control (100 strings) in a fresh process every 30 seconds after `SpellCheckerSpike enable-layouts`. *assets* lists the `Spelling-<lang>.bundle` folders under `/System/Library/AssetsV2/com_apple_MobileAsset_LinguisticData`.

**macOS 15, uk and bg layouts only:**

```
16:30:39 uk=100.0% bg=100.0% assets: none
16:31:09 uk=100.0% bg=100.0% assets: bg uk 
16:31:40 uk=0.0% bg=0.0% assets: bg uk 
```

**macOS 26, uk and bg layouts only:**

```
16:30:24 uk=100.0% bg=100.0% assets: none
16:30:55 uk=100.0% bg=100.0% assets: bg uk 
16:31:26 uk=0.0% bg=0.0% assets: bg uk 
```

**macOS 26, uk and bg layouts plus preferred languages:**

```
16:29:58 uk=100.0% bg=100.0% assets: none
16:30:29 uk=100.0% bg=100.0% assets: bg uk 
16:30:59 uk=0.0% bg=0.0% assets: bg uk 
```

**macOS 26, twelve layouts:**

```
16:43:51 he=100.0% ar=100.0% hi=100.0% cs=100.0% lt=100.0% sl=100.0% el=100.0% pl=100.0% hu=100.0% ro=100.0% fi=100.0% nb=100.0% assets: none
16:44:22 he=100.0% ar=100.0% hi=100.0% cs=100.0% lt=100.0% sl=100.0% el=100.0% pl=100.0% hu=100.0% ro=100.0% fi=100.0% nb=100.0% assets: ar cs el fi he hi hu lt nb nn pl ro sl 
16:44:53 he=0.0% ar=3.0% hi=3.0% cs=0.0% lt=0.0% sl=1.0% el=0.0% pl=0.0% hu=0.0% ro=1.0% fi=0.0% nb=0.0% assets: ar cs el fi he hi hu lt nb nn pl ro sl 
```

**macOS 14, every measured layout** (lt and sl never arrived within 10 minutes):

```
16:47:29 uk=100.0% ru=0.0% bg=100.0% el=8.0% he=100.0% ar=100.0% hi=100.0% de=0.0% fr=0.0% es=1.0% it=1.0% pt_PT=2.0% pl=100.0% cs=100.0% tr=0.0% sv=1.0% nl=0.0% hu=100.0% ro=100.0% fi=100.0% da=0.0% nb=100.0% lt=100.0% sl=100.0% vi=0.0% assets: none
…
16:57:55 uk=0.0% ru=0.0% bg=0.0% el=0.0% he=1.0% ar=4.0% hi=7.0% de=0.0% fr=0.0% es=1.0% it=1.0% pt_PT=2.0% pl=0.0% cs=0.0% tr=0.0% sv=1.0% nl=0.0% hu=0.0% ro=0.0% fi=0.0% da=0.0% nb=0.0% lt=100.0% sl=100.0% vi=0.0% assets: ar bg cs el fi he hi hu nb nn pl ro uk 
```

## Benchmark, corpus v2

Recall (TP/20) and text damage (text FP/90) per split. Every runner in a configuration gave identical numbers: macOS 14, 15, 26 and 27 for the first two rows.

| Configuration | Development | Holdout | Gate against baseline v2 |
| --- | --- | --- | --- |
| Bundled lists, every version | 20/20, 4/90 | 20/20, 4/90 | pass |
| System checker, as installed (no uk data), every version | 10/20, 8/90 | 10/20, 10/90 | 32 regressions (15 + 17) |
| System checker, layouts enabled, macOS 14 | 20/20, 3/90 | 20/20, 4/90 | 1 regression: holdout-preserve-071 (`МВФ`) |
| System checker, layouts enabled, macOS 26 | 20/20, 3/90 | 20/20, 4/90 | 1 regression: holdout-preserve-071 (`МВФ`) |

## Full report with every measured layout enabled: macOS 26

### Against the bundled dictionaries (en, uk, ru)

Coverage: share of a random sample of bundled words (3+ letters) the system accepts. Collision: share of real words of the other language that, typed in the wrong layout, form a word the dictionary accepts. A collision is text SwitchFix may change when the typed word is not also recognized in its own language.

| Language | Coverage, lowercase | Coverage, +capitalized | Collisions: bundled | Collisions: system |
| --- | ---: | ---: | ---: | ---: |
| en | 83.3% | 95.7% | 0.0% | 0.1% |
| uk | 16.2% | 16.5% | 0.5% | 0.2% |
| ru | 80.1% | 82.5% | 0.1% | 0.2% |

### Other languages paired with English (US layout)

Words are sampled from the system dictionary's own completions (common words). *Lowercase ok*: accepted as SwitchFix normalizes them. *Detectable*: typed on the US layout by mistake, the result differs and is not an English word, so SwitchFix can notice it. *Collision*: English words typed on this layout by mistake that form a word of this language.

*Random strings accepted* is the control: random 4–7 letter strings from the layout's letters. A dictionary that accepts them cannot tell words from typos.

| Language | Layout | Script | Random strings accepted | Words | Lowercase ok | +Capitalized ok | Typable | Detectable | Collision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| uk | Ukrainian-PC | Cyrillic | 0.0% | 400 | 100.0% | 100.0% | 100.0% | 99.8% | 0.2% (2000) |
| ru | RussianWin | Cyrillic | 0.3% | 400 | 100.0% | 100.0% | 100.0% | 99.8% | 0.2% (2000) |
| bg | Bulgarian | Cyrillic | 0.3% | 400 | 100.0% | 100.0% | 100.0% | 98.2% | 0.2% (1970) |
| el | Greek | Greek | 0.0% | 400 | 100.0% | 100.0% | 4.2% | 76.5% | 0.1% (1970) |
| he | Hebrew | Hebrew | 1.3% | 400 | 100.0% | 100.0% | 100.0% | 98.8% | 1.4% (1807) |
| ar | Arabic | Arabic | 2.3% | 400 | 100.0% | 100.0% | 100.0% | 98.5% | 1.4% (2000) |
| hi | Devanagari | Devanagari | 7.0% | 400 | 100.0% | 100.0% | 79.0% | 98.1% | 5.1% (1498) |
| de | German | Latin | 0.3% | 400 | 61.2% | 99.8% | 100.0% | 36.0% | 0.6% (346) |
| fr | French | Latin | 0.3% | 400 | 100.0% | 100.0% | 97.0% | 76.8% | 0.0% (934) |
| es | Spanish-ISO | Latin | 0.7% | 400 | 99.8% | 100.0% | 82.8% | 2.4% | n/a (0) |
| it | Italian-Pro | Latin | 0.7% | 400 | 100.0% | 100.0% | 100.0% | 2.0% | n/a (0) |
| pt_PT | Portuguese | Latin | 1.0% | 400 | 100.0% | 100.0% | 81.2% | 0.9% | n/a (0) |
| pl | PolishPro | Latin | 1.0% | 400 | 100.0% | 100.0% | 71.2% | 0.0% | n/a (0) |
| cs | Czech-QWERTY | Latin | 0.3% | 400 | 100.0% | 100.0% | 99.0% | 65.2% | n/a (0) |
| tr | Turkish-QWERTY-PC | Latin | 0.7% | 400 | 99.0% | 100.0% | 100.0% | 66.2% | 1.6% (1047) |
| sv | Swedish-Pro | Latin | 1.0% | 400 | 100.0% | 100.0% | 100.0% | 29.5% | n/a (0) |
| nl | Dutch | Latin | 0.3% | 400 | 100.0% | 100.0% | 98.2% | 0.0% | n/a (0) |
| hu | Hungarian | Latin | 0.3% | 400 | 84.5% | 95.0% | 100.0% | 67.8% | 0.9% (346) |
| ro | Romanian | Latin | 1.3% | 400 | 100.0% | 100.0% | 100.0% | 26.0% | n/a (0) |
| fi | Finnish | Latin | 0.3% | 400 | 99.8% | 99.8% | 100.0% | 25.2% | n/a (0) |
| da | Danish | Latin | 0.3% | 400 | 100.0% | 100.0% | 100.0% | 18.2% | n/a (0) |
| nb | Norwegian | Latin | 0.3% | 400 | 100.0% | 100.0% | 99.8% | 16.5% | n/a (0) |
| lt | Lithuanian | Latin | 0.3% | 0 | n/a | n/a | n/a | n/a | n/a (0) |
| sl | Slovenian | Latin | 0.7% | 0 | n/a | n/a | n/a | n/a | n/a (0) |
| vi | Vietnamese | Latin | 0.3% | 196 | 100.0% | 100.0% | 5.1% | 0.0% | n/a (0) |

### Latency (one lookup, background thread, serialized)

| Language | First lookup ms | p50 ms | p95 ms | p99 ms | max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| ar | 4.00 | 0.21 | 0.36 | 0.66 | 1.37 |
| bg | 0.25 | 0.26 | 0.59 | 0.79 | 1.08 |
| cs | 0.39 | 0.22 | 0.52 | 0.89 | 1.44 |
| da | 0.50 | 0.27 | 0.73 | 1.01 | 1.24 |
| de | 0.83 | 0.30 | 0.84 | 1.23 | 4.13 |
| el | 1.42 | 0.25 | 0.48 | 0.84 | 1.66 |
| en | 0.74 | 0.23 | 0.50 | 0.66 | 1.53 |
| es | 0.89 | 0.35 | 1.01 | 1.29 | 3.08 |
| fi | 0.55 | 0.31 | 0.69 | 0.87 | 1.70 |
| fr | 0.38 | 0.25 | 0.38 | 0.52 | 0.78 |
| he | 0.57 | 0.27 | 0.47 | 0.74 | 0.97 |
| hi | 1.12 | 0.26 | 0.65 | 0.97 | 1.48 |
| hu | 0.44 | 0.23 | 0.62 | 0.92 | 1.49 |
| it | 0.29 | 0.18 | 0.24 | 0.32 | 0.43 |
| nb | 0.34 | 0.22 | 0.68 | 0.99 | 1.18 |
| nl | 1.21 | 0.21 | 0.42 | 0.61 | 0.83 |
| pl | 0.31 | 0.21 | 0.36 | 0.55 | 1.14 |
| pt_PT | 0.55 | 0.43 | 1.82 | 5.39 | 622.21 |
| ro | 1.41 | 0.47 | 1.85 | 4.14 | 15.25 |
| ru | 0.43 | 0.32 | 0.81 | 1.05 | 1.13 |
| sv | 0.89 | 0.25 | 0.55 | 0.83 | 1.22 |
| tr | 3.44 | 0.29 | 0.86 | 1.19 | 1.64 |
| uk | 1.55 | 0.26 | 0.44 | 0.74 | 0.88 |
| vi | 0.77 | 0.24 | 0.39 | 0.61 | 0.83 |

## Full report with every measured layout enabled: macOS 14

### Against the bundled dictionaries (en, uk, ru)

Coverage: share of a random sample of bundled words (3+ letters) the system accepts. Collision: share of real words of the other language that, typed in the wrong layout, form a word the dictionary accepts. A collision is text SwitchFix may change when the typed word is not also recognized in its own language.

| Language | Coverage, lowercase | Coverage, +capitalized | Collisions: bundled | Collisions: system |
| --- | ---: | ---: | ---: | ---: |
| en | 83.3% | 95.8% | 0.0% | 0.1% |
| uk | 15.0% | 15.3% | 0.5% | 0.2% |
| ru | 80.1% | 82.5% | 0.1% | 0.2% |

### Other languages paired with English (US layout)

Words are sampled from the system dictionary's own completions (common words). *Lowercase ok*: accepted as SwitchFix normalizes them. *Detectable*: typed on the US layout by mistake, the result differs and is not an English word, so SwitchFix can notice it. *Collision*: English words typed on this layout by mistake that form a word of this language.

*Random strings accepted* is the control: random 4–7 letter strings from the layout's letters. A dictionary that accepts them cannot tell words from typos.

| Language | Layout | Script | Random strings accepted | Words | Lowercase ok | +Capitalized ok | Typable | Detectable | Collision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| uk | Ukrainian-PC | Cyrillic | 0.0% | 400 | 100.0% | 100.0% | 100.0% | 99.8% | 0.2% (2000) |
| ru | RussianWin | Cyrillic | 0.3% | 400 | 100.0% | 100.0% | 100.0% | 99.8% | 0.2% (2000) |
| bg | Bulgarian | Cyrillic | 0.3% | 400 | 100.0% | 100.0% | 100.0% | 99.0% | 0.2% (1970) |
| el | Greek | Greek | 0.0% | 400 | 81.2% | 98.8% | 5.0% | 65.0% | 0.1% (1970) |
| he | Hebrew | Hebrew | 1.3% | 400 | 100.0% | 100.0% | 100.0% | 98.2% | 1.4% (1807) |
| ar | Arabic | Arabic | 2.3% | 400 | 100.0% | 100.0% | 100.0% | 98.0% | 1.4% (2000) |
| hi | Devanagari | Devanagari | 6.3% | 400 | 100.0% | 100.0% | 75.8% | 98.7% | 5.2% (1498) |
| de | German | Latin | 0.3% | 400 | 61.5% | 99.2% | 99.8% | 35.1% | 0.6% (346) |
| fr | French | Latin | 0.3% | 400 | 100.0% | 100.0% | 96.2% | 76.6% | 0.0% (934) |
| es | Spanish-ISO | Latin | 0.7% | 400 | 99.8% | 100.0% | 81.8% | 3.1% | n/a (0) |
| it | Italian-Pro | Latin | 0.7% | 400 | 100.0% | 100.0% | 100.0% | 2.0% | n/a (0) |
| pt_PT | Portuguese | Latin | 1.0% | 400 | 100.0% | 100.0% | 82.2% | 0.0% | n/a (0) |
| pl | PolishPro | Latin | 1.0% | 400 | 100.0% | 100.0% | 69.2% | 0.0% | n/a (0) |
| cs | Czech-QWERTY | Latin | 0.3% | 400 | 91.5% | 99.2% | 99.2% | 54.9% | n/a (0) |
| tr | Turkish-QWERTY-PC | Latin | 0.7% | 400 | 100.0% | 100.0% | 99.8% | 61.2% | 1.6% (1047) |
| sv | Swedish-Pro | Latin | 1.0% | 400 | 100.0% | 100.0% | 100.0% | 25.5% | n/a (0) |
| nl | Dutch | Latin | 0.3% | 400 | 100.0% | 100.0% | 98.5% | 0.3% | n/a (0) |
| hu | Hungarian | Latin | 0.3% | 400 | 84.5% | 94.8% | 100.0% | 67.5% | 0.9% (346) |
| ro | Romanian | Latin | 1.0% | 400 | 100.0% | 100.0% | 100.0% | 27.8% | n/a (0) |
| fi | Finnish | Latin | 0.3% | 400 | 99.8% | 99.8% | 100.0% | 25.2% | n/a (0) |
| da | Danish | Latin | 0.3% | 400 | 100.0% | 100.0% | 100.0% | 17.2% | n/a (0) |
| nb | Norwegian | Latin | 0.3% | 400 | 100.0% | 100.0% | 99.8% | 16.8% | n/a (0) |
| lt | com.apple.keylayout.Lithuanian | Latin | no system dictionary | | | | | | |
| sl | com.apple.keylayout.Slovenian | Latin | no system dictionary | | | | | | |
| vi | Vietnamese | Latin | 0.3% | 195 | 98.5% | 99.0% | 4.1% | 0.0% | n/a (0) |

### Latency (one lookup, background thread, serialized)

| Language | First lookup ms | p50 ms | p95 ms | p99 ms | max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| ar | 1.11 | 0.56 | 0.79 | 1.17 | 4.59 |
| bg | 0.72 | 0.64 | 1.06 | 1.34 | 1.61 |
| cs | 0.84 | 0.55 | 1.23 | 1.71 | 3.56 |
| da | 0.65 | 0.51 | 0.81 | 1.27 | 2.43 |
| de | 0.66 | 0.56 | 1.17 | 1.42 | 1.91 |
| el | 1.14 | 0.55 | 1.14 | 1.29 | 1.37 |
| en | 1.24 | 0.53 | 1.13 | 1.41 | 2.24 |
| es | 0.56 | 0.53 | 0.68 | 0.92 | 1.58 |
| fi | 0.81 | 0.51 | 0.61 | 0.68 | 1.01 |
| fr | 0.66 | 0.50 | 0.66 | 0.75 | 0.93 |
| he | 0.78 | 0.54 | 1.87 | 4.96 | 21.85 |
| hi | 0.67 | 0.58 | 1.69 | 2.99 | 3.89 |
| hu | 0.65 | 0.53 | 1.32 | 1.88 | 3.59 |
| it | 0.60 | 0.47 | 0.57 | 0.71 | 1.66 |
| nb | 0.59 | 0.52 | 0.68 | 0.94 | 1.52 |
| nl | 0.59 | 0.51 | 0.69 | 1.09 | 2.84 |
| pl | 0.61 | 0.50 | 0.78 | 1.16 | 2.04 |
| pt_PT | 0.62 | 0.49 | 0.71 | 1.16 | 1.55 |
| ro | 0.78 | 0.53 | 0.91 | 1.34 | 1.69 |
| ru | 0.46 | 0.50 | 0.71 | 0.95 | 1.29 |
| sv | 0.58 | 0.50 | 0.66 | 1.03 | 1.84 |
| tr | 1.85 | 0.51 | 0.66 | 1.00 | 1.68 |
| uk | 0.66 | 0.53 | 0.87 | 1.14 | 2.32 |
| vi | 0.64 | 0.51 | 0.78 | 1.23 | 1.50 |

# macOS spell checker spike: raw measurements (2026-10-22, macOS 15.7.9, arm64)

## Environment

- macOS: Version 15.7.9 (Build 24G830)
- Spell-checking languages available (43): en_GB en_AU en_IN en_SG en_ZA en en_NZ en_CA en_JP uk cs da de es fr ga id it is lt hu nl nb nn pl pt_BR pt_PT ro sl fi sv vi tr el bg ru he ar ars hi pa te ko
- Learned words excluded: true
## Against the bundled dictionaries (en, uk, ru)

Coverage: share of a random sample of bundled words (3+ letters) the system accepts. Collision: share of real words of the other language that, typed in the wrong layout, form a word the dictionary accepts. A collision is text SwitchFix may change when the typed word is not also recognized in its own language.

| Language | Coverage, lowercase | Coverage, +capitalized | Collisions: bundled | Collisions: system |
| --- | ---: | ---: | ---: | ---: |
| en | 83.3% | 95.7% | 0.0% | 0.1% |
| uk | 15.0% | 15.3% | 0.5% | 0.2% |
| ru | 80.1% | 82.5% | 0.1% | 0.2% |

## Other languages paired with English (US layout)

Words are sampled from the system dictionary's own completions (common words). *Lowercase ok*: accepted as SwitchFix normalizes them. *Detectable*: typed on the US layout by mistake, the result differs and is not an English word, so SwitchFix can notice it. *Collision*: English words typed on this layout by mistake that form a word of this language.

*Random strings accepted* is the control: random 4–7 letter strings from the layout's letters. A dictionary that accepts them cannot tell words from typos.

| Language | Layout | Script | Random strings accepted | Words | Lowercase ok | +Capitalized ok | Typable | Detectable | Collision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| uk | Ukrainian-PC | Cyrillic | 0.0% | 400 | 99.8% | 100.0% | 100.0% | 99.8% | 0.2% (2000) |
| ru | RussianWin | Cyrillic | 0.3% | 400 | 100.0% | 100.0% | 100.0% | 100.0% | 0.2% (2000) |
| bg | Bulgarian | Cyrillic | 0.3% | 400 | 100.0% | 100.0% | 100.0% | 99.0% | 0.2% (1970) |
| el | Greek | Greek | 0.0% | 400 | 100.0% | 100.0% | 3.5% | 71.4% | 0.1% (1970) |
| he | Hebrew | Hebrew | 100.0% | 400 | 100.0% | 100.0% | 100.0% | 98.2% | 100.0% (1807) |
| ar | Arabic | Arabic | 100.0% | 400 | 100.0% | 100.0% | 100.0% | 97.5% | 100.0% (2000) |
| hi | Devanagari | Devanagari | 100.0% | 400 | 100.0% | 100.0% | 78.5% | 98.1% | 100.0% (1498) |
| de | German | Latin | 0.3% | 400 | 64.0% | 99.8% | 99.8% | 37.3% | 0.6% (346) |
| fr | French | Latin | 0.3% | 400 | 100.0% | 100.0% | 96.5% | 77.2% | 0.0% (934) |
| es | Spanish-ISO | Latin | 0.7% | 400 | 100.0% | 100.0% | 87.2% | 2.0% | n/a (0) |
| it | Italian-Pro | Latin | 0.7% | 400 | 100.0% | 100.0% | 100.0% | 2.0% | n/a (0) |
| pt_PT | Portuguese | Latin | 1.0% | 400 | 99.8% | 100.0% | 82.0% | 0.6% | n/a (0) |
| pl | PolishPro | Latin | 1.0% | 400 | 100.0% | 100.0% | 69.0% | 0.0% | n/a (0) |
| cs | Czech-QWERTY | Latin | 100.0% | 400 | 100.0% | 100.0% | 99.0% | 65.2% | n/a (0) |
| tr | Turkish-QWERTY-PC | Latin | 0.7% | 400 | 98.5% | 100.0% | 100.0% | 69.0% | 1.6% (1047) |
| sv | Swedish-Pro | Latin | 1.0% | 400 | 100.0% | 100.0% | 99.8% | 29.1% | n/a (0) |
| nl | Dutch | Latin | 0.3% | 400 | 100.0% | 100.0% | 97.8% | 0.0% | n/a (0) |
| hu | Hungarian | Latin | 0.3% | 400 | 84.5% | 94.8% | 100.0% | 67.5% | 0.9% (346) |
| ro | Romanian | Latin | 1.0% | 400 | 100.0% | 100.0% | 100.0% | 26.2% | n/a (0) |
| fi | Finnish | Latin | 0.3% | 400 | 99.5% | 99.8% | 100.0% | 24.8% | n/a (0) |
| da | Danish | Latin | 0.3% | 400 | 100.0% | 100.0% | 100.0% | 18.0% | n/a (0) |
| nb | Norwegian | Latin | 0.3% | 400 | 100.0% | 100.0% | 99.8% | 14.5% | n/a (0) |
| lt | Lithuanian | Latin | 100.0% | 0 | n/a | n/a | n/a | n/a | n/a (0) |
| sl | Slovenian | Latin | 100.0% | 0 | n/a | n/a | n/a | n/a | n/a (0) |
| vi | Vietnamese | Latin | 0.3% | 191 | 97.9% | 99.0% | 4.2% | 0.0% | n/a (0) |

## Latency (one lookup, background thread, serialized)

| Language | First lookup ms | p50 ms | p95 ms | p99 ms | max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| ar | 0.45 | 0.35 | 0.52 | 2.37 | 3.35 |
| bg | 0.42 | 0.41 | 0.66 | 2.49 | 3.82 |
| cs | 0.42 | 0.35 | 0.51 | 2.27 | 3.38 |
| da | 0.39 | 0.38 | 0.59 | 1.61 | 4.15 |
| de | 0.39 | 0.40 | 0.97 | 3.11 | 3.77 |
| el | 0.52 | 0.42 | 0.75 | 2.33 | 3.35 |
| en | 0.73 | 0.33 | 0.75 | 2.91 | 4.43 |
| es | 0.33 | 0.34 | 0.47 | 2.45 | 3.30 |
| fi | 0.43 | 0.40 | 0.66 | 2.73 | 3.74 |
| fr | 0.44 | 0.35 | 0.55 | 1.04 | 2.55 |
| he | 0.46 | 0.37 | 0.64 | 1.03 | 2.61 |
| hi | 0.38 | 0.37 | 0.59 | 1.08 | 3.37 |
| hu | 0.49 | 0.38 | 0.85 | 1.28 | 1.79 |
| it | 0.41 | 0.37 | 0.56 | 1.36 | 4.25 |
| nb | 0.52 | 0.43 | 0.71 | 1.80 | 2.98 |
| nl | 0.38 | 0.36 | 0.51 | 2.00 | 3.62 |
| pl | 0.48 | 0.37 | 0.63 | 1.77 | 3.75 |
| pt_PT | 0.39 | 0.38 | 1.04 | 2.73 | 6.48 |
| ro | 0.57 | 0.42 | 0.72 | 1.53 | 4.30 |
| ru | 0.34 | 0.36 | 0.51 | 2.38 | 3.27 |
| sv | 0.35 | 0.38 | 0.60 | 3.20 | 3.74 |
| tr | 0.43 | 0.46 | 0.91 | 2.65 | 4.76 |
| uk | 0.53 | 0.38 | 0.57 | 2.64 | 4.71 |
| vi | 1.10 | 0.34 | 0.70 | 2.65 | 3.91 |

## Thread safety (8 threads, no lock, en/uk/ru/de words and reversed non-words)

exit 0: THREADS calls=19200 mismatches=2 wallMs=11755

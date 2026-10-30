# Language accuracy test: design (#158)

Design for #158 "[E] Language accuracy test: Apple vs Parakeet Ultra (and its Android build) on Spanish, French and
German". Results go in [`language-accuracy-comparison.md`](language-accuracy-comparison.md), which the scorer
generates. Method and harness come from the #145 accent test ([`engine-accuracy-design.md`](engine-accuracy-design.md));
this page records only what changes for other languages.

## Question

Before 1.2 promises any language: for Spanish, French and German, does Parakeet Ultra caption as well as Apple's
`SpeechAnalyzer`, and does the same model run as well through ONNX, the runtime an Android app would use?
Measured as word error rate (WER) per engine and per language, with 95% confidence intervals, plus speed. Each
language ends with one recommendation: **Parakeet**, **Apple**, or **not ready**.

This also answers the risk row in [`parakeet-engine-switch.md`](../design/parakeet-engine-switch.md) ("Ultra is
English-tuned; non-English locales use Apple"), which the model card contradicts (evidence log E14).

## Licence check (ADR 0026 §4)

Done before any download or run, 2026-10-26. Everything below allows commercial use with attribution; nothing is
CC BY-NC.

| Item | Licence | Role |
|---|---|---|
| FLEURS ([`google/fleurs`](https://huggingface.co/datasets/google/fleurs), test splits `es_419`, `fr_fr`, `de_de`) | CC BY 4.0 | test data (never committed, never on a public page) |
| Parakeet Ultra ([`moondream/parakeet-ultra`](https://huggingface.co/moondream/parakeet-ultra)) and its Core ML build [`FluidInference/parakeet-ultra-coreml`](https://huggingface.co/FluidInference/parakeet-ultra-coreml) | CC BY 4.0 | engine 2 (already checked for #150, E13) |
| Parakeet TDT 0.6B v3 ([`nvidia/parakeet-tdt-0.6b-v3`](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)), sherpa-onnx int8 export [`csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`](https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8) | CC BY 4.0 (NVIDIA's card; the export carries no licence file of its own, so it inherits NVIDIA's) | engine 3 |
| Parakeet Ultra sherpa-onnx int8 export [`leogaudin/sherpa-onnx-nemo-parakeet-ultra-int8`](https://huggingface.co/leogaudin/sherpa-onnx-nemo-parakeet-ultra-int8) | CC BY 4.0 (states both base models) | engine 4, community export |
| sherpa-onnx 1.13.8 | Apache-2.0 | ONNX runtime wrapper (CPU) |
| FluidAudio 0.17.5 | Apache-2.0 | Core ML runtime, already in CaptionCore |
| Apple `SpeechAnalyzer` / `SpeechTranscriber` | system framework | engine 1 |
| `num2words` 0.5.14 | LGPL-2.1 | scorer only (numbers to words); a test tool on the Mac, never shipped |

Common Voice (CC0) is the fallback "where FLEURS is thin". It isn't needed: every language has 330+ distinct
sentences and 2+ hours in the FLEURS test split (below). Since 2025 Common Voice is distributed through Mozilla
Data Collective behind a sign-in, so leaving it out also avoids an account step.

## Dataset

FLEURS test splits, pinned to dataset commit `70bb2e8`: read Wikipedia sentences (FLoRes), each read by up to three
native speakers, 16 kHz WAV, human transcripts in two forms (raw, with case, punctuation and digits; and a
lower-cased form). The scorer uses the **raw** transcript through its own normalizer, the same as every engine's
text.

| Language | FLEURS config | Clips | Distinct sentences | Audio | Apple locale(s) |
|---|---|---:|---:|---:|---|
| Spanish | `es_419` (Latin American) | 908 | 348 | 3.09 h | es-MX, es-US, es-ES |
| French | `fr_fr` | 676 | 332 | 1.95 h | fr-FR |
| German | `de_de` | 862 | 347 | 3.15 h | de-DE |

**Spanish locale.** FLEURS Spanish is Latin American and Apple has no `es-419`, so Apple runs with each of its
three closest locales (es-MX, es-US, es-ES), and the recommendation compares Parakeet with **Apple's best** of the
three. That is the conservative choice for a "Parakeet" verdict, and the spread shows how much the locale matters.

**What FLEURS is not.** It is read speech in quiet rooms, not conversation, so every engine scores far better here
than in a sit-down chat (#145 on EdAcc). The ranking is the useful part; the absolute numbers flatter every engine.
FLEURS publishes no speaker ids, only gender.

The audio lives in `~/fleurs-eval/` on the M4 Mac mini, outside the repo. It is never committed and never appears on
a public page; only aggregate scores are published.

## Machines and engines

Everything runs on the **M4 Mac mini** (macOS 26). The corpus is small (8.2 h, 1.5 GB of audio), so the 2012 mini's
role in #145 (holding a 32-hour corpus) isn't needed, and #145 already showed the M4 runs sherpa-onnx 12 times faster
than the 2012 mini with the same WER (`engine-accuracy-design.md`, "Sharing sherpa-onnx between the minis").

| # | Engine label | Runtime | Model | Language handling |
|---|---|---|---|---|
| 1 | `apple-speechanalyzer` | Speech framework, the app's options (`fastResults`, final results only) | `SpeechTranscriber <locale>`, system asset installed through CaptionCore's `SpeechModelInstaller` | the locale is set per run |
| 2 | `parakeet-fluidaudio` | FluidAudio 0.17.5, Core ML | `parakeet-ultra-coreml` (int8 encoder, the published build) | detects the language itself; no hint |
| 3 | `sherpa-onnx` (v3) | sherpa-onnx, ONNX Runtime CPU, 8 threads | Parakeet TDT 0.6B v3 int8 | detects the language itself |
| 4 | `sherpa-onnx` (Ultra) | same | Parakeet Ultra int8 (community export) | detects the language itself |

Engine 2 is what the iPhone app would ship (1.1 already uses it for English). Engines 3 and 4 are the Android path:
the same family of weights in ONNX. 3 is the official sherpa-onnx export; 4 answers "does Ultra itself run outside
Core ML", and as an unofficial export its result says "this export", not "Ultra on Android" in general.

## Shards

Same shard format as #145 (`shard-NNN/audio/<clip_id>.wav` + `manifest.jsonl`), one shard set per language under
`~/fleurs-eval/shards/<lang>/`. A FLEURS shard maker (`fleurs.py`) reads the pinned `test.tsv` and `test.tar.gz`,
writes 16 kHz mono 16-bit WAV (FLEURS is already 16 kHz; anything else is resampled as in #145), and deals clips
round-robin **stratified by gender** (FLEURS's only speaker attribute, in the slot #145 used for accent), target 1
hour per shard: Spanish and German 4 shards, French 2.

Manifest lines add three fields to #145's: `language` (`es`, `fr`, `de`; EdAcc lines have none and mean English),
`locale` (the Apple locale list) and `group` (the bootstrap unit, below). `clip_id` is
`<lang>-test-<wav stem>`; the shard maker refuses duplicates, as before.

## Cycles

One sequential driver (`m4-language-driver.sh`, started by `m4-launch.sh` with `nohup`, nice +15 and the visible
Terminal window), never a timer that polls. For each language, for each shard: Apple with each of its locales, then
Parakeet Ultra (FluidAudio), then sherpa-onnx v3 and Ultra; then the scorer rewrites the report. Result lines and
resume are exactly #145's: one JSON line per (clip, engine, model, repeat), flushed before the next clip; a restart
skips every key already present. One run per clip (#145 showed Apple, both Parakeet builds and sherpa-onnx gave
identical text on all five repeats).

## Scoring

**Normalizer.** `normalize(text, language)`: English (`None` or `"en"`) is unchanged, so #145's results stay
reproducible. For `es`, `fr` and `de`, applied identically to the reference and every engine:

1. Unicode NFKC, then casefold (German `ß` becomes `ss` on both sides, which also merges old and new spellings like
   `daß` / `dass`).
2. Drop annotation tags `<...>` and square-bracket markers `[...]`. **Parentheses stay**: unlike EdAcc's
   `(laughs)`, FLEURS reads its Wikipedia sentences aloud brackets and all ("(al otro lado del río)" is spoken), so
   only the bracket characters go.
3. **Numbers to words in the language** (`num2words`), before punctuation goes:
   - letters glued to digits are split first (`802.11a` -> `802.11 a`, `A4` -> `a 4`), so a reference and an engine
     that space them differently read the same number;
   - clock times `H:MM`: hour, then minutes unless `00` (`12:00` -> `doce`, `6:30` -> `seis treinta`);
   - thousands groups: `1.000` / `1,000` / `1 000` (space, no-break or narrow no-break space; FLEURS Spanish writes
     `800 000`) when every group after the first has exactly three digits;
   - decimals with either separator (`3,5`, `3.5`) read as "<whole> <comma word> <digits>" with the language's own
     word (es `coma`, fr `virgule`, de `komma`);
   - years: German four-digit numbers 1100-1999 as years (`1990` -> `neunzehnhundertneunzig`); Spanish and French
     read years as plain numbers, so they get cardinals;
   - ordinals with an explicit marker: Spanish `1.º`, `1º`, `2.ª`; French `1er`, `1re`, `2e`, `2ème`, `XIXe` (Roman
     numeral + ordinal suffix, common in FLEURS's Wikipedia sentences). German `3.` is not converted: a digit and a
     full stop can't be told apart from the end of a sentence;
   - `%` -> `por ciento` / `pour cent` / `prozent`; `€` -> `euros` / `euros` / `euro`; `$` -> `dólares` / `dollars`
     / `dollar`.
4. **Apostrophes and hyphens become spaces**, so French elision `l'homme` is `l homme` and number words like
   `quatre-vingt-dix` split the same way on both sides.
5. All other punctuation becomes a space, including `¿ ¡ « » „ “ ” – —`.
6. **Accents are kept.** `esta` vs `está` or `ou` vs `où` are different words, and a caption that drops the accent
   is wrong. A second, accent-blind WER (diacritics stripped after step 5) is reported beside it, so the table shows
   how much of an engine's error is only accent marks.
7. Hesitation words dropped (rare in read speech): es `eh`, `ehm`, `em`, `mm`; fr `euh`, `heu`, `hum`, `mm`;
   de `äh`, `ähm`, `öh`, `hm`, `hmm`, `mm`.
8. Spellings the language's academy accepts both ways map to one form: Spanish `período` / `periodo`. Real accent
   errors (`esta` / `está`) still count.

Steps 2 (parentheses), 3 (times, space thousands, letters before numbers) and 8 were added after reading the
errors on Spanish shard 1, before any language was finished: each was a reference-vs-engine formatting mismatch
that charged every engine for words it got right (Ultra 4.5% -> 3.2%, Apple es-ES 5.9% -> 3.9% on that shard).
Each has a test in `tests/test_normalize_languages.py`.

Known residual mismatches, accepted and equal for every engine: German compounds written apart vs together
(`Bundes Regierung`), bare Roman numerals (`Luis XIV` read "catorce"), Spanish decimals said `punto` instead of
`coma`, German ordinals after a digit, times said another way (`6:30` read "seis y media"), unit abbreviations
(`h`, `km`) against spoken units, and a few typos in FLEURS's own transcripts (`carreras d Fórmula 1`). English's spelling-variant table has no counterpart here.

**WER**, alignment and pooling are #145's (`wer.py`): (S + D + I) / N, pooled over clips; only clips every engine
finished are compared.

**Confidence intervals.** 95% percentile bootstrap, 1,000 resamples, resampling **sentences**, not clips. FLEURS
has no speaker ids, and the up-to-three readings of one sentence share its words, so they are correlated the way one
speaker's segments are in EdAcc. The manifest's `group` field carries the sentence id, and the scorer resamples
`group` when present, `speaker` otherwise (so #145 is unchanged).

**Speed.** Real-time factor (processing / audio) and "x real time", model load excluded, as in #145. All engines run
at nice +15 next to other work, so speed is indicative.

## Recommendation rule

Per language, decided by the scorer (`recommend()`, tested), using Parakeet Ultra via FluidAudio (what the iPhone
would run) against Apple's best locale:

1. **Not ready** if the better of the two has WER above **15%** (the test plan's "good" line). FLEURS is read
   speech; conversation is several points worse (#145), so a language that misses 15% here would miss badly in use.
2. Otherwise **Parakeet** if Ultra matches or beats Apple: the low end of Ultra's 95% CI is at or below Apple's WER.
   ADR 0026 §3: "When a cross-platform engine matches or beats Apple's on the test, prefer it."
3. Otherwise **Apple**.

The report adds the Android line under each verdict: how the ONNX builds compare with Ultra on Core ML.

## #234: the other languages both engines caption

#234 runs the same test on **every other language Parakeet v3 covers that Apple's engine also captions**, so the app
can route each one to the engine that wins (ADR 0029). Parakeet v3 covers 25 European languages (E14); Apple's
`SpeechTranscriber` captions 10 languages (E27; `supportedLocales` on the M4, macOS 26.5: German, English, Spanish,
French, Italian, Japanese, Korean, Portuguese, Cantonese, Chinese). The overlap beyond #145 and #158 is **Italian and
Portuguese**. Parakeet's other 19 languages (Dutch, Polish, Swedish and so on) have no Apple engine to compare with and
aren't in Seal's caption language list, which comes from Apple's locales; adding them is a separate question.

| Language | FLEURS config | Clips | Distinct sentences | Audio | Apple locale(s) |
|---|---|---:|---:|---:|---|
| Italian | `it_it` | 865 | 346 | 3.52 h | it-IT, it-CH |
| Portuguese | `pt_br` (Brazilian) | see the report | | | pt-BR, pt-PT |

What changes from #158, and nothing else does (same dataset commit `70bb2e8`, scorer, bootstrap, rule):

- **Engines:** Apple with each of its locales for the language (best one compared, as with Spanish) and Parakeet Ultra
  through FluidAudio, the published `parakeet-ultra-coreml` build #158 used (the app ships its 6-bit encoder, which
  #150 measured at the same WER on EdAcc). The ONNX builds (Android path) are left out: the ticket asks which engine
  the app routes to, and they would double the run on a loaded Mac.
- **Normalizer:** Italian and Portuguese use #158's rules with their own words: comma `virgola` / `vírgula`, percent
  `per cento` / `por cento`, currencies (it `euro`, `dollari`, `sterline`; pt `euros`, `dólares`, `libras`), the
  `1º` / `2ª` ordinals as in Spanish (feminine for `ª`), hesitations (it `eh ehm mm mmm hmm`; pt `eh ehm hum hmm mm
  mmm ahn`) and, for Portuguese, Brazilian number words (`num2words` `pt_BR`: `dezesseis`), since FLEURS Portuguese is
  Brazilian. Italian elision (`l'uomo`) and Portuguese clitics (`disse-lhe`) split on both sides like French. Years
  are plain cardinals in both. Tests in `tests/test_normalize_languages.py`.
- **Errors read on Italian shard 1** before the rest ran: no formatting mismatch big enough to need a rule. The top
  pairs are real mistakes (Apple writes `è` for `e` 16 times), names (`Martelly`), unit abbreviations (`m`, `km`,
  `p.` against spoken words, the accepted residual above) and a few FLEURS transcripts that write `e` where `è` was
  said, which cost every engine equally.
- **Disk:** one language at a time on the M4 (about 5 to 9 GB free during the run): download, shard, delete the
  tarball, run, score, then delete that language's WAVs before the next. Manifests and result files stay.

Run: `LANG_LANGS=it LANG_SHERPA_MODELS=" " EVAL_WORK=<private work dir> scripts/engine-eval/m4-language-driver.sh`
(a private work dir with symlinks to `~/edacc-eval/models` and `venv`, so the status files of another run on the
same Mac aren't overwritten), then the same for `pt`.

## Complexity

- Shard maker: one pass over each `test.tar.gz` and `test.tsv`, O(clips); memory is one WAV at a time.
- Runs: O(clips x engines). Resume reads the shard's result file once, O(lines).
- Scorer: O(result lines + words^2 per clip) per language, rebuilt from all result files each run; seconds at this
  size. Bootstrap O(1,000 x sentences) per cell.
- Disk: about 1.5 GB of tarballs plus 1.5 GB of WAVs on the M4; models 3 GB (Ultra Core ML and the two ONNX builds),
  Apple's assets are system-managed.

## Running it

```bash
cd scripts/engine-eval && python3 -m pytest          # normalizer (per language), FLEURS shards, scoring, report
swift test --package-path Packages/EngineEval --filter EngineEvalKitTests
# M4 Mac mini: build the shards once, then every engine on every language (nohup, nice +15, Terminal window, resumable)
~/edacc-eval/venv/bin/python -m edacc_eval.cli fleurs-shards --corpus ~/fleurs-eval/corpus --out ~/fleurs-eval/shards
EVAL_DRIVER=m4-language-driver.sh scripts/engine-eval/m4-launch.sh 1 99 1
# Report
~/edacc-eval/venv/bin/python -m edacc_eval.cli report-languages --shards ~/fleurs-eval/shards \
  --results ~/fleurs-eval/results --out docs/perf/language-accuracy-comparison.md
```

## Not in this ticket

Languages beyond these three, conversational speech in these languages, live latency per language, the iPhone run,
and the 1.2 language picker. Non-European languages (Japanese, Korean, Mandarin, the Indian languages) aren't covered
by Parakeet at all; that is a separate test with other engines (`cross-platform-engines.md`).

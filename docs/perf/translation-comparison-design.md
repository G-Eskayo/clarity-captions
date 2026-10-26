# Translation comparison test: design (#159)

Design for #159 "[E] Translation comparison test: Apple vs ML Kit vs open models, before 1.3". Results and the
recommendation are in [`translation-comparison.md`](translation-comparison.md); the full generated tables are in
[`translation-comparison-results.md`](translation-comparison-results.md), which the scorer rebuilds from the result
files.
Policy behind the test: [[0026]] (Apple first, every feature gets a cross-platform comparison test). Landscape:
[`docs/research/cross-platform-engines.md`](../research/cross-platform-engines.md).

## Question

Which on-device engine should translate captions in 1.3? Measured per engine and per language pair as chrF (and
COMET), with 95% confidence intervals, plus time per caption line, model size per language, and how the language
model gets onto the device. English to Spanish first, then French and German.

## Patterns reused from #145

- **Result lines** are the #145 format (`edacc_eval.results`, Swift `EngineEvalKit.ResultLine`): one JSON line per
  (segment, engine, model, repeat), flushed before the next segment, resumable, first line wins on duplicates, corrupt
  lines skipped. For text, `clip_id` is the segment id, `accent` carries the test set name, `hypothesis` is the
  translation, `audio_seconds` is 0 and `processing_seconds` is the time to translate that one line.
- **Bootstrap** from `edacc_eval.wer`: 95% percentile bootstrap, 1,000 resamples, resampling *groups* (documents,
  not sentences, because sentences from one article are correlated), fixed seed.
- **Sizes** from `edacc_eval.sizes`: model folder bytes on disk and deflate-zipped bytes.
- **Report** shape from `edacc_eval.report`: a generated markdown file in `docs/perf/` and a JSON twin, rebuilt from
  every result file each time.
- **Opt-in Swift runner** in `Packages/EngineEval` (a tool package the app never references): a new
  `translation-eval` executable for Apple's framework, reusing `EngineEvalKit`'s result store.
- **No shards across machines.** #145 sharded 31 hours of audio across two Mac minis; this test is about 2,700 short
  text lines per language and runs on the M4 Mac mini in minutes, so it uses the result-file and resume pattern but
  not the shard queue.

## Licences and terms (checked first)

Read 2026-10-26; recorded in the evidence log (E18).

| Item | Licence / terms | Paid app OK? | Notes |
|---|---|---|---|
| Apple Translation framework | Apple SDK (Apple Developer Program License) | Yes | System framework; nothing to ship |
| Google ML Kit Translation | ML Kit Terms + Google APIs Terms; translation guidelines | Yes, with conditions | Must follow Cloud Translation attribution rules (Google branding in the UI); only on phones, tablets, laptops and desktops; no reverse engineering of the models; **the SDK sends usage and performance metrics to Google**, which the app must disclose |
| OPUS-MT `opus-mt-en-es`, `opus-mt-en-fr` | Apache 2.0 | Yes | Marian transformer-base, about 75M parameters |
| OPUS-MT `opus-mt-en-de`, `opus-mt-tc-big-en-es`, `opus-mt-tc-big-en-fr` | CC BY 4.0 | Yes | Attribution in the app's credits, like Parakeet |
| Firefox Translations (Bergamot) models | MPL 2.0 (repo archived Dec 2025, models now on Mozilla's storage) | Yes | Needs `bergamot-translator` (MPL 2.0); run only if a Mac build installs cleanly |
| CTranslate2 (runtime for OPUS-MT here) | MIT | Yes | |
| NLLB-200 | CC BY-NC 4.0 | **No** | Out, not tested |
| COMET `Unbabel/wmt22-comet-da` | Apache 2.0 | Yes (scoring only) | Reference-based; the reference-free CometKiwi models are non-commercial, so not used |
| FLORES-200 devtest | CC BY-SA 4.0 | Yes (test data) | Downloaded to `~/translation-eval/data`, never committed |
| WMT24++ (`google/wmt24pp`) | Apache 2.0 | Yes (test data) | Not committed |
| EdAcc transcripts | CC BY-SA (E9) | Yes (test data) | Text lines from the shard manifests only; no audio leaves the 2012 mini; not committed |

## Data

All test sets are built by `translation_eval.sets` into `~/translation-eval/sets/<pair>/<set>.jsonl`, one line per
segment: `id, set, group, source, reference`. Nothing from them is committed; only aggregate scores are published.

| Set | Source | Segments | References | Bootstrap group |
|---|---|---|---|---|
| `flores` | FLORES-200 devtest, `eng_Latn` to `spa_Latn` / `fra_Latn` / `deu_Latn` | 1,012 | human | article URL (metadata) |
| `flores-caption` | the same sentences, made caption-style (below) | 1,012 | same human | article URL |
| `speech` | WMT24++ "speech" domain: transcripts of YouTube videos, en to es_MX / fr_FR / de_DE | 111 | human, post-edited `target` | document |
| `speech-caption` | the same, caption-style | 111 | same | document |
| `edacc-lines` | EdAcc shard 1 transcripts as they would appear in a caption: spoken, short, unpunctuated | about 500 | **none** | speaker |

**Caption-style** turns written text into what a caption engine emits for the same words: lowercase, sentence
punctuation removed (`. , ; : ! ? " ( )` and dashes between words), apostrophes and hyphens inside words kept,
digits kept. The clean and caption-style versions share references, so the gap between them isolates how much each
engine loses when it gets caption text instead of written text.

**EdAcc lines** have no translation references, so they measure speed per caption line (real caption lengths and
vocabulary) and two failure checks that need no reference: output identical to the input (left untranslated) and
empty output. From each manifest reference: drop EdAcc tags (`<laugh>`, `<overlap>`, ...) and the filler words the
#145 normalizer drops (um, uh, er, mm, hmm ...), lowercase, keep lines of 2 to 40 words, de-duplicate.

**Caveats.** FLORES is Wikipedia-style written prose, not conversation. WMT24++ speech segments are paragraphs
(median about 68 words), longer than a caption line. FLORES Spanish is Latin American (`spa_Latn`), WMT24++ is
Mexican Spanish, Apple's and ML Kit's Spanish target is plain `es`; dialect choices cost every engine roughly
alike. Any engine may have seen FLORES or WMT data in training; we can't check that for Apple or Google.

## Engines

| Engine | Model | Where it runs here | Runtime |
|---|---|---|---|
| `apple` | Translation framework, system model | M4 Mac mini, macOS 26 | `TranslationSession(installedSource:target:)` in `engine-eval`'s new `translation-eval` command |
| `mlkit` | ML Kit on-device translation (`com.google.mlkit:translate` 17.0.3), Google Translate's offline models | **Android emulator** (Android 15, Google APIs, arm64-v8a) on the M4 | a tool-only Android app under `scripts/engine-eval/mlkit-android`, driven by `run.sh` over `adb` |
| `opus-mt` | `Helsinki-NLP/opus-mt-en-{es,fr,de}` | M4 CPU | CTranslate2, int8 weights, 4 threads, beam 4, sentence by sentence |
| `opus-mt-big` | `Helsinki-NLP/opus-mt-tc-big-en-{es,fr}` | M4 CPU | CTranslate2, int8 |
| `bergamot` | Firefox's en-es model | – | not run: no arm64 macOS build of the runtime (the `bergamot` wheel is x86_64 only) |

ML Kit has no macOS SDK. The iOS Simulator was tried first and doesn't work: ML Kit's iOS frameworks (MLKitTranslate
8.0.0, the newest, pulled in by GoogleMLKit 9.0.0) are fat binaries with an x86_64 Simulator slice and an arm64 device
slice but **no arm64 Simulator slice**, and the iOS 26.5 Simulator on Apple silicon refuses x86_64 apps ("needs to be
updated"). Re-tagging the device slice as a Simulator slice would mean modifying Google's binaries, which ML Kit's
terms rule out. So ML Kit runs in an **arm64 Android emulator** (hardware-virtualized on the M4, so near-native CPU
speed) with Google's official Android SDK, which uses the same offline models as iOS. The app is built debuggable only
so `adb shell run-as` can write the sets into its private folder; translation runs in ML Kit's native code. Emulator
timing is Mac CPU timing, not phone timing.

Apple's framework does not run in the iOS Simulator, and on macOS it only translates once the language is
installed, which takes a person: the system download sheet or **System Settings → General → Language & Region →
Translation Languages**. On 2026-10-26 the M4 had en→es, fr and de as *supported, not installed*, so #159 asks Gil
to install them; the Apple rows are added when he has.

**Sentence splitting for OPUS-MT.** Marian models translate a sentence at a time and silently drop sentences from
long multi-sentence input: on the WMT24++ speech passages (median 68 words) the first unsplit run left 13 (base) and
21 (tc-big) of 111 Spanish outputs under 70% of the reference length, against 0 for ML Kit, which splits internally.
An app integration would feed a sentence or a caption line at a time, so the OPUS runner splits at sentence ends
(`translation_eval.split`, tested) and rejoins. The caption-style copies have no punctuation to split on, so on the
long speech passages they also measure how each engine copes with an unpunctuated paragraph; in the app, lines would
be short.

## How the model reaches the device

Recorded per engine in the report, because Seal Speak shows no system pop-ups:

- **Apple:** the system owns the download. `prepareTranslation()` (or the first translation with a missing
  language) shows a system sheet asking the person to download; the app can't download silently, can't restyle the
  sheet, and can't delete a language. People can also add languages in Settings. Languages are shared with Apple's
  Translate app, so some people already have them.
- **ML Kit:** the app owns the download. `ModelManager.download(_:conditions:)` fetches a language from Google's
  servers with no system UI (Wi-Fi-only or cellular allowed, background allowed), and `deleteDownloadedModel` removes
  it. Seal draws its own progress and choice.
- **OPUS-MT / Bergamot:** the app owns everything: bundle the model or download it from our own host. No third-party
  server or SDK metrics. The cost is a runtime we would ship ourselves (CTranslate2, Marian or a Core ML conversion
  on iOS; Firefox already ships Bergamot on Android).

## Scoring

- **chrF** (sacrebleu `CHRF()`, defaults: character 6-grams, β = 2), corpus-level per (engine, set, pair). For the
  bootstrap, each segment's chrF sufficient statistics are summed over the resampled groups and the score recomputed,
  so every resample is a real corpus chrF, not a mean of sentence scores. O(B × groups × statistic length).
- **Paired difference**: for each pair of engines, the same 1,000 resamples give a 95% interval for the chrF
  difference; an interval that excludes 0 counts as a real difference.
- **COMET** (`Unbabel/wmt22-comet-da`, run locally on the M4) on the reference sets: system score is the mean
  segment score, bootstrap over the same groups.
- Only segments every engine finished are compared, as in #145.
- **Speed**: milliseconds per caption line on `edacc-lines`, batch size 1, one line at a time as live captions
  would arrive; median and p95 over 2 repeats, excluding model loading and the first 5 lines (warm-up). The repeat
  also gives a determinism check (share of lines with identical output). The quality runs overlap (emulator and
  CTranslate2 at once, and other work on the M4), so timing comes from a separate **isolated pass**: each engine
  alone on the caption lines, en-es (`--speed-results`).
- **Size per language**: the folder an engine needs for one language pair, on disk and zipped (`edacc_eval.sizes`).
  For ML Kit, `du` of the language folder it downloaded, measured in place on the emulator (the files aren't copied
  off; zipped size not measured); for Apple, the installed asset if it can be found on disk, otherwise unknown.

## Complexity

- Set builder: one pass over each source file, O(segments).
- Engines: O(segments × repeats) translations; resume reads the result file once.
- Scorer: chrF statistics O(characters) per segment, once; bootstrap O(B × groups) per cell and per engine pair;
  COMET O(segments) model calls, cached to a file per (engine, set, pair) so re-scoring doesn't re-run it.
- Disk: data about 30 MB; models: OPUS-MT about 80 MB per pair int8, tc-big about 240 MB, COMET about 2.3 GB, in
  `~/translation-eval`, never in the repo.

## Running it

```bash
cd scripts/engine-eval && python3 -m pytest     # existing #145 tests plus translation_eval tests
# Build sets, run the open models, score (~/translation-eval/venv has sacrebleu, ctranslate2, unbabel-comet)
python -m translation_eval.cli build-sets --data ~/translation-eval/data --out ~/translation-eval/sets --pair en-es
python -m translation_eval.cli ct2 --sets ~/translation-eval/sets/en-es --model ~/translation-eval/models/opus-mt-en-es-ct2 --hf-model ~/translation-eval/models/opus-mt-en-es-ct2 --results ~/translation-eval/results/en-es/opus-mt.jsonl
python -m translation_eval.cli report --sets ~/translation-eval/sets --results ~/translation-eval/results --speed-results ~/translation-eval/results-speed --sizes ~/translation-eval/sizes.json --meta translation_eval/report_meta.json --out ../../docs/perf/translation-comparison-results.md
# Apple (once the languages are installed)
swift run --package-path Packages/EngineEval translation-eval --sets ~/translation-eval/sets/en-es --target es --results ~/translation-eval/results/apple-en-es.jsonl
# ML Kit: JDK 21 + Android SDK (platform-tools, emulator, platforms;android-35, build-tools, cmdline-tools,
# system-images;android-35;google_apis;arm64-v8a), then
scripts/engine-eval/mlkit-android/run.sh en-es
# Open models for every pair, then COMET, then the report
scripts/engine-eval/translation-open-models.sh
python -m translation_eval.cli comet --sets ~/translation-eval/sets/en-es --results ~/translation-eval/results/en-es
```

## Not in this ticket

The iPhone speed, memory and battery check, and the 1.3 UI (where a translation line sits, the language picker, how
the download is shown). Non-English source languages (ML Kit pivots through English), and any decision about
Android itself (#43).

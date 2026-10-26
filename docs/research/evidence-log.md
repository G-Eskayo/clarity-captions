# Evidence log: the research behind Seal's decisions

One entry per source. Each says what we took from it, how strong it is, and which decision it drives, so the
portfolio page and the marketing site (#44) can show the reasoning, not just the result. **Add an entry whenever
research informs a decision**, and link the ADR, PR or ticket it drove.

Confidence: **Strong** (controlled study or official documentation), **Moderate** (guideline or several consistent
sources), **Weak** (single small study, secondary report or anecdote), **Ours** (our own measurement).

Public use: **Yes** (fine to cite on the portfolio or marketing pages as written), **Careful** (cite with its
caveat), **Internal** (process detail, not for marketing).

---

## E1. Dark vs. light mode for older readers
- **Source:** Piepenbrock, Mayr, Mund & Buchner (2013), *Ergonomics*: younger (18–33) vs. older (60–85) adults on
  visual acuity and proofreading in light vs. dark mode. Summary: [Nielsen Norman Group, Dark Mode vs. Light Mode](https://www.nngroup.com/articles/dark-mode/).
- **What we took:** dark text on a light background read better for both age groups, but the advantage was smaller
  for older adults. Dark mode caused no measurable extra eye fatigue. Participants had healthy eyes (no cataracts).
- **Confidence:** Strong for healthy eyes; the result doesn't extend to eye conditions.
- **Drives:** equal choice of 3 light and 3 dark themes rather than dark by default (v1 polish spec §4, #96).
- **Public use:** Careful ("light and dark both work; we offer both equally").

## E2. Brightness contrast matters more than color
- **Source:** Legge, Parish, Luebker & Wurm (1990), *Psychophysics of reading XI: comparing color contrast and
  luminance contrast*, JOSA A. [PDF](https://legge.dl8.umn.edu/sites/legge.psych.umn.edu/files/files/media/legge90_psychophysics_of_reading._xi._comparing_luminance_and_color_contrast.pdf)
- **What we took:** low-vision readers all read better with luminance (brightness) contrast than color contrast;
  text color itself mattered for only a minority (mostly advanced photoreceptor disorders).
- **Confidence:** Strong.
- **Drives:** every theme must reach AAA contrast (7:1), enforced by a test; theme design focuses on brightness
  contrast, not on "special" text colors (#96).
- **Public use:** Yes.

## E3. Yellow-on-black isn't proven easier, and pure-black glare
- **Source:** no controlled study found that isolates yellow-on-black for older adults (searched 2026-10-09).
  Secondary: [NIH/NLM, Making Your Web Site Senior Friendly](https://corpora.tika.apache.org/base/docs/govdocs1/562/562513.html)
  (light lettering on dark backgrounds is acceptable; avoid yellow next to blue and green for older eyes).
  Astigmatism and halation on bright-on-black text: anecdotal, not verified.
- **What we took:** no evidence justifies the harsh black-and-yellow "Bright" theme; dark themes should be calm
  (no pure black, no pure white, warm off-white text) while keeping AAA contrast.
- **Confidence:** Moderate (guideline) for the yellow/blue caution; Weak for the glare reasoning.
- **Drives:** "Bright" theme removed; relaxed dark themes (owner, 2026-10-09; #96).
- **Public use:** Careful.

## E4. What makes captions readable for older viewers
- **Source:** caption readability study for elderly TV viewers. [Sun Repository](https://reposit.sun.ac.jp/dspace/handle/10561/231)
- **What we took:** readability depends on caption size, font, spacing and the contrast between caption and
  background, the four things Seal lets people adjust.
- **Confidence:** Moderate.
- **Drives:** size, lettering and color settings (ADR 0013 simplicity; #34 text size; #96 settings).
- **Public use:** Yes.

## E5. Dyslexia fonts don't measurably improve reading
- **Source:** Wery & Diliberto (2017), *The effect of a specialized dyslexia font, OpenDyslexic, on reading rate and
  accuracy*, Annals of Dyslexia. [PMC full text](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5629233/) ·
  [Springer](https://link.springer.com/article/10.1007/s11881-016-0127-1). Counterpoint: a 3-student study reported
  gains ([OHU](https://acikerisim.ohu.edu.tr/items/4a62b3fd-db56-44ff-bddf-1349ab8e6458)); overview:
  [Edutopia](https://www.edutopia.org/article/do-dyslexia-fonts-actually-work/).
- **What we took:** in 12 students with dyslexia, OpenDyslexic gave no improvement in reading rate or accuracy over
  Arial or Times New Roman, and none preferred it. Some people still find it more comfortable.
- **Confidence:** Strong (for no measured benefit, in children); Weak (for the counterpoint).
- **Drives:** default lettering stays OpenDyslexic by the owner's choice (2026-10-09): he is dyslexic, it is an
  homage, and it is comforting to look at. Atkinson Hyperlegible (designed for low vision) and the system font are
  offered alongside it, plus Rounded, Serif and Typewriter (six choices). Marketing must never claim a font improves reading.
- **Public use:** Careful ("offered for comfort", never "improves reading").

## E6. What App Review rejects, and how to avoid it
- **Source:** [docs/app-review-risks.md](../app-review-risks.md) and [docs/app-store-compliance.md](../app-store-compliance.md):
  Apple's App Review Guidelines, App Store Connect help, developer forums and Reddit, each claim marked as Apple doc
  or forum report.
- **What we took:** device-support check, privacy manifest, iPad orientations, export compliance, the in-app
  privacy link, no health claims, and holding background audio out of v1.
- **Confidence:** Strong (Apple docs); Weak (forum anecdotes, marked as such).
- **Drives:** #79, #80, #82, #83, the listing in docs/app-store-listing.md.
- **Public use:** Internal (the "no data collected, fully on-device" outcome is Yes).

## E7. Building on existing on-device speech and speaker tools
- **Source:** [docs/research-existing-resources.md](../research-existing-resources.md): Apple SpeechAnalyzer reference
  code, FluidAudio (Apache-2.0), Sortformer (CC BY 4.0).
- **What we took:** transcription and speaker separation are solved problems on-device; reuse them, bundle the
  models, and never call the network at runtime.
- **Confidence:** Strong.
- **Drives:** ADR 0001, 0008, 0014.
- **Public use:** Yes (credit the open-source projects).

## E8. Why one voice sometimes gets split into two speakers
- **Source:** our own replay measurements, [docs/perf/speaker-label-stability.md](../perf/speaker-label-stability.md) (#91, PR #94).
- **What we took:** the speaker model itself reassigns one voice after pitch or pace changes; smoothing cut live
  relabels (e.g. 8.1 → 4.5 per minute) without slowing real turn-taking; a full fix needs a voice-recognition model.
- **Confidence:** Ours (synthetic voices; real-device check pending).
- **Drives:** SpeakerLabelSmoother (#94); open decision on adding a speaker-embedding model.
- **Public use:** Careful (good "how we measure" story; don't overstate accuracy).

## E9. EdAcc: accented conversations with checked transcripts
- **Source:** Sanabria, Bogoychev, Markl, Carmantini, Klejch & Bell (2023), *The Edinburgh International Accents of
  English Corpus: Towards the Democratization of English ASR*, ICASSP. [arXiv 2303.18110](https://arxiv.org/abs/2303.18110) ·
  [Edinburgh DataShare, doi:10.7488/ds/7914](https://doi.org/10.7488/ds/7914) (handle 10283/8983) ·
  Hugging Face mirror [`edinburghcstr/edacc`](https://huggingface.co/datasets/edinburghcstr/edacc) (test + validation,
  6.95 GB parquet, 19,137 segments, 32.7 h after segmentation, 32 accent groups, 122 speakers).
- **License:** CC BY-SA (the current DataShare record ships `CC_BY_SA_license_text.txt`; checked 2026-10-21). An earlier
  DataShare record was withdrawn over a license change, so this current record is the one we rely on. The Hugging Face
  card states no license of its own; we treat the mirror as carrying the DataShare license.
- **What we took:** two-person conversations, human transcripts and per-speaker accent and first-language labels: the
  closest public match to Seal's sit-down use. The paper reports every model degrading on accents (the best, Whisper
  large, averaged 19.7% WER versus 2.7% on clean US read speech), worst on Jamaican, Indonesian, Nigerian and Kenyan
  English.
- **Handling:** downloaded with the owner's approval (2026-10-21) to the 2012 Mac mini only; the audio never goes in the
  repo (ignore rules) or on any public page. Only aggregate scores are published.
- **Confidence:** Strong (peer-reviewed corpus).
- **Drives:** #145 engine accuracy test ([design](../perf/engine-accuracy-design.md), [results](../perf/engine-accuracy-comparison.md)).
- **Public use:** Careful (cite the corpus and aggregate WER; never quote or play its audio).

## E10. Speech engines compared in #145, and their licenses
- **Source:** model cards and repos, checked 2026-10-21:
  Apple SpeechAnalyzer / SpeechTranscriber (system framework, en-US asset via AssetInventory);
  [FluidAudio](https://github.com/FluidInference/FluidAudio) 0.17.5 (Apache-2.0) running
  [`FluidInference/parakeet-tdt-0.6b-v2-coreml`](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml) (CC BY 4.0,
  from [`nvidia/parakeet-tdt-0.6b-v2`](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)) and
  [`FluidInference/parakeet-ultra-coreml`](https://huggingface.co/FluidInference/parakeet-ultra-coreml) (CC BY 4.0, from
  [`moondream/parakeet-ultra`](https://huggingface.co/moondream/parakeet-ultra));
  [WhisperKit / argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (MIT) running
  `openai_whisper-large-v3-v20240930_turbo` from [`argmaxinc/whisperkit-coreml`](https://huggingface.co/argmaxinc/whisperkit-coreml)
  (MIT, from [`openai/whisper-large-v3-turbo`](https://huggingface.co/openai/whisper-large-v3-turbo));
  [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 1.13.8 (Apache-2.0) running
  `sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8` (CC BY 4.0, from NVIDIA's Parakeet TDT 0.6B v2).
- **What we took:** every candidate runs fully on device and has a license that allows use in a free app with
  attribution (CC BY 4.0 needs credit in the app's notices if shipped).
- **Confidence:** Strong (official model cards).
- **Drives:** #145; any engine switch would add its notice to `NOTICE.md` and the credits screen.
- **Public use:** Yes.

## E11. Engine accuracy test on all of EdAcc: which engine follows accents best
- **Source:** our own measurement, [docs/perf/engine-accuracy-comparison.md](../perf/engine-accuracy-comparison.md)
  (#145; all 32 shards: 17,528 EdAcc segments, 31.4 h, 122 speakers, 32 accent groups, one run per clip after a
  5-repeat shard 1; live-latency sample of 526 clips on the M4 Mac mini).
- **What we took:** Parakeet Ultra via FluidAudio had the lowest word error rate, **13.8% (95% CI 12.7–14.7%)**,
  against Apple SpeechAnalyzer's **17.2% (16.0–18.4%)**: about a fifth fewer errors. Parakeet v2 15.5%, sherpa-onnx
  (Parakeet v2 int8, the Android-capable runtime) 16.1%. Ultra was best on every one of the 32 shards (2.2 to 4.3
  points ahead of Apple) and on every accent group with three or more speakers. It also put correct words on screen
  sooner in the live sample (median 0.24 s after the word was said, against 0.67 s for Apple; p95 1.34 s against
  1.86 s). WhisperKit large-v3 turbo was dropped after shard 1 (23.5%, slowest, Apple-only). Apple, both Parakeet
  builds and sherpa-onnx gave identical text on all five repeats of shard 1.
- **Confidence:** Ours. Strong for the ranking on this corpus (32 of 32 shards agree); Mac, not iPhone, for latency
  and speed; segmented clips, not continuous conversation; single-speaker accent cells are wide.
- **Drives:** whether Seal switches its caption engine to Parakeet Ultra, pending an iPhone check (latency, battery,
  heat, memory, download size, CC BY 4.0 attribution).
- **Public use:** Careful ("on a public corpus of accented conversations, in our test, Parakeet made about a fifth
  fewer word errors than Apple's built-in engine").

## E12. How small can Parakeet Ultra get and still beat Apple?
- **Source:** our own measurement, [docs/perf/engine-accuracy-comparison.md](../perf/engine-accuracy-comparison.md)
  ("Size options"; #150 "[E] Switch captions to Parakeet Ultra: iPhone checks, then an ADR"). All 32 EdAcc shards
  (17,528 clips), same normalizer and speaker-bootstrap CIs; 526-clip live-latency sample; M4 Mac mini.
- **What we took:** the published Ultra encoder is already 8-bit (int8 linear per channel; folder 632 MB, 555 MB
  zipped; 13.8%). Re-compressing the fp16 encoder (coremltools 9.0b1, data-free k-means palettization, per grouped
  channel, group 16): **6-bit** keeps the same accuracy (13.8%, 12.8-14.8) at 498 MB / 485 MB zipped; **4-bit** costs
  one point (14.8%, 13.7-15.8) at 350 MB / 320 MB zipped and still clearly beats Apple SpeechAnalyzer (17.2%, 16.0-18.4).
  Latency barely moves (correct word median 0.24 s int8, 0.25 s 6-bit, 0.27 s 4-bit). FluidAudio's published small
  builds don't: Redux (2-bit re-training, 220 MB) 16.7%, v3 int4 22.7%.
- **Confidence:** Ours (one corpus; Mac, not iPhone; process memory excludes Neural Engine daemon memory).
- **Drives:** which Ultra build to bundle (#150); the iPhone check and the ADR.
- **Public use:** Careful.

## E13. Can the app load a compressed Parakeet build from its own bundle?
- **Source:** our own spike (#150), recorded in [docs/design/parakeet-engine-switch.md](../design/parakeet-engine-switch.md)
  "Feasibility spike": FluidAudio 0.17.5 source (`AsrModels.loadLocal`, `ASRConstants.maxModelSamples`) and a run of
  the `ultra-pal6` folder on a MacBook with `ModelHub.offlineMode` on. Licenses re-checked on Hugging Face 2026-10-22
  (`moondream/parakeet-ultra`, `nvidia/parakeet-tdt-0.6b-v3`, `FluidInference/parakeet-ultra-coreml`: all CC BY 4.0).
- **What we took:** the pinned FluidAudio loads a local compressed folder with no network; the first load compiles for
  the device (35 s on the Mac, 0.17 s after); every decode pads to a 15 s encoder pass, so the decode rate, not the
  window, sets Neural Engine load.
- **Confidence:** Ours (Mac only; iPhone numbers come from the #150 phone checks).
- **Drives:** ADR 0025, the committed tail-window decoder and adaptive hop, the first-run load step.
- **Public use:** Careful (Mac numbers; say so).

## E14. Parakeet Ultra covers 25 European languages, not just English
- **Source:** Parakeet Ultra model card (read from a mirror, [matenek/parakeet-ultra](https://huggingface.co/matenek/parakeet-ultra);
  the `moondream/parakeet-ultra` page didn't load on 2026-10-26) and [Spokenly on Parakeet v3](https://spokenly.app/blog/parakeet-models).
- **What we took:** Ultra is a post-training of Parakeet TDT 0.6B v3 (25 European languages, language detected
  automatically). Card figures: 25-language FLEURS WER 9.55% (v3 11.62%), English Open ASR 5.80% (v3 6.26%).
- **Confidence:** Moderate (card figures via a mirror; not our measurement yet).
- **Drives:** ADR 0026; the 1.2 languages plan may use Parakeet for European languages instead of Apple's engine,
  pending the FLEURS test. Challenges the "Ultra is English-tuned" risk row in the engine-switch design.
- **Public use:** Careful (cite as the model card's numbers, not ours).

## E15. Apple's Translation framework downloads languages through a system sheet
- **Source:** Apple, [`TranslationSession`](https://developer.apple.com/documentation/translation/translationsession)
  (`prepareTranslation()` "asks for permission to download translation languages"); [Kodeco, Translation API](https://www.kodeco.com/ios/paths/apple-ai-models/49307459-translation-framework/01-meet-the-translation-api/03).
- **What we took:** a missing language triggers a system download view the app can't restyle; a forum report says it
  sometimes doesn't appear on first use.
- **Confidence:** Strong for the sheet; Weak for the first-use bug.
- **Drives:** ADR 0026; the 1.3 translation design must handle or avoid the sheet (Seal shows no system pop-ups).
- **Public use:** Internal.

## E16. On-device translation that runs on iOS and Android, and what licences rule out
- **Source:** [ML Kit Translation](https://developers.google.com/ml-kit/language/translation) and its
  [iOS guide](https://developers.google.com/ml-kit/language/translation/ios); [NLLB-200 model card](https://huggingface.co/facebook/nllb-200-distilled-600M).
- **What we took:** ML Kit translates 50+ languages offline on both platforms, about 30 MB per language, downloads
  managed by the app, pivots through English, aimed at "casual and simple" text. NLLB-200 is CC BY-NC 4.0, so it is out
  for a paid app.
- **Confidence:** Strong (official docs). ML Kit's terms not yet read.
- **Drives:** ADR 0026; the 1.3 translation comparison test (Apple vs ML Kit vs OPUS-MT/Bergamot).
- **Public use:** Internal.

## E17. Speaker labels and sound labels outside Apple
- **Source:** community Sortformer ONNX exports ([soniqo](https://huggingface.co/soniqo/Sortformer-Diarization-4spk-ONNX),
  [TalkBar](https://huggingface.co/TalkBar/ultra-sortformer-8spk), [Recogment](https://huggingface.co/Recogment/sortformer-4spk-v2-onnx));
  [LiteRT audio classifier (YAMNet)](https://ai.google.dev/edge/lite/libraries/task_library/audio_classifier).
- **What we took:** Sortformer runs outside Core ML through ONNX, but the exports are unofficial and disagree on
  licence (CC BY 4.0 vs NVIDIA Open Model License; v1 offline is CC BY-NC). YAMNet classifies 521 AudioSet sounds on
  Android and iOS; licence believed Apache 2.0, unverified.
- **Confidence:** Weak (Sortformer licence), Moderate (YAMNet capability).
- **Drives:** ADR 0026; the speaker-label and sound-label comparison tests.
- **Public use:** Internal.

## E18. Language test data and models, and their licences (#158)
- **Source:** dataset and model cards, checked 2026-10-26: [FLEURS](https://huggingface.co/datasets/google/fleurs)
  (Conneau et al. 2022, [arXiv 2205.12446](https://arxiv.org/abs/2205.12446); test splits `es_419`, `fr_fr`,
  `de_de`, dataset commit `70bb2e8`); [`nvidia/parakeet-tdt-0.6b-v3`](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
  and its sherpa-onnx int8 export [`csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`](https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8);
  [`moondream/parakeet-ultra`](https://huggingface.co/moondream/parakeet-ultra) (the card now loads; it confirms E14),
  its Core ML build [`FluidInference/parakeet-ultra-coreml`](https://huggingface.co/FluidInference/parakeet-ultra-coreml)
  and a community sherpa-onnx export [`leogaudin/sherpa-onnx-nemo-parakeet-ultra-int8`](https://huggingface.co/leogaudin/sherpa-onnx-nemo-parakeet-ultra-int8);
  [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 1.13.8; [num2words](https://github.com/savoirfairelinux/num2words) 0.5.14.
- **License:** FLEURS CC BY 4.0; every Parakeet model and export CC BY 4.0 (the v3 export carries no file of its own
  and inherits NVIDIA's); sherpa-onnx and FluidAudio Apache-2.0; num2words LGPL-2.1, used only by the scorer on the
  Mac, never shipped. Nothing is non-commercial, so all of it passes ADR 0026 §4 for a paid app.
- **What we took:** FLEURS gives 908 Spanish (Latin American), 676 French and 862 German test clips (8.2 h, 330+
  distinct sentences each) of read Wikipedia sentences with human transcripts, enough per language that Common Voice
  wasn't needed. The Ultra card reports FLEURS WER of 2.72% Spanish, 4.32% French, 3.61% German (v3: 3.12, 4.81, 4.13),
  scored with the Open ASR Leaderboard's normalizer, not ours.
- **Handling:** the audio is on the M4 Mac mini only (`~/fleurs-eval`), never in the repo or on a public page; only
  aggregate scores are published.
- **Confidence:** Strong (official dataset and model cards).
- **Drives:** #158 ([design](../perf/language-accuracy-design.md)); an Ultra notice in the app would follow E10's rule.
- **Public use:** Yes (licences); Careful for the card's WER figures (theirs, not ours).

## E19. Language accuracy test: Parakeet Ultra beats Apple in Spanish, French and German
- **Source:** our own measurement, [docs/perf/language-accuracy-comparison.md](../perf/language-accuracy-comparison.md)
  (#158; [design](../perf/language-accuracy-design.md)). FLEURS test splits, every clip: Spanish 908 (3.1 h), French
  676 (2.0 h), German 862 (3.2 h); per-language normalizer that keeps accents; 95% CIs from a bootstrap over sentences;
  M4 Mac mini, macOS 26.5.1, one run per clip.
- **What we took:** Parakeet Ultra via FluidAudio (the 1.1 English engine, which detects the language itself) made
  the fewest word errors in all three languages: **Spanish 2.8% (2.4–3.3%) vs Apple 4.0% (3.4–4.5%); French 4.5%
  (3.9–5.1%) vs Apple 7.5% (6.7–8.3%); German 4.4% (3.8–5.0%) vs Apple 7.2% (6.5–7.9%)**: roughly 30 to 40% fewer
  errors, with intervals that don't overlap. Our figures sit close to the Ultra card's (2.72, 4.32, 3.61; E14,
  different normalizer). Apple's es-MX, es-US and es-ES gave identical text on all 908 clips, so its Spanish is one
  model. Apple's de-DE model put a stray "you" at the start of 76 of 862 German clips; without it Apple would be 6.8%,
  still well behind. On the Android path (sherpa-onnx, CPU), Parakeet v3 int8 scored 3.9% / 7.0% / 6.6% and a community
  Ultra int8 export 3.2% / 6.2% / 5.3%: the Ultra weights in ONNX beat Apple in every language, and in Spanish
  match Ultra on Core ML, but lose 1.0 to 1.7 points in French and German. Speed: Ultra on Core ML 98–114x real time,
  Apple 91–104x, sherpa-onnx 14–20x on CPU (the Mac was heavily loaded; indicative only).
- **Confidence:** Ours. Strong for the ranking (non-overlapping intervals in all three languages); read speech, not
  conversation, so real-use WER will be higher for every engine (#145); Mac, not iPhone; the Ultra ONNX result is
  one unofficial export.
- **Drives:** #158's recommendation, **Parakeet** for Spanish, French and German in 1.2; retires the "Ultra is
  English-tuned" risk row in the engine-switch design; under ADR 0026 the same weights are the Android candidate.
- **Public use:** Careful ("on a public set of read sentences, in our test, Parakeet made about a third fewer word
  errors than Apple's built-in engine in Spanish, French and German").

## E20. Translation engines for 1.3: licences, terms and how each gets its model onto the phone
- **Source:** [ML Kit Terms](https://developers.google.com/ml-kit/terms) (modified 2025-05-14) and the
  [ML Kit Translation guidelines](https://developers.google.com/ml-kit/language/translation/translation-terms);
  [ML Kit Translation overview](https://developers.google.com/ml-kit/language/translation); Hugging Face model cards
  for [`Helsinki-NLP/opus-mt-en-es`](https://huggingface.co/Helsinki-NLP/opus-mt-en-es) and its fr, de and tc-big
  siblings; [mozilla/firefox-translations-models](https://github.com/mozilla/firefox-translations-models) LICENSE;
  [`Unbabel/wmt22-comet-da`](https://huggingface.co/Unbabel/wmt22-comet-da); FLORES-200 (CC BY-SA 4.0) and
  [WMT24++](https://huggingface.co/datasets/google/wmt24pp) (Apache 2.0). All read 2026-10-26 for #159.
- **What we took:** every engine tested is usable in a paid app. **ML Kit** is free, but its translation guidelines
  require Google's Cloud Translation attribution and branding in the app, it may only ship on phones, tablets and
  computers, its models may not be reverse engineered, and **the SDK sends usage and performance metrics to Google**
  (our harness saw ML Kit keep a growing `datatransport` event database, 2.7 MB after one language), which the app
  must disclose. ML Kit downloads languages with the app's own code and no system UI. **OPUS-MT** models are Apache
  2.0 (en-es, en-fr) or CC BY 4.0 (en-de, tc-big), credited like Parakeet; the app owns download and storage.
  Firefox's Bergamot models are MPL 2.0. **Apple's** Translation framework downloads languages only through a
  system sheet or Settings (E15). NLLB-200 stays out (CC BY-NC). The reference-free CometKiwi metrics are
  non-commercial, so scoring uses the Apache 2.0 `wmt22-comet-da`.
- **Confidence:** Strong (official terms and model cards).
- **Drives:** the 1.3 engine choice (#159), the privacy label if ML Kit is used, the credits screen.
- **Public use:** Internal.

## E21. Translation comparison: open OPUS-MT models beat ML Kit in Spanish, French and German
- **Source:** our own measurement, [docs/perf/translation-comparison.md](../perf/translation-comparison.md)
  (#159 "[E] Translation comparison test: Apple vs ML Kit vs open models, before 1.3"). FLORES-200 devtest (1,012
  sentences) and WMT24++ speech transcripts (111 passages), each as written and in a caption-style copy (lowercase,
  unpunctuated); 760 EdAcc caption lines for speed. chrF and COMET (wmt22-comet-da), 95% bootstrap CIs over documents.
  OPUS-MT on the M4 Mac mini CPU (CTranslate2 int8, sentence by sentence); ML Kit 17.0.3 in an arm64 Android 15
  emulator on the same machine. Apple not yet run (languages not installed).
- **What we took:** the 82 MB OPUS-MT base model scored above ML Kit on written text in all three languages: chrF on
  FLORES **55.0 vs 53.2** (es), **69.8 vs 65.4** (fr), **63.6 vs 59.0** (de), and on speech transcripts **68.9 vs
  65.2**, **62.2 vs 59.5**, **61.3 vs 57.4**: paired differences of +1.8 to +4.6 chrF, every 95% CI above zero,
  and COMET gaps of 0.04 to 0.11. On caption-style input they were close: ML Kit ahead by 0.5 on Spanish FLORES (CI
  0.1–1.0), a tie in French (CIs include zero), OPUS-MT ahead on Spanish speech (+1.6) and in German (+1.5 FLORES,
  +10.2 speech). Every engine lost 1 to 15 chrF on caption-style input against the same words written with
  punctuation. Greedy decoding kept OPUS-MT's quality (FLORES 54.8, COMET 0.847)
  at **35 ms median, 107 ms p95 per caption line** on the M4 CPU; ML Kit took 23 ms median, 59 ms p95 in the emulator
  (measured under heavier machine load). The larger tc-big models (es, fr) added 0.9 to 2.6 chrF on written text at three
  times the size (about 215 MB zipped against 62–69 MB) and lost ground on long unpunctuated input. Marian models
  silently drop sentences from long multi-sentence input unless fed a sentence at a time.
- **Confidence:** Ours. Strong for the ranking on written text (all paired CIs exclude zero in all three languages);
  Moderate for caption-style input. Mac and emulator, not iPhone; Spanish references are Latin American; any engine may
  have seen FLORES or WMT data in training.
- **Drives:** the 1.3 translation engine (recommendation: OPUS-MT, pending an iPhone runtime spike), and the rule to
  translate Parakeet's punctuated text a sentence at a time.
- **Public use:** Careful ("in our test on public benchmarks, an open model we can ship ourselves translated more
  accurately than Google's on-device ML Kit in Spanish, French and German").

# Languages batch: the gap Apple leaves, and what Seal ships next to Hebrew (#236)

2026-10-30, unattended on the M4 Mac mini. Research only: nothing downloaded except Apple's own locale lists, read
from its APIs on this Mac. Every claim has a source: the four cited notes in [`languages-batch/`](languages-batch/)
carry each URL, its access date and a tier, and this page links the ones it leans on.

Tiers (the research skill's): **Established** (official source, or two or more independent ones agree),
**Contested** (sources disagree), **Speculative** (inference or a single weak source), **Unknown**. Every model
accuracy figure here is the model author's own unless it says **Ours**. Figures from different cards use different
normalisers, so compare them across rows only roughly.

## 1. The answer in brief

- **Apple's main engine (`SpeechTranscriber`) captions 10 languages on macOS 26.5.1, and probably 11 on 27.** Apple's
  older dictation engine (`DictationTranscriber`) adds 23 more, all of them in the gap list. Even on 27,
  `SpeechTranscriber` still has no Arabic, Hebrew, Russian, Turkish, Polish, Dutch, Vietnamese, Thai or Indonesian.
  Hindi is probably the one new language (§2). Bengali, Urdu, Persian, Swahili, Serbian and about 40 more big languages
  get nothing from Apple on either version.
- **19 gap languages are already in the Parakeet pack Seal ships**: 13 that Apple has only on dictation, and 6 it
  doesn't have at all. #234 doesn't cover them. It measures only Italian and Portuguese, the overlap with
  `SpeechTranscriber`. Those 19 cost no download, only the #158 measurement against Apple's dictation engine.
  **That's the cheapest win in this ticket** (§3).
- **For the rest, the field is better than it was for Hebrew.** There are open, commercially usable models of about
  Hebrew's size class (70–120M parameters) for Arabic (Standard), Persian, Russian, Ukrainian, Polish, Vietnamese,
  Bengali, Urdu and more. Most are NVIDIA NeMo FastConformers, the family Parakeet belongs to. Persian already has
  a streaming Core ML build (§4).
- **The weak spots:**
  - **Arabic dialects:** no small, clean model. Palestinian is about 30% WER even for a 1.5B model.
  - **African languages:** no small, good model for Swahili, Amharic, Hausa or Yoruba.
  - **Turkish:** the only small streaming model caps revenue.
  - **Conversational test sets:** almost every one is non-commercial, research-only or paid (§5).
- **Proposed first batch with Hebrew** (Decision `batch`):
  - **Own packs:** Arabic, Persian, Bengali, Urdu and Vietnamese.
  - **Parakeet** for the European languages where it beats Apple's dictation engine, Russian and Ukrainian first.
  - Together that's about **1.5 billion speakers** across the Middle East, South Asia, Southeast Asia and Eastern
    Europe. It also covers Israel's two largest languages after Hebrew: Arabic (about 2.1M first-language speakers)
    and Russian (1.2–1.5M).
  - Africa is the honest gap. It gets a measurement ticket, not a promise (§6).

## 2. What Apple's engines cover

### macOS 26.5.1, read on this Mac today

From [`apple-speech-locales-macos-26.5.1.json`](apple-speech-locales-macos-26.5.1.json), written by
[`scripts/speech-locales/probe.swift`](../../scripts/speech-locales/probe.swift).

| Engine | Locales | Languages |
|---|---|---|
| `SpeechTranscriber` (the engine Seal uses) | 30 | de, en, es, fr, it, ja, ko, pt, yue, zh (10) |
| `DictationTranscriber` (system dictation's models) | 54 | the 10 above **plus** ar (ar-SA only), ca, cs, da, el, fi, he, hi, hr, hu, id, ms, nb, nl, pl, ro, ru, sk, sv, th, tr, uk, vi (33) |
| `SFSpeechRecognizer` (old API) | 63 | the 33, plus wuu-CN and more English and Spanish regions |

**Established** (read from the APIs, matching E27 and the #200 design table).

### What 27 adds

Notes: [`languages-batch/apple-27.md`](languages-batch/apple-27.md).

- **Counts on macOS 27.0.1:** `SpeechTranscriber` has 45 locales and `DictationTranscriber` 54. Three independent
  developer measurements agree (examples:
  [skilli #80](https://github.com/nomdelasociete/skilli/pull/80),
  [EnviousWispr #4105](https://github.com/saurabhav88/EnviousWispr/issues/4105)), and the owner's laptop matches.
  **Established.**
- **Still dictation-only on 27:** the same two sources list 23 locales whose language `SpeechTranscriber` has in no
  variant. They are exactly the 23 above, Hebrew and Arabic included. **Established**, though from developers, not
  Apple.
- **So the one new language is very likely Hindi.** 54 minus those 23 leaves our 30 plus hi-IN. The other new
  locales are regional variants of languages it already had. **Speculative**: no source prints the 45.
- **No new features for captions.** Apple's June 2026 Speech updates are audio-input helpers only: no language
  detection, no multilingual mode and no vocabulary API
  ([Speech updates](https://developer.apple.com/documentation/updates/speech)). **Established.**
- **Apple publishes no accuracy figures by language.** **Established**: none in the docs, sessions or release notes.
- **iPhone and iPad:** Apple publishes no device list
  ([DTS](https://developer.apple.com/forums/thread/802863)). Developers report an empty list on A13 iPhones
  (iPhone 11 and SE 2) ([forum](https://developer.apple.com/forums/thread/806765)). **Contested.** Whether a
  supported iPhone lists the same locales as the Mac is **Unknown**, which is why the app reads the list on the
  device (E27).

**To close this:** run the probe on the macOS 27 laptop to commit the real 45-locale list
(`swift scripts/speech-locales/probe.swift > docs/research/apple-speech-locales-macos-27.0.1.json`). An iPhone on 27
needs a debug-build log of the same two lists. Neither needs a microphone.

## 3. The gap table

**Apple** shows the best Apple engine on macOS 26.5.1. It's the same on 27 except Hindi (§2).

- **Dict.** means `DictationTranscriber` only. Its Hebrew was 10.4% CER on conversation against 2.4–2.5% for open
  models: four times worse (evidence `2026-10-29-hebrew-engines-on-conversation`). No other language has been
  measured.
- **Parakeet** means the language is in the shared Parakeet v3/Ultra pack Seal already ships.
- **Speakers** are total and first-language, in millions: Ethnologue 2026 as quoted by Wikipedia, else the language's
  Wikipedia infobox. Sources are in [`testsets-speakers.md`](languages-batch/testsets-speakers.md) §4. **n/r** means
  not researched.

### 3a. Languages the shipped Parakeet pack already covers (no new download)

| Language | Speakers (total / L1) | Apple | Parakeet v3 FLEURS WER (card) | Small specialist, if better | Clean held-out test |
|---|---|---|---|---|---|
| Russian | 210 / 133 | Dict. | in E14's 25 | T-one 72M, Apache-2.0, **streaming**; GigaAM-v3 240M, MIT | **CV Spontaneous ru** (2.2 h, 12 speakers, CC0 + Mozilla terms); FLEURS |
| Ukrainian | 39 / 32 | Dict. | in E14's 25 | NVIDIA `stt_ua` FastConformer 115M, CC BY 4.0 (MCV12 5.7) | FLEURS; CV |
| Polish | 43 / 40 | Dict. | in E14's 25 | NVIDIA `stt_pl` 115M, CC BY 4.0 (MLS 5.8) | ParlaSpeech-PL (CC BY-SA, no test split); VoxPopuli (CC0); FLEURS |
| Dutch | 30 / 25 | Dict. | in E14's 25 | NVIDIA `stt_nl` 115M, CC BY 4.0 | VoxPopuli (CC0); MLS; FLEURS |
| Romanian | 22+ / 22 | Dict. | in E14's 25 | none small | VoxPopuli (CC0); FLEURS |
| Greek | — / 13.5 | Dict. | in E14's 25 | none small | FLEURS only |
| Czech | 12 / 9.8 | Dict. | in E14's 25 | — | ParlaSpeech-CZ (CC BY-SA); VoxPopuli; FLEURS |
| Hungarian | — / 12.1 | Dict. | in E14's 25 | — | VoxPopuli; FLEURS |
| Swedish | 13.1 / 9.9 | Dict. | in E14's 25 | — | VoxPopuli; FLEURS |
| Slovak | 7.4 / 5.4 | Dict. | in E14's 25 | — | VoxPopuli; FLEURS |
| Danish | — / 5.5 | Dict. | in E14's 25 | — | FLEURS |
| Croatian | 6.5 / 5.1 | Dict. | in E14's 25 | NVIDIA `stt_hr` 115M, CC BY 4.0 (ParlaSpeech-HR 4.2) | VoxPopuli; FLEURS |
| Finnish | — / 5.0 | Dict. | in E14's 25 | — | VoxPopuli; FLEURS |
| Bulgarian | 7.9 / 6.8 | **none** | 12.6 | Canary-1b-v2 9.3 (978M, too big) | FLEURS only |
| Lithuanian | — / 4.0 | **none** | 20.4 | Canary 12.4 | VoxPopuli; FLEURS |
| Slovenian | — / 2.5 | **none** | 24.0 | Canary 13.3 | VoxPopuli; FLEURS |
| Latvian | — / 1.5 | **none** | 22.8 | Canary 9.7 | FLEURS |
| Estonian | — / 1.2 | **none** | 17.7 | Canary 12.6 | VoxPopuli; FLEURS |
| Maltese | n/r | **none** | in E14's 25 | — | FLEURS |

Notes:

- Parakeet v3 WERs for the five Apple-less languages come from the Canary paper's Table 11
  ([arXiv 2509.14128](https://arxiv.org/html/2509.14128)), the same table as Canary's. Seal ships Ultra, which beat v3
  on the 25-language FLEURS average (9.55% vs 11.62%, E14). **Established** (self-reported).
- Lithuanian, Slovenian and Latvian sit above ADR 0029's 15% bar on v3. Whether Ultra clears it is **Unknown** until
  measured.
- Speaker figures for the smaller languages come from each Wikipedia infobox, read 2026-10-30:
  [hu](https://en.wikipedia.org/wiki/Hungarian_language), [sv](https://en.wikipedia.org/wiki/Swedish_language),
  [hr](https://en.wikipedia.org/wiki/Croatian_language), [sk](https://en.wikipedia.org/wiki/Slovak_language),
  [da](https://en.wikipedia.org/wiki/Danish_language), [fi](https://en.wikipedia.org/wiki/Finnish_language),
  [et](https://en.wikipedia.org/wiki/Estonian_language), [lv](https://en.wikipedia.org/wiki/Latvian_language),
  [lt](https://en.wikipedia.org/wiki/Lithuanian_language), [sl](https://en.wikipedia.org/wiki/Slovene_language).
- **#234 covers none of these rows.** Its design says Parakeet's other 19 languages "have no Apple engine to compare
  with". That is true of `SpeechTranscriber` but not of `DictationTranscriber`, which has 13 of them
  (`docs/perf/language-accuracy-design.md` on the #234 branch). **Established.**

### 3b. Languages that need a model of their own

| Language | Speakers (total / L1) | Apple | Best open candidate: licence, size, streaming, published accuracy | Clean held-out test (conversational, else read) | Tier |
|---|---|---|---|---|---|
| **Arabic** (Standard) | ≈481 / 411 (all varieties) | Dict. (ar-SA only) | NVIDIA `stt_ar_fastconformer_hybrid_large_pc_v1.0`, CC BY 4.0, 115M, offline; FLEURS 8.2, MCV 10.2, MASC 11.5 WER | No clean conversational set: MASC licence disputed, MGB-2 research-only, SADA and CASABLANCA NC. Read: FLEURS, CV ar | Established (model); dialects below |
| Arabic dialects (Levantine/Palestinian, Egyptian, …) | Levantine 58 / 55, Egyptian 118 / 83 | none per dialect | Nothing small and clean. Best numbers: a 1.5B Whisper fine-tune, Palestinian 30.1% WER, training data unlicensed. Omnilingual (Apache-2.0) lists apc and arz, unmeasured at phone size | CASABLANCA Palestine, Jordan and Egypt: CC BY-NC-ND | Established (absence) |
| **Persian** | 127 / 91 (Iran: 82 / 65) | **none** | **Shenava Koochik 114M / Rizeh 32M**, Apache-2.0, **streaming, Core ML builds already published**; FLEURS 10.6 / 14.5 WER. NVIDIA `stt_fa` 115M CC BY as a second | PSRB is research-only; read: CV fa 11.7 h, FLEURS | Established. Training-data provenance Contested (a 512 GB scrape) |
| **Bengali** | 274 / 234 | **none** | AI4Bharat IndicConformer-bn 120M, MIT (gated), offline, no WER published; Vosk streaming zipformer, Apache-2.0, FLEURS 20.6 | **IndicVoices bn**: CC BY 4.0, gated click-through, 5 h, 125 speakers, mostly unscripted | Established; accuracy Unknown |
| **Urdu** | 246 / 78 | **none** | IndicConformer-ur 120M, MIT (gated), no WER published | **IndicVoices ur** (5 h, 99 speakers, Indian Urdu); FLEURS ur_pk | Established; accuracy Unknown |
| **Vietnamese** | 97 / 86 | Dict. | **gipformer1.5 68M**, MIT, zipformer (the Hebrew model's family); FLEURS 12.7, call-centre 15.4 WER | Clean conversational: none (GigaSpeech 2 is NC). Read: FLEURS, CV | Established |
| Hindi | 611 / 347 | Dict.; probably `SpeechTranscriber` on 27 | IndicConformer-hi 120M MIT | IndicVoices hi (5 h, 63 speakers) | Apple 27 Speculative |
| Indonesian | 255 / 78 | Dict. | PixelML `sea-asr-id`, Apache-2.0, streaming 0.48 s; FLEURS 9.0 WER; size Contested (112M vs 364M) | Read: FLEURS, CV (GigaSpeech 2 NC) | Contested (size) |
| Turkish | 94 / 86 | Dict. | `mihuai/turkish-stt-66m-v2`: streaming, FLEURS 10.1, but a **custom licence** (under $500k revenue, "Powered by mihu"). Nemotron 3.5 streaming 0.6B (OpenMDW-1.1) lists Turkish as ready | Read: CV tr 12.7 h, FLEURS | Established |
| Thai | 71 / 27 | Dict. | Typhoon streaming 115M, CC BY 4.0, CER 19.4 (offline sibling 9.8) | **LOTUSDIS**: CC BY-SA 4.0, ungated meeting dialogue, 13.3 h test | Established |
| Tamil, Telugu, Marathi, Punjabi | 86, 96, 99 total | **none** | IndicConformer per language, MIT, no WER published | IndicVoices (5 h each) | Established; accuracy Unknown |
| Swahili | ~95 (Contested) / 4–5 | **none** | Nemotron fine-tune 600M, OpenMDW-1.1, streaming, ~30 WER; nothing small | Babel (paid); read: CV sw 17.9 h, FLEURS | Established (absence) |
| Amharic | 78 / 39 | **none** | `hohe-asr-amharic` 606M, CC BY 4.0, FLEURS 17.9 | FLEURS only | Established |
| Hausa, Yoruba | 94 / 58, 53 / 48 | **none** | Hausa: Nemotron fine-tune 600M (33.5 WER). Yoruba: nothing commercially clear | NaijaVoices is NC; read: FLEURS | Established (absence) |
| Filipino/Tagalog | 87 / 33 | **none** | `sea-asr-ph`, Apache-2.0, streaming, FLEURS 17.2 | FLEURS only (no Common Voice) | Established |
| Serbian (#204) | — / 8.2 | **none** | NVIDIA `stt_hr` (Croatian) 115M, CC BY; untested on Serbian. Parakeet has hr | **JuzneVesti-SR**: CC BY-SA 4.0, interview show, about 5 h test | Speculative (hr → sr) |
| Georgian, Armenian, Kazakh, Uzbek | small | **none** | NVIDIA `stt_ka` **streaming 80 ms**, `stt_hy`, CC BY 115M; GigaAM-Multilingual 220M MIT (kk 5.2, uz 10.0) | FLEURS | Established |
| Yiddish | n/r | **none** | ivrit.ai `yi-whisper-large-v3-turbo`, Apache-2.0, 809M, offline | — | Established |

Not offered at all, from Apple or here: Burmese, Khmer, Pashto, Kurdish (Sorani), Somali and Albanian have no small
clean model. Only Omnilingual covers them (Apache-2.0, a 300M CTC model at about 292 MB int8, offline, accuracy
unmeasured at that size) ([`models-multilingual.md`](languages-batch/models-multilingual.md) §3).

**Do not ship** (licence): MMS-1b-all, SeamlessM4T v2, ArTST, anything trained on SADA, hynt's 30M Vietnamese
zipformer and the sherpa-onnx `vi-30M` release that appears to be it (CC BY-NC-ND), the Vosk Tagalog model,
PengChengStarling (no licence), EchoesML Georgian, and Moonshine's non-English models (community licence).
[`models-per-language.md`](languages-batch/models-per-language.md) has the reasons.

## 4. What makes a language cheap or dear

The Hebrew recipe has four steps: measure, convert, compress to 4-bit, pack. Its cost depends on three things.

1. **The model's family.** We have two converters.
   - **Zipformer:** our own ONNX-to-Core ML translator from #225.
   - **NeMo FastConformer:** the möbius path FluidAudio uses for Parakeet.

   The NVIDIA per-language models (Arabic, Persian, Ukrainian, Polish, Dutch, Croatian, Georgian, Armenian),
   IndicConformer (Bengali, Urdu and the other Indic languages) and Shenava (Persian) are all NeMo conformers.
   gipformer (Vietnamese) is a zipformer.

   **One FastConformer converter would serve most of the batch.** That's **Speculative** until one converts. The
   möbius route was refused unattended on the Mini once, and #225 worked around it by treating ONNX as data.
2. **Streaming.** Hebrew's zipformer streams natively. Most of the 115M NeMo models are offline, so they would run
   like Parakeet does today, re-encoding a window. The exceptions are Shenava, T-one, Georgian and Typhoon. That
   costs latency and heat on the phone, not accuracy.
3. **Size.** Hebrew: 66M parameters, 38.6 MB at 4-bit. **By the same ratio a 115–120M model is about 65–70 MB at
   4-bit** (**Speculative**: scaled, not built). Five such packs come to about 330 MB, which is why §7 asks how they
   ship.

## 5. Test data: the constraint nobody can buy around cheaply

Notes: [`testsets-speakers.md`](languages-batch/testsets-speakers.md).

- **Commercially clean and conversational:** only a handful.
  - **IndicVoices:** CC BY 4.0, gated. Hindi, Urdu, Bengali, Tamil, Telugu and Marathi, 5 h each, mostly
    unscripted.
  - **LOTUSDIS:** Thai meetings, CC BY-SA 4.0.
  - **JuzneVesti-SR:** Serbian interviews, CC BY-SA 4.0.
  - **Common Voice Spontaneous:** CC0, monologue. Only Russian has a usable test split: 2.2 h from 12 speakers.
  - **VoxPopuli:** CC0, parliament speech, 16 European languages.

  **Established.**
- **Everything else conversational is non-commercial, research-only or paid:** CASABLANCA, SADA, MGB-2, GigaSpeech 2,
  NaijaVoices, PELCRA, CGN and the LDC Babel packs. GigaSpeech 2's terms bind a for-profit employer explicitly.
  **Established.**
- **The read-speech fallback is always there:** FLEURS (CC BY 4.0, all 102 languages) and Common Voice (CC0, now only
  through Mozilla Data Collective with a login, no re-hosting). Read speech flatters every engine. Hebrew's gap
  widened from about 40% on read speech to about 75% on conversation. **Established** (ours, one language).
- **Precedent:** Hebrew's conversation sets were gated "AI training or academic research", and the owner accepted
  them for internal scoring. Whether that carries to NC sets is Decision `test-data`.

## 6. The proposed first batch

Scored on three things: reach (speakers), how much better than Apple Seal can be (nothing → dictation-only →
`SpeechTranscriber`), and cost (§4: a ready, clean, small model and a clean test set). Balanced by region and
community, with Hebrew.

| | Language | Why | Engine route | Main risk |
|---|---|---|---|---|
| **Pack** | **Arabic** (Standard) | 411M L1; Israel's second language (about 2.1M L1, 21% of citizens); Apple has only Saudi dictation | NVIDIA FastConformer 115M, CC BY | Dialect speech (Palestinian, Egyptian) will be weaker: measure on dialect and say so in the app. No clean conversational test |
| **Pack** | **Persian** | 127M; Apple has nothing | Shenava, Apache-2.0, streaming, Core ML exists | Training-data provenance check before shipping |
| **Pack** | **Bengali** | 274M; Apple has nothing | IndicConformer-bn, MIT | No published WER: the measurement decides |
| **Pack** | **Urdu** | 246M; Apple has nothing; same model family and test set as Bengali | IndicConformer-ur, MIT | As Bengali; Pakistani speech is not in the test set |
| **Pack** | **Vietnamese** | 97M; Apple has dictation only | gipformer 68M, MIT, zipformer like Hebrew | No clean conversational test |
| **Parakeet** | **Russian, Ukrainian** and the other 11 dictation-only European languages, plus the 6 Apple-less ones | 210M + 39M + about 190M more; Israel's third language (Russian, 1.2–1.5M); no download | Shared Parakeet pack, measured against `DictationTranscriber` (#158 rule) | Lithuanian, Slovenian and Latvian may miss the 15% bar |

That comes to about 1.5 billion people. Arabic, Bengali, Urdu, Persian and Vietnamese sum to about 1.2 billion total
speakers using the Arabic macrolanguage figure (481 + 274 + 246 + 127 + 97); Russian and Ukrainian add about 250M.
These are total speakers (first and second language) and overlap between languages, so read them as reach, not
headcount.

**Left for a second batch:**

- **Hindi:** Apple is probably adding it on 27.
- **Indonesian:** the model's size is disputed and its architecture is new to us.
- **Turkish:** licence (Decision `openmdw`).
- **Thai:** it has a clean conversation set, so it's a good next candidate.
- **The other Indic languages:** they follow Bengali and Urdu for little extra work.
- **Africa:** Swahili, Amharic, Hausa and Yoruba have no small, good, clean model. **Proposed: one screening ticket**
  scores Omnilingual 300M and Dolphin on FLEURS for these languages before anything is promised. Amharic also
  matters in Israel, through its Ethiopian community.

## 7. Release plan

- **1.1.1, the easy route:**
  - **Hebrew**, bundled, is already built (#222, PR #227).
  - **The Parakeet languages.** Their engine is already in the app, so each language that wins its #234-style
    measurement is a line in the engine table plus an entry in the caption-language list. The list can already
    hold languages Apple's `SpeechTranscriber` lacks (`CaptionLanguage.adding`, PR #227).
  - The six Apple-less ones have no Apple fallback. That's Decision `parakeet-unmeasured`, already open on PR #205.
- **1.2: the five own-model packs**, as packs from #221 (ADR 0029: the base install stays the app). Bundling them
  like Hebrew would add about 330 MB for everyone (§4) and undo #200's goal. Decision `release`.
- **Per language, before it ships:**
  1. Measure against Apple (#217 harness, CER and WER, 95% intervals, conversation where a clean set exists).
  2. Convert and 4-bit compress (#225), then rescore.
  3. Pack and credit it (CC BY and MIT need attribution, as Hebrew's does).
  4. The iPhone checks from #225 (P1–P4), which need a real microphone: the owner's devices, not the Mini.

## 8. Measurement tickets, drafted (filed once the owner picks the batch)

Each follows #217 / #225: one command, the result table in `docs/perf/`, an evidence entry, and no audio committed.

1. **Parakeet vs Apple's dictation engine, 19 European languages** (an extension of #234). FLEURS plus VoxPopuli
   where it exists; CV Spontaneous for Russian. Routing tests first.
2. **Arabic:** NVIDIA FastConformer vs `DictationTranscriber` ar-SA on FLEURS and CV, plus a dialect slice if
   `test-data` allows CASABLANCA.
3. **Persian:** Shenava Koochik and Rizeh, NVIDIA `stt_fa`. Apple has nothing, so the 15% bar alone applies. The
   provenance check comes first.
4. **Bengali and Urdu:** IndicConformer and the Vosk streaming bn model, on IndicVoices and FLEURS.
5. **Vietnamese:** gipformer vs `DictationTranscriber` vi-VN on FLEURS and CV.
6. **FastConformer to Core ML:** one converter for the NeMo per-language models, tried on Arabic first.
7. **Africa screen:** Omnilingual 300M and Dolphin on FLEURS for sw, am, ha and yo.

## 9. What would change this, and what we don't know

- **The 45-locale list.** If it holds a gap language other than Hindi, that row moves. The probe on the 27 laptop
  settles it.
- **Apple's dictation engine is measured only for Hebrew.** If it does far better in, say, Vietnamese, the case for a
  Vietnamese pack shrinks. Every own-pack ticket measures it first.
- **IndicConformer has no published accuracy.** Bengali and Urdu could disappoint. Their tickets decide.
- **Unknown** licences: VietSuperSpeech, VietMed, RO-N3WS, the VOA Ukrainian set, Russian Open STT, MGB-3 and the
  MediaSpeech original.
- **Speaker figures** for Arabic, Persian, Hindi, Thai and Swahili depend on how the language is defined. The
  figure used is named in the notes.
- **Converting a 115M FastConformer to Core ML is unproven** on the Mini (§4).

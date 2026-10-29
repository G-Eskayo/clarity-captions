# Hebrew accuracy test: design (#201, #202)

Design for #201 "[E] Hebrew: measure Apple's dictation engine against the open Hebrew models" and its scorer, #202
"[E] Hebrew text normaliser for fair scoring". Method and harness come from the #158 language test
([`language-accuracy-design.md`](language-accuracy-design.md)); this page records what changes for Hebrew.

## Question

Before any Hebrew engine work (a fine-tune, a language pack, an iPhone spike): how well does Apple's own Hebrew
engine caption, and how far ahead are the open Hebrew models? Apple's Hebrew accuracy had never been measured (the
2026-10-29 Hebrew research, ticket T1 there). Measured as WER and CER per engine per test set, with 95% confidence
intervals, plus speed. There is no verdict rule: this is a baseline for the decisions after it (which base model to
fine-tune, whether a pack beats Apple), not a ship decision.

## What we found (2026-10-29)

Full table: [`hebrew-accuracy-comparison.md`](hebrew-accuracy-comparison.md). FLEURS he, 792 clips, all five engines
on every clip. CER (strict) with 95% CI, then WER:

| Engine | CER | WER |
|---|---|---|
| ivrit.ai Whisper turbo (reference only) | 8.3% (6.7–10.0) | 17.4% (15.3–19.5) |
| Parakeet-He | 9.7% (8.1–11.4) | 22.3% (20.2–24.5) |
| ivrit.ai zipformer2 66M, int8, streaming | 10.0% (8.4–11.7) | 22.2% (20.1–24.3) |
| **Apple DictationTranscriber he-IL** | **16.5% (14.8–18.4)** | **35.0% (32.8–37.2)** |
| Nemotron 3.5 streaming, zero-shot | 32.4% (29.7–35.0) | 50.8% (47.8–53.5) |

- **Every open Hebrew model beats Apple, and the intervals don't overlap.** Parakeet-He and the zipformer make about
  40% fewer character errors than Apple's DictationTranscriber (9.7–10.0% vs 16.5% CER). The research guessed this
  ("open models very likely beat it, Speculative until measured"); it is now measured on read speech.
- **The 66M zipformer, streaming at int8, ties the 600M Parakeet-He** (10.0% vs 9.7% CER, intervals overlapping) at
  about a tenth of the size. This supports the research's reframe: a small native streaming model may be the better
  phone candidate.
- **Nemotron 3.5 zero-shot is not usable for Hebrew** (32% CER, mostly deletions: 2,669 of its 6,982 word errors),
  even when told the language. That matches NVIDIA's "adaptation-ready" label: it needs a fine-tune first.
- Whisper turbo leads, as expected of the model that labelled the others' training data. It is the accuracy ceiling,
  not a phone candidate.
- **Apple's engine is also the least complete:** 1,024 deleted words, twice the open models', and one clip failed
  outright on the first try (`RecogFailed`; it passed on a retry).
- **Cross-check with the published number:** Parakeet-He's card puts it at "FLEURS: 76.8 vs ~82 for the best models",
  apparently 100 − WER. Here it scores 22.3% WER (77.7) and Whisper 17.4% (82.6), so this harness agrees with the
  card within a point.
- **Speed** (indicative, different hardware per engine): Parakeet-He 50x real time on the GPU, Apple 41x, the zipformer
  31x on the CPU, Whisper and Nemotron about 9x.
- **Read speech.** FLEURS is the set the published models are weakest on (rare names, Latin terms). The
  conversation sets below are the ones that decide anything about live captions.

## Conversation sets: eval-d1 and eval-whatsapp

Follow-up run, 2026-10-29, same harness, normaliser and engine versions, once the Mini was signed in to Hugging Face.
ivrit.ai [`eval-d1`](https://huggingface.co/datasets/ivrit-ai/eval-d1) @ `7899b04` (conversation: 17 recordings,
1.43 h) and [`eval-whatsapp`](https://huggingface.co/datasets/ivrit-ai/eval-whatsapp) @ `1267f61` (voice notes: 54
recordings, 1.18 h, 1 s to 4.6 min). Every engine finished every recording, 0 errors. Each recording is whole (up to
about 5 minutes), so the bootstrap resamples recordings. CER (strict) with 95% CI, then WER:

| Engine | eval-d1 CER | eval-d1 WER | eval-whatsapp CER | eval-whatsapp WER |
|---|---|---|---|---|
| Parakeet-He | 2.4% (2.0–2.9) | 5.2% (4.5–5.9) | 3.8% (3.4–4.4) | 8.2% (7.3–9.2) |
| ivrit.ai zipformer2 66M, int8, streaming | 2.5% (2.1–2.8) | 5.0% (4.2–5.6) | 4.2% (3.6–4.8) | 8.6% (7.6–9.6) |
| ivrit.ai Whisper turbo (reference only) | 2.4% (2.0–2.8) | 4.8% (4.0–5.4) | 3.2% (2.8–3.9) | 7.0% (6.1–8.0) |
| **Apple DictationTranscriber he-IL** | **10.4% (7.8–13.3)** | **17.8% (15.3–20.6)** | **11.6% (10.2–13.1)** | **22.3% (20.5–24.2)** |
| Nemotron 3.5 streaming, zero-shot | 8.2% (7.3–9.1) | 18.7% (17.2–20.1) | 20.3% (17.1–24.1) | 37.9% (33.4–42.8) |

- **Conversation (eval-d1): Parakeet-He and the 66M zipformer win, and they are tied.** 2.4% vs 2.5% CER, 5.2% vs
  5.0% WER, intervals almost identical; Whisper turbo, the reference, is no better (2.4%). Nothing here separates
  the two candidates on accuracy, so the zipformer's other strengths decide for live captions: it is natively
  streaming and about a tenth of Parakeet-He's size. Apple is **about four times worse** (10.4% CER), and the
  intervals are far apart. Apple's errors are half deletions (763 of 1,789 word errors): it drops words in running
  conversation.
- **Voice notes (eval-whatsapp):** the same order. Parakeet-He 3.8%, the zipformer 4.2% (overlapping), Whisper 3.2%;
  Apple 11.6%, about three times the open models.
- **The FLEURS conclusion holds and widens:** on read speech the open models made about 40% fewer character errors
  than Apple; on conversation about 75% fewer.
- **Nemotron zero-shot** does better on conversation than on read speech (8.2% CER, level with Apple there) but
  collapses on voice notes (20.3%). Still not a candidate without a fine-tune.
- **Caveats, plainly.** eval-d1 is **one podcast episode** with two speakers, cut into 17 consecutive five-minute
  segments (every recording's id starts `Mindset 2018.10.07`), so its interval covers variation within that episode, not
  across speakers or recording setups; it says less than its 10,061 words suggest. eval-whatsapp is more varied (54
  separate notes). Both sets are ivrit.ai's own held-out evals, and Parakeet-He, the zipformer and Whisper turbo are
  all trained on ivrit.ai data; the sets are meant to be held out, but a shared domain (Israeli podcasts and
  voice notes) favours them over Apple and Nemotron. Mac, not iPhone; offline whole-file runs, not live latency.


## Licence check

Done before any download, 2026-10-29. The app is paid, so a non-commercial licence rules a model out.

| Item | Licence | Role |
|---|---|---|
| FLEURS he ([`google/fleurs`](https://huggingface.co/datasets/google/fleurs) `he_il` test split, commit `70bb2e8`) | CC BY 4.0 | test data, never trained on, never committed |
| Apple `DictationTranscriber` he-IL (Speech framework, asset through `AssetInventory`) | system framework | engine |
| Parakeet-He, [`thewh1teagle/parakeet-tdt-0.6b-v3-he`](https://huggingface.co/thewh1teagle/parakeet-tdt-0.6b-v3-he) @ `0037204` | CC BY 4.0 (base NVIDIA Parakeet v3 CC BY 4.0; trained on ivrit.ai audio under its licence) | engine |
| ivrit.ai zipformer2 66M streaming, [`ivrit-ai/zipformer2-66m-streaming-he`](https://huggingface.co/ivrit-ai/zipformer2-66m-streaming-he) @ `ee769a2`, `sherpa-onnx/` int8 | CC BY 4.0 (Yakov Kolani's model, mirrored by ivrit.ai) | engine |
| ivrit.ai Whisper large-v3 turbo, [`ivrit-ai/whisper-large-v3-turbo`](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo) @ `f33172a` | Apache-2.0 | reference only (809M parameters, about 1.6 GB: not a phone candidate) |
| NVIDIA Nemotron 3.5 ASR streaming 0.6B, [`nvidia/nemotron-3.5-asr-streaming-0.6b`](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b); sherpa-onnx int8 export [`csukuangfj2/sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-1120ms-int8-2026-06-11`](https://huggingface.co/csukuangfj2/sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-1120ms-int8-2026-06-11) @ `cba1c96` | OpenMDW-1.1, "ready for commercial use" (NVIDIA's card; the export has no licence file of its own, so it inherits NVIDIA's) | engine, zero-shot |
| ivrit.ai eval-d1 and eval-whatsapp ([`ivrit-ai/eval-d1`](https://huggingface.co/datasets/ivrit-ai/eval-d1), [`ivrit-ai/eval-whatsapp`](https://huggingface.co/datasets/ivrit-ai/eval-whatsapp)) | "other": the ivrit.ai licence (CC BY 4.0 base, use limited to AI training or academic research), gated; terms accepted by the owner's Hugging Face account 2026-10-29 | test data (conversation, voice notes), never trained on, never committed; eval-d1 @ `7899b04`, eval-whatsapp @ `1267f61` |
| Common Voice he | CC0 | **not run**, see below |
| sherpa-onnx 2.0.1, transformers 5.22.0, torch 2.15.0, librosa | Apache-2.0 / Apache-2.0 / BSD-3 / ISC | runtimes on the Mac (test tools, never shipped) |

## What could not run

- **Common Voice he** has been distributed through Mozilla Data Collective behind a sign-in since 2025 (the same
  reason #158 left it out), and the old Hugging Face copies are gated or withdrawn. Not fetched.
- ivrit.ai eval-d1 and eval-whatsapp ran in the follow-up (above, [Conversation sets](#conversation-sets-eval-d1-and-eval-whatsapp)) once the Mini was signed in to Hugging Face and the owner had accepted ivrit.ai's terms. Their licence limits use to "training AI models, or academic research": testing a model we plan to train fits that, and the same one-line confirmation with ivrit.ai as for the training data (research §2) covers both.

## Dataset

FLEURS `he_il` test split at dataset commit `70bb2e8` (the commit #158 pinned): **792 clips, 347 distinct sentences,
2.05 h**, read by up to three native speakers each, 16 kHz WAV, every clip under 30 s. The #158 shard maker
(`fleurs.py`, now with `he`) cuts three gender-stratified shards with the same manifest format; the reference is
FLEURS's **raw** transcription through the #202 normaliser. The audio lives in `~/hebrew-eval/` on the M4 Mac mini,
outside the repo, and is never committed or shown on a public page; only aggregate scores are published.

## Machines and engines

Everything ran on the **M4 Mac mini** (10 cores, 16 GB, macOS 26.5), at nice +15 next to other work.

| Engine (result `model`) | Runtime | Settings |
|---|---|---|
| Apple DictationTranscriber he-IL (`DictationTranscriber he-IL`) | Speech framework through the Swift harness (`engine-eval run --engines apple-dictation --locale he-IL`) | no content hints, punctuation on, final results only. **SpeechTranscriber**, the app's engine, has no Hebrew locale on macOS 26 (it lists 30 locales, none Hebrew), so DictationTranscriber is Apple's only on-device Hebrew model. |
| Parakeet-He (`parakeet-tdt-0.6b-v3-he`) | transformers `AutoModelForTDT`, torch MPS (Apple GPU), fp32 | greedy, as the model card shows |
| ivrit.ai zipformer2 66M (`zipformer2-66m-streaming-he-int8`) | sherpa-onnx 2.0.1 `OnlineRecognizer`, CPU, 8 threads | streaming, 1.28 s chunks, greedy; the whole clip is fed, then 3 s of silence to flush |
| ivrit.ai Whisper turbo (`whisper-large-v3-turbo-ivrit`) | transformers Whisper, torch MPS, fp16 | `language="he"`, transcribe, greedy; no timestamps on FLEURS (every clip is under 30 s), sequential long-form with timestamps on the ivrit.ai recordings (up to about 5 minutes) |
| Nemotron 3.5 streaming 0.6B (`nemotron-3.5-asr-streaming-0.6b-1120ms-int8`) | sherpa-onnx 2.0.1 `OnlineRecognizer`, CPU, 8 threads | streaming, 1.12 s chunks (its most accurate setting), **language prompt `he`**, greedy. Zero-shot: Hebrew is in NVIDIA's "adaptation-ready" tier (the tokenizer knows it; it needs a fine-tune). On a two-clip probe `he` read better than `auto`. |

Speed is indicative only: the engines run on different hardware (Apple's Neural Engine path, the GPU through MPS, the
CPU through ONNX Runtime) and the transformers path is not how a phone would run them.

The 2012 mini isn't used: the corpus is 2 hours and every engine needs Apple silicon or a recent ONNX Runtime.

## Running it

```bash
cd scripts/engine-eval && python3 -m pytest     # normaliser, scorer, runners (Hebrew venv or #158's)
swift test --package-path Packages/EngineEval --filter EngineEvalKitTests
# M4 Mac mini, once: the Hebrew venv (kept apart from #158's, which pins sherpa-onnx 1.13.8)
uv venv --python 3.12 ~/hebrew-eval/venv
VIRTUAL_ENV=~/hebrew-eval/venv uv pip install "sherpa-onnx==2.0.1" soundfile numpy scipy "transformers>=5.18" torch librosa pytest num2words pyarrow rapidfuzz
# The whole test, one command: fetches the pinned data and models if missing, shards, runs all five engines
# (resumable), rewrites the report. HE_DELETE_MODELS=1 deletes each model once it has done every shard;
# HE_DELETE_AUDIO=1 deletes the audio once every engine has scored it. HE_SETS picks the sets (default: all three;
# eval-d1 and eval-whatsapp need a Hugging Face token whose account accepted ivrit.ai's terms).
EVAL_REPO=$PWD HE_DELETE_MODELS=1 HE_DELETE_AUDIO=1 scripts/engine-eval/hebrew-driver.sh
cp ~/hebrew-eval/report/hebrew-accuracy-comparison.md docs/perf/
```

## Not in this ticket

Common Voice (above); the iPhone (#201 is the Mac baseline; the phone spikes are research
tickets T4 and T5); live latency; noisy audio; and the two community Hebrew fine-tunes of Nemotron 3.5 that turned up
while looking for exports ([`notmax123/nemotron-3.5-asr-hebrew-streaming-0.6b`](https://huggingface.co/notmax123/nemotron-3.5-asr-hebrew-streaming-0.6b),
[`mralexivy/nemotron-3.5-asr-streaming-0.6b-hebrew`](https://huggingface.co/mralexivy/nemotron-3.5-asr-streaming-0.6b-hebrew)).
Neither is named in #201 and their licences weren't checked, so they weren't fetched. They bear directly on the
"Nemotron needs our fine-tune" assumption and deserve their own ticket.

## Scoring

### The normaliser (#202)

`normalize(text, "he")` in `scripts/engine-eval/edacc_eval/hebrew.py`, applied identically to the reference and to
every engine's text, so whatever quirk is left costs every engine the same. In order:

1. **Direction marks removed** (U+200E/F, U+061C, U+202A–E, U+2066–9, U+FEFF), not turned into spaces. Apple's
   DictationTranscriber starts its Hebrew text with U+200F; a mark inside a word would otherwise split it.
2. **Unicode NFKC, then casefold.** Presentation forms (שׁ as one code point, U+FB2A) decompose; no-break spaces
   become spaces; Latin words inside Hebrew are lower-cased.
3. **Niqqud and cantillation stripped:** every point in U+0591–U+05C7 except the four punctuation marks in that range.
   Maqaf (U+05BE), paseq (U+05C0), sof pasuq (U+05C3) and nun hafukha (U+05C6) become spaces.
4. **Engine markers dropped:** `<...>`, `[...]`, `{...}`. Parentheses stay, as in #158 (FLEURS reads them aloud).
5. **Geresh and gershayim unified, then dropped:** ׳ ״ and every stand-in (`'` `"` `` ` `` `’` `”` `´` `ʼ`), so
   צה״ל = צה"ל = צה''ל = צהל and ג׳ירפה = גירפה. Quotation marks around words go with them.
6. **Symbols to words:** `%` → אחוז (and אחוזים → אחוז), `₪` → שקלים, `$` → דולר.
7. **Thousands separators** (`1,000`) removed; a decimal point between digits (`3.5`) is kept, and every other
   punctuation mark becomes a space. A hyphen-minus is treated like a maqaf.
8. **A prefix letter glued to digits splits off:** `ב3` → `ב 3`, so it matches `ב-3` and `בשלוש`.
9. **Fillers dropped:** אה, אהה, אההה, אמ, אממ, אמממ, אהמ, הממ, המממ, מממ (and Latin uh/um/mm/hmm). אום is not one:
   it is also או"ם (the UN) once gershayim are gone.
10. **Numbers to one form: words become digits** (inverse normalisation), because the word form depends on gender
    and construct state (חמש, חמישה, חמשת are all 5) and digits don't. Both genders, construct forms, common full
    and defective spellings (שלוש/שלש, שישים/ששים), teens (שלוש עשרה, שלושה עשר), tens with or without ו,
    hundreds (מאה, מאתיים, שלוש מאות), thousands (אלף, אלפיים, שלושת אלפים, עשרת אלפים), millions and billions,
    and a digit or decimal before a scale word (`5 אלף`, `2.5 מיליון`). A number word behind up to three prefix
    letters (ו ה ב ל מ ש כ) keeps its prefix as a separate token: בשלוש → `ב 3`. Inside a number only the conjunction
    ו may continue it, and two units in a row are two numbers (חמש ושש → `5 ו 6`).
    - **שנים** is "two" only right before עשר/עשרה (שנים עשר = 12). Standing alone it is almost always "years", and
      reading it as 2 would turn מאה שנים into 102.
    - A lone plural scale word stays a word: אלפים אנשים is "thousands of people", not a number.
    - Words that are also numbers (שני = Monday, אחד in אף אחד) become digits on both sides; that is symmetric, so it
      costs nothing.
11. **Abbreviations always said in full:** ארה"ב → ארצות הברית and ק"מ → קילומטר (with any prefix letter;
    קילומטרים → קילומטר too), and the two accepted spellings לדוגמא / לדוגמה become one. FLEURS writes the
    abbreviations, every engine writes what was said. ק"מ and לדוגמא were added after reading the errors on Apple's
    FLEURS shard 1, before any scoring was final, the way #158 added its rules; each has a test.
12. **Final letter forms are kept** as written: ם/מ, ן/נ and the rest are spelling, and an engine that writes the
    wrong one has made a spelling error.

The ticket's title mentions prefixes. Prefix letters are **not** split from ordinary words: Hebrew writes them
joined, the references do too, and splitting them would hide real errors (ו־ vs ה־ changes the meaning). Their cost
is what CER is for (below). Prefixes are split only from numbers, where the reference and engines really do write
the same words differently (`ב-3`, `ב3`, `בשלוש`).

**Lenient score.** `lenient_hebrew()` folds full and defective spelling (ktiv male / ktiv haser): it drops ו and י
inside a Hebrew word, keeping its first and last letter, so שולחן = שלחן, תוכנית = תכנית, תקווה = תקוה,
קרייה = קריה. Word-initial ו ("and") and final י ("my") stay, since they change the meaning. It is reported **beside**
the strict score, never instead of it: it also merges a few real pairs (a word and its plural spelled only with a
mater lectionis), which is why strict is the headline.

**Known residual mismatches**, equal for every engine: other abbreviations (ת"א, וכו', ס"מ), Latin terms the reference
writes in Latin letters and an engine in Hebrew letters (or the reverse), and Hebrew numbers said as ordinals
(השלישי) against digits.

### WER and CER

- **WER** = (S + D + I) / N over words, pooled over clips (`wer.py`, the #145 alignment).
- **CER** = the same alignment over characters of the normalised text with single spaces between words
  (`char_counts`). In Hebrew one wrong prefix letter makes the whole fused word wrong in WER (ובבית vs בבית is one
  word error but one character), so CER is the in-house decision metric and WER is for comparing with published
  numbers. Research summary for #201: "Use WER to compare with the leaderboard and CER as the in-house decision
  metric."
- Strict and lenient, WER and CER: four numbers per engine per set, each with a 95% CI.

**How much the normaliser moves the scores** (FLEURS he, every engine, against a punctuation-and-case-only baseline
in the spirit of Whisper's `BasicTextNormalizer`): WER falls by 0.8–1.4 points and CER by 0.4–1.1 points for every
engine (Apple 35.9 → 35.0% WER, Parakeet-He 23.1 → 22.3%, Whisper 18.4 → 17.4%), and **the ranking doesn't change**.
The effect is small here because FLEURS's references carry no niqqud and few numbers. Lenient spelling takes off about
another 2 WER points but barely moves CER, because a dropped ו or י is one character. The research had found no
study measuring this; this is a first, read-speech-only number.

Tests: `scripts/engine-eval/tests/test_normalize_hebrew.py` (every rule with real Hebrew pairs, including the
ticket's שולחן/שלחן, צה״ל/צה"ל and 5/חמש).

## Complexity

- Normaliser: O(characters) per text; the number reader is one left-to-right pass over the tokens with constant
  lookahead, O(tokens).
- CER: O(R × H) in characters per clip, O(H) memory. FLEURS clips are a few hundred characters; eval-d1 transcripts run to 3,000+ characters (10M cells), so above 250,000 cells the alignment runs in C through rapidfuzz (same minimum edit distance, tested against the Python path).
- Scorer: O(result lines + words² + characters² per clip), plus O(1,000 × sentences) per bootstrap, four per cell;
  seconds at this size.
- Runs: O(clips × engines), one model in memory at a time. Disk: models 6.4 GB in total (Whisper's fp32 checkpoint
  is 3.2 GB), 0.4 GB of FLEURS tarball and 0.23 GB of shards, plus 0.29 GB of eval-d1 and eval-whatsapp shards; the driver can delete each model once it's done and the audio once it's scored.

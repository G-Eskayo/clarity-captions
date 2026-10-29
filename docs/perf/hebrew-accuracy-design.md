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
| ivrit.ai eval-d1 and eval-whatsapp ([`ivrit-ai/eval-d1`](https://huggingface.co/datasets/ivrit-ai/eval-d1), [`ivrit-ai/eval-whatsapp`](https://huggingface.co/datasets/ivrit-ai/eval-whatsapp)) | "other": the ivrit.ai licence (CC BY 4.0 base, use limited to AI training or academic research), gated | **not run**, see below |
| Common Voice he | CC0 | **not run**, see below |
| sherpa-onnx 2.0.1, transformers 5.22.0, torch 2.15.0, librosa | Apache-2.0 / Apache-2.0 / BSD-3 / ISC | runtimes on the Mac (test tools, never shipped) |

## What could not run

- **ivrit.ai eval-d1 and eval-whatsapp** are gated on Hugging Face: a signed-in account has to accept ivrit.ai's terms
  before the files download (the API answers `gated: auto`). The Mac mini has no Hugging Face token, and this run was
  unattended, so nobody could accept them. They matter most: they are conversation and voice notes, closer to live
  captions than read speech, and they are where every published Hebrew number comes from. Once the owner accepts the
  terms and saves a token on the Mini, the driver needs only a shard maker for their parquet files (a follow-up).
  Their licence restricts use to "training AI models, or academic research". Testing a model we plan to train fits
  that purpose, but it is worth the same one-line confirmation with ivrit.ai as the training data (research §2).
- **Common Voice he** has been distributed through Mozilla Data Collective behind a sign-in since 2025 (the same
  reason #158 left it out), and the old Hugging Face copies are gated or withdrawn. Not fetched.
- So this report has **one test set, FLEURS he: read Wikipedia sentences**. It is the set where the published models
  are weakest (Parakeet-He's card: "weaker on read encyclopedic text: rare names, numbers, Latin terms"), so it
  understates them against their conversation scores. It is not a stand-in for eval-d1.

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
| ivrit.ai Whisper turbo (`whisper-large-v3-turbo-ivrit`) | transformers Whisper, torch MPS, fp16 | `language="he"`, transcribe, greedy, no timestamps (every clip is under 30 s) |
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
VIRTUAL_ENV=~/hebrew-eval/venv uv pip install "sherpa-onnx==2.0.1" soundfile numpy scipy "transformers>=5.18" torch librosa pytest num2words
# The whole test, one command: fetches the pinned data and models if missing, shards, runs all five engines
# (resumable), rewrites the report. HE_DELETE_MODELS=1 deletes each model once it has done every shard.
EVAL_REPO=$PWD HE_DELETE_MODELS=1 scripts/engine-eval/hebrew-driver.sh
cp ~/hebrew-eval/report/hebrew-accuracy-comparison.md docs/perf/
```

## Not in this ticket

eval-d1, eval-whatsapp and Common Voice (above); the iPhone (#201 is the Mac baseline; the phone spikes are research
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

Tests: `scripts/engine-eval/tests/test_normalize_hebrew.py` (every rule with real Hebrew pairs, including the
ticket's שולחן/שלחן, צה״ל/צה"ל and 5/חמש).

## Complexity

- Normaliser: O(characters) per text; the number reader is one left-to-right pass over the tokens with constant
  lookahead, O(tokens).
- CER: O(R × H) in characters per clip (FLEURS clips are under 30 s, a few hundred characters).
- Scorer: O(result lines + words² + characters² per clip), plus O(1,000 × sentences) per bootstrap, four per cell;
  seconds at this size.
- Runs: O(clips × engines), one model in memory at a time. Disk: models 6.4 GB in total (Whisper's fp32 checkpoint
  is 3.2 GB), 0.4 GB of FLEURS tarball and 0.23 GB of shards; the driver can delete each model once it's done.

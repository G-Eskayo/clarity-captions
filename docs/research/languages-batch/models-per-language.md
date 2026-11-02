# Single-language / regional specialist ASR models for Seal Speak

Research date / access date for every URL below: **2026-10-30**. Read-only; no weights downloaded.
Scope: per-language specialist models. Big multilingual families (Whisper base, Parakeet v3, Canary, Omnilingual,
Qwen3-ASR, Moonshine, Nemotron base, MMS, Vosk generic) are covered by a separate agent and only appear here when a
specialist is a fine-tune of one.

## Conventions

- **Licence** is read from the Hugging Face API `cardData.license` (https://huggingface.co/api/models/<id>) and the
  model card, unless stated otherwise.
- **Tiers**
  - **Established**: read directly from the primary source (model card, licence text, release list).
  - **Contested**: there is a reason to doubt it: conflicting numbers, suspicious results (likely test leakage), unclear data provenance,
    or a licence that conflicts with upstream data.
  - **Speculative**: my inference, not stated anywhere.
  - **Unknown**: not published.
- **All WER/CER numbers are self-reported by the model authors** unless marked otherwise. "Established" on a number means
  "the card really says this", not "independently reproduced". Normalisation differs between cards, so numbers are not
  directly comparable across models.
- **Ship rule**: NC / ND licences, a missing licence, gated custom licences and revenue-capped licences are marked
  **DO NOT SHIP** or **FLAG**.

## Useful cross-cutting findings

1. **NVIDIA per-language FastConformer hybrids (115M, CC-BY-4.0)** exist for ar, fa, hr, hy, ka (+ a *streaming 80 ms*
   ka variant), kk-ru, nl, pl, ru, ua(uk), uz (plus be/ca/de/es/fr/it/pt). They are the same size class as the ivrit.ai
   Hebrew model, have a proven NeMo→ONNX path, and are the obvious default "specialist" for those languages.
   List: https://huggingface.co/api/models?author=nvidia&search=stt_ (Established).
   Most of them are offline (full-context). Only `stt_ka_..._streaming_80ms_pc` is cache-aware streaming. The others would need
   chunked or simulated streaming, or a streaming re-train like Typhoon did for Thai (Speculative).
2. **sherpa-onnx ready-made exports** (release `asr-models`, https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models)
   cover these target languages: Russian (GigaAM v1/v2/v3 CTC+RNNT, T-one streaming, Vosk small streaming zipformer,
   zipformer-ru), Vietnamese (zipformer-vi, zipformer-vi-30M), Persian (Shenava Koochik/Rizeh/Rizeh-Pizeh, streaming and
   non-streaming), Bengali (Vosk streaming zipformer), Thai (zipformer-thai-2024-06-20), and the NeMo multilingual
   be-de-en-es-fr-hr-it-pl-ru-uk FastConformer. (Established, from the GitHub API asset list.)
3. **Nemotron-3.5-ASR-streaming-0.6B community fine-tunes** (Persian, Arabic dialects, Thai, Swahili, Hausa) are now the
   common way to get a *streaming* specialist. Licence is **OpenMDW-1.1**: a permissive "deal … without restriction" grant,
   needing only that the licence and notices travel with redistributed weights (https://openmdw.ai/license/1-1/, Established).
   At 600M they are about 2x the size budget. 4-bit gives about 300 MB (Speculative).
4. **BuzzASR** (https://huggingface.co/BuzzASR): a whole family of per-language Whisper-large-v3 fine-tunes (1.55B, MIT,
   offline) covering almost every target language, from arXiv:2609.09554 (EMNLP Findings 2026). Useful as an accuracy
   ceiling or offline fallback, not as an on-device streaming engine. Several cards show implausible Common Voice numbers
   (Amharic CV CER 0.02%, Punjabi 0.39%, Kazakh 0.62%) next to FLEURS numbers 10–100x worse, and some FLEURS numbers are
   *worse* than zero-shot Whisper (Polish 9.98 vs 1.81 CER, Thai 23.8 vs 6.6, Hindi 17.1 vs 9.3). Treat as **Contested**.
5. **GigaAM-Multilingual** (Sber, MIT, 220M/600M, CTC; https://huggingface.co/ai-sage/GigaAM-Multilingual) claims
   best-in-class FLEURS WER for Kazakh (5.2/4.4), Kyrgyz and Uzbek (10.0/7.3), beating Omnilingual-1B, Seamless and Whisper-v3.
   It is 220M with a Core ML community port (`vadimsuhanov/gigaam-multilingual-large-ctc-coreml`). Established (self-reported).

---

## GROUP 1

### Arabic (MSA + dialects)

Bottom line: there is **no small (<300M), streaming, commercially licensed Arabic model that handles dialects well.**
- The best small option is MSA-oriented and offline: NVIDIA FastConformer 115M.
- Streaming dialect coverage exists only at 600M+ (a Nemotron fine-tune with unclear data licence) or at 4B (Voxtral).
- Levantine/Palestinian specifically: the only per-dialect numbers found are on the Lahgtna balanced set. Palestinian WER
  there is 30.1% for the best model (Whisper-large-v3 fine-tune).

| Candidate | Licence | Size | Streaming | Published accuracy | Export |
|---|---|---|---|---|---|
| [nvidia/stt_ar_fastconformer_hybrid_large_pc_v1.0](https://huggingface.co/nvidia/stt_ar_fastconformer_hybrid_large_pc_v1.0) | CC-BY-4.0 (Established) | 115M | No ("non-streaming") | WER: FLEURS 8.18, MCV 10.20, MASC 11.46 (self-reported) | .nemo; community Core ML of the `pcd` (diacritised) sibling: [dev-ahmedhany/..-coreml](https://huggingface.co/dev-ahmedhany/stt_ar_fastconformer_hybrid_large_pcd_v1.0-coreml); sherpa-onnx NeMo-hybrid export script works (a Gulf fine-tune used it) |
| [oddadmix/nemotron-3.5-asr-arabic-dialectal-v2](https://huggingface.co/oddadmix/nemotron-3.5-asr-arabic-dialectal-v2) | "other" on the card; the ONNX mirror says OpenMDW-1.1. Training set [lahgtna-v3-small](https://huggingface.co/datasets/oddadmix/lahgtna-v3-small) states **no licence or sources**. **FLAG (Contested)** | 638M | Yes (cache-aware) | WER 42.3 / CER 14.8 on a 2,600-clip, 13-dialect balanced test (self-reported) | ONNX: [OpenVoiceOS/...-onnx](https://huggingface.co/OpenVoiceOS/nemotron-3.5-asr-arabic-dialectal-v2-onnx) (int8 encoder 617 MB, no streaming caches in graph) |
| [mistralai/Voxtral-Mini-4B-Realtime-Arabic](https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-Arabic) | Apache-2.0 stated in card text (Established) | 4.4B | Yes (480 ms delay) | avg CER 8.82 over 7 Arabic benchmarks incl. Darija-in-the-wild (self-reported) | ONNX/WebGPU community port. Far too big for iPhone (Speculative) |

Also relevant:
- [oddadmix/whisper-large-v3-arabic-dialectal-v2](https://huggingface.co/oddadmix/whisper-large-v3-arabic-dialectal-v2):
  Apache-2.0, 1.54B, offline, overall WER 32.0.
  - Per-dialect WER: Saudi/Gulf 16.9, Egyptian 27.1, Syrian 27.2, **Palestinian 30.1**, Lebanese 31.7, Moroccan 34.0, Tunisian 47.8.
  - Sibling sizes: turbo 809M (33.2), whisper-small 244M (40.3).
  - Same unlicensed dataset. **Contested.**
- [CohereLabs/cohere-transcribe-arabic-07-2026](https://huggingface.co/CohereLabs/cohere-transcribe-arabic-07-2026):
  Apache-2.0, gated (share contact info), 2B, not described as streaming.
  - Open Universal Arabic ASR leaderboard avg WER 25.87 / CER 11.80; SADA 37.5, Casablanca (Maghrebi) 49.7.
  - Best open model on that board as of 2026-07-07 (self-reported via the card).
- **DO NOT SHIP**:
  - [MBZUAI/artst_asr_v3](https://huggingface.co/MBZUAI/artst_asr_v3) (ArTST): **CC-BY-NC-4.0**.
  - [vladadu/stt-ar-fastconformer-gulf-sherpa-onnx](https://huggingface.co/vladadu/stt-ar-fastconformer-gulf-sherpa-onnx): **CC-BY-NC-SA-4.0**,
    because the SADA training data is NC. Any SADA-trained fine-tune inherits this risk (Contested for others that don't declare it).
  - [NAMAA-Space/NAMAA-Saudi-ASR-V1](https://huggingface.co/NAMAA-Space/NAMAA-Saudi-ASR-V1): Apache LoRA on the 2B Cohere model,
    26.5% WER on Saudi podcasts. Too big.
- PengChengStarling streaming zipformer (ar/en/id/ja/ru/th/vi/zh,
  [sherpa export](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10),
  [source](https://github.com/yangb05/PengChengStarling)): **no licence stated anywhere → DO NOT SHIP (Unknown)**.
  Self-reported MGB-2 24.37 vs Whisper-v3 30.3.
- SauDial / QCRI: no open ASR checkpoints found on HF under those names (Unknown).

### Persian / Farsi

Strongest small-specialist story after Hebrew. A whole **Apache-2.0 family with streaming, sherpa-onnx and Core ML
already exported** (Shenava, by Reza2kn / VisualEars).

| Candidate | Licence | Size | Streaming | Published accuracy | Export |
|---|---|---|---|---|---|
| [Reza2kn/Shenava-Koochik-v1.0](https://huggingface.co/Reza2kn/Shenava-Koochik-v1.0) (+ [v1.5](https://huggingface.co/Reza2kn/Shenava-Koochik-v1.5) fixes the RNNT head) | Apache-2.0 | 114M | Yes (cache-aware; Core ML iOS15 streaming build) | WER/CER: FLEURS-fa 10.64 / 3.79; in-house golden set 7.49 / 2.30 | sherpa-onnx (in official release), Core ML fp16, [Core ML iOS15 streaming](https://huggingface.co/Reza2kn/Shenava-Koochik-1.0-CoreML-iOS15-fp16), ONNX, tract |
| [Reza2kn/shenava-fa-fastconformer-streaming-32m](https://huggingface.co/Reza2kn/shenava-fa-fastconformer-streaming-32m) / [Shenava-Rizeh-v1.0](https://huggingface.co/Reza2kn/Shenava-Rizeh-v1.0) | Apache-2.0 | 32M | Yes, multi-latency 0–1040 ms | 11.08 WER / 3.17 CER at 0 ms lookahead on its own golden set; Rizeh FLEURS-fa 14.45 WER | sherpa-onnx (official), Core ML (Rizeh-Pizeh 6.9M too) |
| [mehdi-hf/nemotron-asr-streaming-farsi](https://huggingface.co/mehdi-hf/nemotron-asr-streaming-farsi) | OpenMDW-1.1 | 622M | Yes (1.12 s / 0.32 s) | FLEURS-fa 8.8 WER; conversational (YouTube/films) 26.0 vs 54.4 for NVIDIA fa model | NeMo |

- Also: [nvidia/stt_fa_fastconformer_hybrid_large](https://huggingface.co/nvidia/stt_fa_fastconformer_hybrid_large),
  CC-BY-4.0, 115M. The Nemotron-Farsi card says it gets 24.2 WER on FLEURS.
- **Contested**: Shenava's training set [visualears-persian-asr-16k](https://huggingface.co/datasets/Reza2kn/visualears-persian-asr-16k)
  is declared Apache-2.0, but it is a 512 GB scrape with a per-row `source` field and model-generated pseudo-labels.
  Provenance of the raw audio is not itemised on the card. Do a provenance check before shipping.

### Turkish

| Candidate | Licence | Size | Streaming | Accuracy | Export |
|---|---|---|---|---|---|
| [mihuai/turkish-stt-66m-v2](https://huggingface.co/mihuai/turkish-stt-66m-v2) | **Custom "mihu Community License"**. Free only below USD 500k annual revenue, needs commercial registration, mandatory "Powered by mihu" in the UI, no redistribution except as allowed. **FLAG** | 66M (~68 MB int8) | Yes (Zipformer transducer, 320 ms) | FLEURS-tr WER 10.06 (standard norm.) / 6.21 (Turkish norm.) | sherpa-onnx int8 ONNX in repo |
| [BuzzASR/turkish](https://huggingface.co/BuzzASR/turkish) | MIT | 1.55B | No | FLEURS CER 2.0 / WER 7.99 | HF transformers |

- No permissive, small, streaming Turkish specialist was found (Established absence on HF search).
- **Inference**: Parakeet/Canary v3 doesn't cover Turkish. The likely permissive route is a Nemotron-streaming fine-tune or our
  own zipformer trained on Common Voice + FLEURS (Speculative).

### Russian

Very well served. **Several MIT/Apache streaming models, already in sherpa-onnx, with Core ML community ports.**

| Candidate | Licence | Size | Streaming | Accuracy | Export |
|---|---|---|---|---|---|
| [t-tech/T-one](https://huggingface.co/t-tech/T-one) | Apache-2.0 | 71.7M | Yes (300 ms chunks, CTC + KenLM) | WER: call-centre 8.63, CV19 5.32, OpenSTT calls re-labelled 7.94 | ONNX in repo; sherpa-onnx `streaming-t-one-russian-2025-09-08` |
| [ai-sage/GigaAM-v3](https://huggingface.co/ai-sage/GigaAM-v3) ([GitHub](https://github.com/salute-developers/GigaAM)) | MIT | 220–240M | No (≤25 s segments; long-form via VAD) | v3 RNNT avg WER 8.3 over 10 sets (CV19 0.9, Golos crowd 2.4, callcentre 9.5) vs T-one+LM 16.3 on the same table | ONNX ([istupakov/gigaam-v3-onnx](https://huggingface.co/istupakov/gigaam-v3-onnx)), sherpa-onnx, Core ML ([smkrv](https://huggingface.co/smkrv/gigaam-v3-e2e-rnnt-coreml), [vadimsuhanov](https://huggingface.co/vadimsuhanov/gigaam-v3-rnnt-coreml)); e2e variants output punctuation |
| [alphacep/vosk-model-small-streaming-ru](https://huggingface.co/alphacep/vosk-model-small-streaming-ru) | Apache-2.0 | ~20M | Yes (Zipformer2) | CV ru WER 11.3 | sherpa-onnx |

- **Contested**: each vendor's table favours itself. T-one's table shows T-one beating GigaAM-v2 on telephony; Sber's
  table shows GigaAM-v3 beating T-one on 9 of 10 sets.

### Ukrainian

| Candidate | Licence | Size | Streaming | Accuracy | Export |
|---|---|---|---|---|---|
| [nvidia/stt_ua_fastconformer_hybrid_large_pc](https://huggingface.co/nvidia/stt_ua_fastconformer_hybrid_large_pc) | CC-BY-4.0 | 115M | No | MCV12 test WER 5.66 (no P&C) / 8.06 (P&C) | .nemo; ONNX via NeMo export |
| NeMo multilingual be-de-en-es-fr-hr-it-pl-ru-uk FastConformer | CC-BY-4.0 (NVIDIA) | ~115M (Speculative) | No | Unknown | **sherpa-onnx official** (`nemo-fast-conformer-transducer-be-de-en-es-fr-hr-it-pl-ru-uk-20k`) |
| [asfberlin/fast-ukrainian-asr](https://huggingface.co/asfberlin/fast-ukrainian-asr) | MIT | ~220M (GigaAM-ML backbone; a 600M sibling exists) | No | cv10 WER 9.64 vs Whisper-v3 13.85; *loses* to Whisper on broadcast sets (28.0 vs 17.0) | PyTorch ckpt |

### Polish

| Candidate | Licence | Size | Streaming | Accuracy | Export |
|---|---|---|---|---|---|
| [nvidia/stt_pl_fastconformer_hybrid_large_pc](https://huggingface.co/nvidia/stt_pl_fastconformer_hybrid_large_pc) | CC-BY-4.0 | 115M | No | WER (no P&C): MCV12 test 8.67, MLS test 5.78, VoxPopuli test 8.45 | .nemo; sherpa via multilingual pl-ru-uk bundle |
| [yuriyvnv/parakeet-tdt-0.6b-polish](https://huggingface.co/yuriyvnv/parakeet-tdt-0.6b-polish) | CC-BY-4.0 | 600M | No | CV17 pl test (WER on card, raw text) | .nemo |

### Hindi, Urdu, Bengali (and Group-2 Indic: Tamil, Telugu, Marathi, Punjabi)

**Primary candidate: AI4Bharat IndicConformer per-language models.**
- Licence MIT, ~120M each, hybrid CTC/RNNT, offline. Gated: you must accept the conditions on HF.
- Per language: [hi](https://huggingface.co/ai4bharat/indicconformer_stt_hi_hybrid_ctc_rnnt_large),
  [ur](https://huggingface.co/ai4bharat/indicconformer_stt_ur_hybrid_ctc_rnnt_large),
  [bn](https://huggingface.co/ai4bharat/indicconformer_stt_bn_hybrid_ctc_rnnt_large),
  [ta](https://huggingface.co/ai4bharat/indicconformer_stt_ta_hybrid_ctc_rnnt_large),
  [te](https://huggingface.co/ai4bharat/indicconformer_stt_te_hybrid_ctc_rnnt_large),
  [mr](https://huggingface.co/ai4bharat/indicconformer_stt_mr_hybrid_ctc_rnnt_large),
  [pa](https://huggingface.co/ai4bharat/indicconformer_stt_pa_hybrid_ctc_rnnt_large).
- Multilingual 600M version (22 languages) ships ONNX in-repo:
  [indic-conformer-600m-multilingual](https://huggingface.co/ai4bharat/indic-conformer-600m-multilingual).
- **Accuracy is Unknown**: the cards publish no per-language WER. The 600M card gives only Hindi 13.2 WER on Vaani-Benchmark.
- Licence MIT is Established. The gating text was not readable without login (Unknown terms).

| Language | Best small | Others |
|---|---|---|
| Hindi | IndicConformer-hi 120M (MIT, gated, offline, WER Unknown) | [ARTPARK-IISc/whisper-large-v3-vaani-hindi](https://huggingface.co/ARTPARK-IISc/whisper-large-v3-vaani-hindi) (Apache, 1.5B); [vasista22/whisper-hindi-small](https://huggingface.co/vasista22/whisper-hindi-small) (Apache, 244M, Vistaar); Bodhan "Indic-Transcribe" (see flag below) |
| Urdu | IndicConformer-ur 120M (MIT, gated) | [kingabzpro/whisper-large-v3-turbo-urdu](https://huggingface.co/kingabzpro/whisper-large-v3-turbo-urdu) (Apache, 809M); BuzzASR/urdu FLEURS CER 7.5 / WER 21.8 |
| Bengali | [alphacep/vosk-model-small-streaming-bn](https://huggingface.co/alphacep/vosk-model-small-streaming-bn): Apache-2.0, small streaming Zipformer, **in sherpa-onnx**, but weak (Banspeech WER 32.9) | IndicConformer-bn 120M (MIT); [kazalbrur/bangla-asr-conformer-120m-dialects](https://huggingface.co/kazalbrur/bangla-asr-conformer-120m-dialects) (Apache, 121.5M, regional dialects, macro WER 27.45 on own eval) |

- **FLAG**: [bodhan-ai/indic-transcribe-core / -flex](https://huggingface.co/bodhan-ai/indic-transcribe-core) is a Canary-1B-v2
  fine-tune, 1.22B, 25 Indic languages, AI4Bharat's recommended successor. It uses the **custom "Indic Open Model License v1.0"**:
  - It grants commercial use and distribution.
  - It requires the in-UI attribution "Built with [Model] from Bodhan AI / AI4Bharat".
  - It requires approval only for *hosting* for third parties. On-device use as an internal component is excluded from that requirement.
  - Licence text read via the Core ML mirror
    ([Muesli-HQ/indic-transcribe-core-coreml](https://huggingface.co/Muesli-HQ/indic-transcribe-core-coreml)), which also
    proves a Core ML port exists.

### Vietnamese

Strong field. **Best: gipformer1.5 (MIT, 68M)**.

| Candidate | Licence | Size | Streaming | Accuracy (WER) | Export |
|---|---|---|---|---|---|
| [g-group-ai-lab/gipformer1.5-68M-rnnt](https://huggingface.co/g-group-ai-lab/gipformer1.5-68M-rnnt) | MIT | 68M | Not stated (offline Zipformer; Unknown) | FLEURS 12.65, CV 6.45, vivos 4.25, call-centre "tele-medium" 15.44 (beats PhoWhisper-large 26.8 and Qwen3-ASR-1.7B 26.3 there) | ONNX + int8 ONNX (sherpa format) in repo |
| [khanhld/chunkformer-rnnt-large-vie](https://huggingface.co/khanhld/chunkformer-rnnt-large-vie) | CC-BY-4.0 | 113M | Chunked long-form (not low-latency streaming; Speculative) | vivos 2.49, CV 5.18, VLSP2020-T1 12.75 | PyTorch |
| [vinai/PhoWhisper-small](https://huggingface.co/vinai/PhoWhisper-small) (tiny→large) | BSD-3-Clause | 244M (large 1.5B) | No | FLEURS 16.11 (small) / 12.62 (large), per the gipformer table | ct2/whisper.cpp community ports |

- **DO NOT SHIP**: [hynt/Zipformer-30M-RNNT-Streaming-6000h](https://huggingface.co/hynt/Zipformer-30M-RNNT-Streaming-6000h)
  is **CC-BY-NC-ND-4.0**. It is otherwise ideal: 30M, streaming, VLSP 2025 winner (non-streaming sibling).
  The sherpa-onnx `zipformer-vi-30M-2026-02-09` release is presumably this model (Speculative), so don't ship that either.
- Also: [nvidia/parakeet-ctc-0.6b-Vietnamese](https://huggingface.co/nvidia/parakeet-ctc-0.6b-Vietnamese).
  - Licence: NVIDIA Open Model License (custom; permits commercial use, but flag it).
  - Gipformer's table shows it is worse than gipformer.
  - A Core ML port exists ([leakless](https://huggingface.co/leakless/parakeet-ctc-0.6b-Vietnamese-coreml)).

### Indonesian

| Candidate | Licence | Size | Streaming | Accuracy (WER) | Export |
|---|---|---|---|---|---|
| [PixelML/sea-asr-id](https://huggingface.co/PixelML/sea-asr-id) | Apache-2.0 (base `google/embeddinggemma-2` is also Apache-2.0 per its HF card). Optional n-gram LM is **CC BY-SA 3.0** (share-alike: skip it or comply) | Card says 364M; HF safetensors count 112M (**Contested**) | Yes, 0.48 s chunks (CTC) | Greedy: FLEURS 9.0, CV27 9.1, GigaSpeech2 18.7; +LM: 6.1 / 7.0 / 17.4 (≈ Whisper-large-v3-turbo) | Safetensors; CPU-friendly |
| [BuzzASR/indonesian](https://huggingface.co/BuzzASR/indonesian) | MIT | 1.55B | No | FLEURS 6.21 WER | — |
| [indonesian-nlp/wav2vec2-indonesian-javanese-sundanese](https://huggingface.co/indonesian-nlp/wav2vec2-indonesian-javanese-sundanese) | Apache-2.0 | ~300M | Possible (CTC) | older CV-era model | — |

- The card says Qwen3-ASR-1.7B was its "teacher" (pseudo-labels). Qwen3-ASR is Apache, so that is not a licence problem (Speculative).

### Serbian / Croatian / Bosnian (BCS)

| Candidate | Licence | Size | Streaming | Accuracy | Export |
|---|---|---|---|---|---|
| [nvidia/stt_hr_fastconformer_hybrid_large_pc](https://huggingface.co/nvidia/stt_hr_fastconformer_hybrid_large_pc) | CC-BY-4.0 | 115M | No | ParlaSpeech-HR test WER 4.17 (no P&C) / 8.7 (P&C) | .nemo; hr also in sherpa multilingual bundle |
| [classla/wav2vec2-xls-r-juznevesti-sr](https://huggingface.co/classla/wav2vec2-xls-r-juznevesti-sr) | **No licence on card → FLAG (Unknown)** | 300M | CTC | JuzneVesti test WER 29.0 / CER 13.8 | ONNX mirror by OpenVoiceOS |
| [classla/whisper-large-v3-mici-princ](https://huggingface.co/classla/whisper-large-v3-mici-princ) / [5roop/whisper-large-v3-ParlaSpeech-HR](https://huggingface.co/5roop/whisper-large-v3-ParlaSpeech-HR) | CC-BY-SA-4.0 (share-alike on weights; FLAG) | 1.55B | No | — | — |

- Using the Croatian model for Serbian/Bosnian is plausible because the languages are mutually intelligible. It outputs Latin
  script only, and accuracy on Serbian is Unknown (Speculative).
- No "whisper-large-v3-serbian" by CLASSLA was found. BuzzASR/serbian shows CV CER 84.95 (broken; Contested).

### Amharic

| Candidate | Licence | Size | Streaming | Accuracy | Export |
|---|---|---|---|---|---|
| [snapwre/hohe-asr-amharic](https://huggingface.co/snapwre/hohe-asr-amharic) | CC-BY-4.0 | 606M (w2v-BERT 2.0) | No (CTC, chunked) | FLEURS am_et WER 17.86 / CER 6.28; with 5-gram 16.04 / 5.99 | safetensors |
| [badrex/Ethio-ASR-amharic](https://huggingface.co/badrex/Ethio-ASR-amharic) | CC-BY-4.0 | 600M | No | WER 22.37 (own test); a 94M AfriHuBERT variant gets 30.95 | — |

Nothing small and good exists. The 94M variant is the only <300M option.

### Swahili

| Candidate | Licence | Size | Streaming | Accuracy | Export |
|---|---|---|---|---|---|
| [Tonykip/nemotron-3.5-swahili-streaming-asr](https://huggingface.co/Tonykip/nemotron-3.5-swahili-streaming-asr) | OpenMDW-1.1 | 600M | Yes | FLEURS sw_ke ~30 WER / ~11 CER | NeMo |
| [badrex/w2v-bert-2.0-swahili-asr](https://huggingface.co/badrex/w2v-bert-2.0-swahili-asr) | CC-BY-4.0 | 580M | No | not in card text | — |
| [BuzzASR/swahili](https://huggingface.co/BuzzASR/swahili) | MIT | 1.55B | No | FLEURS CER 4.51 / WER 14.6 | — |

No small specialist was found.

### Tagalog / Filipino

| Candidate | Licence | Size | Streaming | Accuracy (WER) | Export |
|---|---|---|---|---|---|
| [PixelML/sea-asr-ph](https://huggingface.co/PixelML/sea-asr-ph) | Apache-2.0 | Card says 364M; safetensors count 109M (**Contested**) | Yes, 0.48 s (19.0 WER streaming) | FLEURS fil 17.2, PH conversational (silver labels) 20.1; Whisper-large-v3 10.6 / 17.4 | safetensors |
| [BuzzASR/filipino](https://huggingface.co/BuzzASR/filipino) | MIT | 1.55B | No | FLEURS CER 3.63 / WER 9.68 | — |

- The training data is "Creative Commons Filipino speech" with self-made labels
  ([PixelML/sea-asr-ph-data](https://huggingface.co/datasets/PixelML/sea-asr-ph-data)). Check that none of it is CC-NC (Unknown).

---

## GROUP 2

| Language | Best candidate (licence, size, streaming, published WER) | Notes |
|---|---|---|
| **Thai** | [typhoon-ai/typhoon-asr-streaming-115m](https://huggingface.co/typhoon-ai/typhoon-asr-streaming-115m): CC-BY-4.0, 115M, **streaming** (cache-aware), CER 19.4 @1040 ms on TVSpeech | The offline [typhoon-asr-realtime](https://huggingface.co/typhoon-ai/typhoon-asr-realtime) (CC-BY-4.0, 114M) gets CER 9.84. [typhoon-asr-streaming-nemotron-0.6b](https://huggingface.co/typhoon-ai/typhoon-asr-streaming-nemotron-0.6b) (OpenMDW, 0.6B) gets CER 14.1 TVSpeech / 9.3 GigaSpeech2. Thonburian [biodatlab/distill-whisper-th-small](https://huggingface.co/biodatlab/distill-whisper-th-small) is MIT, 206M, offline. A sherpa-onnx `zipformer-thai-2024-06-20` also exists (licence not checked). |
| **Tamil / Telugu / Marathi / Punjabi** | IndicConformer per-language 120M, MIT, gated, offline, WER Unknown (see Indic section) | [vasista22/whisper-tamil-small](https://huggingface.co/vasista22/whisper-tamil-small) and [whisper-telugu-small](https://huggingface.co/vasista22/whisper-telugu-small) are Apache, 244M. BuzzASR numbers for these are Contested. |
| **Greek** | No small specialist found. [myned-ai/parakeet-tdt-0.6b-v3-greek](https://huggingface.co/myned-ai/parakeet-tdt-0.6b-v3-greek): CC-BY-4.0, 600M, offline | BuzzASR/greek FLEURS WER 11.0 (MIT, 1.55B) |
| **Dutch** | [nvidia/stt_nl_fastconformer_hybrid_large_pc](https://huggingface.co/nvidia/stt_nl_fastconformer_hybrid_large_pc): CC-BY-4.0, 115M, offline, MCV12 9.19 / MLS 12.09 WER (no P&C) | Parakeet v3 covers nl (other agent). [GroNLP/wav2vec2-dutch-large-ft-cgn](https://huggingface.co/GroNLP/wav2vec2-dutch-large-ft-cgn) has no licence on card. |
| **Romanian** | No small specialist beyond [gigant/romanian-wav2vec2](https://huggingface.co/gigant/romanian-wav2vec2) (Apache-2.0, 315M, CTC) | Parakeet v3 covers ro (other agent). BuzzASR/romanian FLEURS WER 9.84. |
| **Hausa** | [EYEDOL/nemotron-3.5-asr-streaming-hausa](https://huggingface.co/EYEDOL/nemotron-3.5-asr-streaming-hausa): OpenMDW-1.1, 600M, streaming, WER 33.5 / CER 9.4 (own test) | [NCAIR1/Hausa-ASR](https://huggingface.co/NCAIR1/Hausa-ASR) (Nigeria's NCAIR, Whisper-small) is **"other" licence + gated → FLAG**. moonshine-tiny-hausa is **CC-BY-NC-SA → DO NOT SHIP**. |
| **Yoruba** | Nothing commercially clear. [NCAIR1/Yoruba-ASR](https://huggingface.co/NCAIR1/Yoruba-ASR) is "other" + gated (FLAG) | moonshine-tiny-yoruba: check licence (sibling Hausa model is NC). |
| **Uzbek** | [ai-sage/GigaAM-Multilingual](https://huggingface.co/ai-sage/GigaAM-Multilingual): MIT, 220M, offline CTC, FLEURS uz WER 10.0 (220M) / 7.3 (600M) | [nvidia/stt_uz_fastconformer_hybrid_large_pc](https://huggingface.co/nvidia/stt_uz_fastconformer_hybrid_large_pc) (CC-BY, 115M) gets FLEURS 10.73 / MCV 7.18 (no P&C). [alphacep/vosk-model-small-streaming-uz](https://huggingface.co/alphacep/vosk-model-small-streaming-uz) (Apache, streaming) gets FLEURS 17.67. |
| **Kazakh** | GigaAM-Multilingual: MIT, 220M, FLEURS kk WER 5.2 (600M: 4.4) | [nvidia/stt_kk_ru_fastconformer_hybrid_large](https://huggingface.co/nvidia/stt_kk_ru_fastconformer_hybrid_large) (CC-BY, 115M, kk+ru) gets KSC2 read 4.43 / spontaneous 15.25. ISSAI (IS2AI GitHub) publishes corpora (KSC2, CC-BY-4.0) and a [TurkicASR](https://github.com/IS2AI/TurkicASR) model (CC-BY-4.0). No better-licensed small ISSAI checkpoint found. |
| **Georgian** | [nvidia/stt_ka_fastconformer_hybrid_transducer_ctc_large_streaming_80ms_pc](https://huggingface.co/nvidia/stt_ka_fastconformer_hybrid_transducer_ctc_large_streaming_80ms_pc): CC-BY-4.0, ~115M, **streaming 80 ms**, MCV 7.44 / FLEURS 16.0 WER | The offline sibling gets 5.73 / 13.44. [EchoesML/Georgian-NeMo](https://huggingface.co/EchoesML/Georgian-NeMo) is "research and educational purposes only" → **DO NOT SHIP**. |
| **Armenian** | [nvidia/stt_hy_fastconformer_hybrid_large_pc](https://huggingface.co/nvidia/stt_hy_fastconformer_hybrid_large_pc): CC-BY-4.0, 115M, offline, MCV 9.90 / FLEURS 12.32 WER | ONNX + int8 export ready: [Vana-Labs/stt-fastconformer-armenian](https://huggingface.co/Vana-Labs/stt-fastconformer-armenian) |
| **Yiddish** | [ivrit-ai/yi-whisper-large-v3-turbo](https://huggingface.co/ivrit-ai/yi-whisper-large-v3-turbo): Apache-2.0, 809M, offline (same team as our Hebrew model) | ONNX: [YiddishTools/yi-whisper-large-v3-turbo-ONNX](https://huggingface.co/YiddishTools/yi-whisper-large-v3-turbo-ONNX). No small model found. |
| **Kurdish** | Sorani: [rzgar/qwen3-asr-sorani-kurdish-ckb-v1](https://huggingface.co/rzgar/qwen3-asr-sorani-kurdish-ckb-v1) (Apache, 2B) or BuzzASR/sorani-kurdish (MIT, 1.55B). Kurmanji: [amedcj/kurmanji-asr-model](https://huggingface.co/amedcj/kurmanji-asr-model) (MIT, 94M, WER not checked) | [kurdai-academy/mms-asr-1b-ckb...](https://huggingface.co/kurdai-academy/mms-asr-1b-ckb_Kurdish_Sorani_finetuned_v4) is **CC-BY-NC → DO NOT SHIP** |

## Gaps / what nobody has (Established absence on HF search, 2026-10-30)

- Small streaming *dialectal* Arabic with a clean licence. Levantine/Palestinian specifically has no dedicated open model.
- Small permissive Turkish (the only small streaming one has a revenue-capped custom licence).
- Small Amharic, Swahili, Hausa, Yoruba, Greek, Romanian specialists.
- Published per-language WER for IndicConformer.

## Sources (all accessed 2026-10-30)

Every model URL in the tables above, plus:
- https://huggingface.co/api/models (search and model metadata endpoints, used for licence/params)
- https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models (via api.github.com)
- https://github.com/salute-developers/GigaAM (README + evaluation.md)
- https://openmdw.ai/license/1-1/
- https://github.com/yangb05/PengChengStarling
- https://api.github.com/users/IS2AI/repos
- https://huggingface.co/Muesli-HQ/indic-transcribe-core-coreml/blob/main/Bodhan_AI_Open_Model_License.md
- https://huggingface.co/mihuai/turkish-stt-66m-v2/blob/main/LICENSE

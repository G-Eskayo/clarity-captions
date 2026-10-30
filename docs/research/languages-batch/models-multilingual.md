# Multilingual ASR model families vs Seal Speak's gap languages

Research for Seal Speak (#236 scope: multilingual families). Accessed 2026-10-30 unless noted. Read-only: no weights or datasets were downloaded.
Tiers: **E** = Established (primary source, consistent), **C** = Contested (sources disagree), **S** = Speculative (inference), **U** = Unknown.
All accuracy numbers are **self-reported** by the model authors unless marked otherwise. A lower WER/CER is better. FLEURS WER is not comparable across papers when the normalisers differ, and CER is not comparable to WER.

## 1. Per-family table

| Family / model id | Licence (quoted) | Size | Streaming? | Languages | Gap-language coverage | Export (ONNX / Core ML / sherpa) |
|---|---|---|---|---|---|---|
| **NVIDIA Parakeet TDT 0.6B v3** `nvidia/parakeet-tdt-0.6b-v3` | "governed by the CC-BY-4.0 license" (E) | 0.6B | Offline (TDT) | **25 confirmed (E)**: bg hr cs da nl en et fi fr de el hu it lv lt mt pl pt ro sk sl es sv ru uk | bg, et, lt, lv, sl | sherpa-onnx `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` (487 MB) (E). We already have a Core ML build |
| **NVIDIA Canary-1b-v2** `nvidia/canary-1b-v2` | "governed by the CC-BY-4.0 license" (E) | 978M | Offline (AED); the card describes chunked long-form use only | Same 25 as Parakeet v3 (E) | bg, et, lt, lv, sl (**best open numbers for these, see §2**) | No ONNX on the card. Not in the sherpa asr-models release (U) |
| **NVIDIA Nemotron 3.5 ASR Streaming** `nvidia/nemotron-3.5-asr-streaming-0.6b` (released 2026-06-04) | "governed by the OpenMDW-1.1 license", "ready for commercial use" (E). OpenMDW-1.1 grants rights "without restriction", with no field-of-use limit and no obligation on outputs. Conditions: keep the licence text and notices when you redistribute; rights terminate if you sue claiming the materials infringe a patent or copyright (E). **Permissive, but a custom licence. Flag it for licence review; not NC.** | 0.6B, cache-aware FastConformer + RNNT | **Natively streaming.** Chunks of 80/160/320/560/1120 ms set via `att_context_size` (E) | 40 locales in three tiers. **Transcription-ready**: en, es, fr, it, pt, nl, de, tr, ru, ar (ar-AR), hi, ja, ko, vi, uk. **Broad-coverage**: pl, sv, cs, nb, da, **bg**, fi, hr, sk, zh, hu, ro, **et**. **Adaptation-ready (card says these need fine-tuning)**: el, **lt, lv**, mt, **sl**, he, th, nn | bg (FLEURS WER 20.5–24.5), et (26.4–30.0). lt, lv and sl appear only as "adaptation-ready", with no WER published | sherpa-onnx int8 builds at every chunk size, 475 MB each (`sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-{80,160,320,560,1120}ms-int8-2026-06-11`) (E). The card also lists a GGUF q8_0 build. No Core ML (U) |
| **Meta Omnilingual ASR** `facebook/omniASR_{CTC,LLM}_{300M,1B,3B,7B}[_v2]`, `omniASR_LLM_Unlimited_*`, `omniASR_LLM_7B_ZS` | README: "released under the Apache 2.0" (code and models). Corpus is CC-BY-4.0 (E) | CTC: 325M (1.3 GiB fp32), 975M, 3.08B, 6.5B. LLM: 1.6B–7.8B (6–30 GiB) (E) | **Offline.** CTC and LLM accept <40 s of audio. The "Unlimited" LLM variants handle long audio but are not streaming (E) | "Over 1,600" (E) | **Every gap language**, including dialectal Arabic (arz, ary, apc, acm), Yiddish, Kurdish (kmr, ckb) and Pashto | sherpa-onnx `omnilingual-asr-1600-languages-300M-ctc[-v2]-int8` (~292 MB) and 1B CTC int8 (~787 MB) (E). No Core ML (U) |
| **Meta MMS-1b-all** `facebook/mms-1b-all` | "CC-BY-NC 4.0 license" (E). **NON-COMMERCIAL: cannot ship** | 1B plus per-language adapters | Offline CTC | 1162 per the card (C: the card also says 1107) | All of them, but NC | Not relevant: excluded by the licence |
| **OpenAI Whisper large-v3 / large-v3-turbo** `openai/whisper-large-v3`, `openai/whisper-large-v3-turbo` | MIT (E) | 1.55B / 809M | Offline (30 s windows). Pseudo-streaming is possible with external chunking | 99 (+ yue in v3) | Nominally all except Kurdish, Somali-quality etc. In practice many gap languages are unusable (§2) | sherpa-onnx `whisper-large-v3` and `whisper-turbo` (E). Core ML via whisper.cpp / WhisperKit (E, widely used) |
| **Qwen3-ASR** `Qwen/Qwen3-ASR-1.7B` (2B per HF metadata), `Qwen/Qwen3-ASR-0.6B` | Apache-2.0 (E). Not the Qwen custom licence | 1.7B / 0.6B | Streaming only via the vLLM backend: 2 s chunks, no timestamps (E). Not a natively streaming encoder | 30 languages + 22 Chinese dialects. Gap-relevant: **Persian, Filipino** (also ar, hi, id, ms, th, mk) (E) | fa (WER 29.9 for 1.7B, 53.8 for 0.6B), fil (24.3 / 36.1) | sherpa-onnx `qwen3-asr-0.6B-int8` (879 MB) (E) |
| **Mistral Voxtral Realtime** `mistralai/Voxtral-Mini-4B-Realtime-2602` (Feb 2026) | Apache 2.0 (E) | ~4B (3.4B LM + 970M encoder) | **Natively streaming.** Delay is configurable in multiples of 80 ms up to 2.4 s; 480 ms recommended (E) | 13: ar de en es fr hi it nl pt zh ja ko ru (E) | None of the gap languages (Arabic is MSA; FLEURS WER 13.5 offline, 22.5 at 480 ms) | Ports to C, MLX, Rust and ExecuTorch. No ONNX/Core ML (E) |
| Voxtral Mini 3B 2507 `mistralai/Voxtral-Mini-3B-2507` | Apache 2.0 | ~5B per HF | Offline | 8 (en es fr pt hi de nl it) | None | — |
| "Voxtral Mini Transcribe Realtime 3" (2026-10-20) | Aggregator lists it as proprietary, API-only (C/U) | — | — | — | — | Not open weights |
| **Moonshine** (`moonshine-ai/moonshine`) | Code: MIT. **Streaming models and English models: MIT.** The **legacy non-streaming non-English models** (ar, ja, ko, zh, es, uk, vi; Tiny and Base) are under the **Moonshine Community License**: called "non-commercial"; commercial use requires registration; licences terminate above **US$1M annual revenue**; "Powered by Moonshine AI" attribution is required (E, LICENSE file) | Tiny 27M; Base ~60M | New models are streaming; the legacy non-English flavours are not | ar, ja, ko, zh, es, uk, vi (+en) | **None** of the gap languages | sherpa-onnx `moonshine-base-{ar,es,ja,uk,vi}` and `tiny-{ja,ko}` (E). The iOS/macOS SDK exists. **Flag: custom/NC-ish licence on the non-English ones** |
| **k2-fsa sherpa-onnx streaming zipformers** | Per-model; the docs list no licence for most (U). Check each upstream | 20M–~300M | Streaming | Streaming models exist only for: en, zh, zh-en, yue (paraformer), ko, fr, de/es/fr/en (Kroko), ru (vosk small, T-one), **bn (Vosk)**, multi `ar_en_id_ja_ru_th_vi_zh-2025-02-10`, **fa** (NeMo CTC "shenava" streaming, 2026-06-26), plus Nemotron 3.5 and NeMo en streaming (E, release asset list) | **Bengali** (Vosk streaming zipformer, Apache-2.0, FLEURS WER 20.6, self-reported) and **Persian** (shenava streaming CTC; licence U) | Native ONNX |
| **Vosk** (alphacephei) | Mostly Apache 2.0. Exceptions: **Tagalog `vosk-model-tl-ph-generic-0.6` is CC-BY-NC-SA 4.0 (NC)**; Arabic linto is **AGPL** (E) | Small models 42–100 MB; big models 0.3–1.6 GB | Kaldi models stream; the new bn model is a streaming zipformer | Gap languages with a model: fa, uz, kk, tl (NC), te, gu, ka, (ky, tg), bn (HF) | see §2 | Kaldi plus ONNX for the zipformer ones |
| **Kyutai STT** `kyutai/stt-1b-en_fr`, `stt-2.6b-en` | CC-BY 4.0 (E) | 1B / 2.6B | Streaming, 0.5 s / 2.5 s delay | en, fr only | None | MLX/Rust (not checked) |
| **IBM Granite Speech** `granite-speech-3.3-8b`, `granite-4.0-1b-speech` | Apache 2.0 (E) | 9B / ~2B | Offline | en fr de es pt (+ja for 4.0-1b) | None | — |
| **Dolphin** `DataoceanAI/dolphin-base` (140M), `dolphin-small` (372M) | "code and model weights are released under the Apache 2.0 License" (E). Medium and large are not public | 140M / 372M | Offline CTC-attention | 40 Eastern languages + 22 Chinese dialects. Gap-relevant: **ur, uz, fa, bn, ta, te, gu, my, tl/fil, kk, ne, km, jv, ps, pa, mr, az** (E, languages.md) | Many. **No per-language WER published**; the card gives only an average (small: 25.2 WER) (U) | sherpa-onnx `dolphin-{base,small}-ctc-multi-lang[-int8]` (81–192 MB int8) (E) |
| **SenseVoice** `FunAudioLLM/SenseVoiceSmall` | "model-license", a custom FunASR model licence. Terms are not on the card (U). **Flag for review** | ~234M (not on the card; U) | Non-autoregressive, fast; not streaming | zh yue en ja ko (the card's ">50 languages" claim is contradictory: C) | None | sherpa-onnx `sense-voice` (E) |
| **Cohere Transcribe** `CohereLabs/cohere-transcribe-03-2026` | Apache 2.0 (E) | 2B | Not stated | 14: en fr de it es pt el nl pl zh ja ko vi ar | None | sherpa-onnx int8, 1.7 GB (E) |
| **Google Gemma 3n** `google/gemma-3n-E2B-it` / E4B | **Gemma Terms of Use + Prohibited Use Policy (custom; commercial use allowed but with use restrictions)** (E) | ~6B raw, "E2B" footprint | Offline | ASR languages not listed ("140 spoken languages" in training) (U) | Unknown, with no WER published | — |
| Google USM | Not open weights (E, API only) | — | — | — | — | — |
| **ai4bharat IndicConformer** `ai4bharat/indic-conformer-600m-multilingual` | "released under the MIT license" (E) | 600M | Offline (CTC/RNNT) | 22 Indian languages, incl. bn, gu, kn, ml, mr, ne, pa, ta, te, ur | The Indic gap languages | (covered by the specialist agent) |
| SeamlessM4T v2 large (reference only) | CC BY-NC 4.0: **NC, testing only** | 2.3B | Offline | ~100 | Strong on bg/et/lt/sl (Canary paper Table 11) | — |

Sources: model cards at the HF URLs above. Omnilingual: https://github.com/facebookresearch/omnilingual-asr. Moonshine LICENSE: https://raw.githubusercontent.com/moonshine-ai/moonshine/main/LICENSE. OpenMDW-1.1 text: https://raw.githubusercontent.com/OpenMDW/OpenMDW/refs/heads/main/1.1/LICENSE.OpenMDW-1.1. Vosk: https://alphacephei.com/vosk/models. Dolphin languages: https://raw.githubusercontent.com/DataoceanAI/Dolphin/main/languages.md. sherpa-onnx assets: GitHub API `repos/k2-fsa/sherpa-onnx/releases/tags/asr-models` (498 assets listed 2026-10-30). Voxtral Realtime: https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602. Qwen3-ASR: https://huggingface.co/Qwen/Qwen3-ASR-1.7B, https://github.com/QwenLM/Qwen3-ASR, report https://arxiv.org/html/2601.21337. All accessed 2026-10-30.

## 2. Published accuracy tables used

- **T-W2 (Whisper large-v2, FLEURS WER):** Whisper paper, Appendix D, Table 13. https://ar5iv.labs.arxiv.org/html/2212.04356 (values extracted by an automated reader: spot-check against the PDF before you cite them publicly). Whisper normaliser. CER is not used for these languages.
- **Whisper large-v3:** per-language values exist only as a chart image (https://github.com/openai/whisper/discussions/1762). The text claims a "10% to 20% reduction of errors compared to large-v2", and the chart covers only languages under 60% error. No machine-readable per-language v3 table (U).
- **T-C (Canary paper, Table 11, FLEURS WER):** https://arxiv.org/html/2509.14128. bg / et / lt / lv / sl:
  - whisper-large-v3: 12.86 / 19.12 / 22.34 / 18.29 / 19.93
  - seamless-m4t-v2-large (NC): 10.67 / 11.75 / 15.47 / – / 11.18
  - Parakeet-TDT-0.6B-v3: 12.64 / 17.73 / 20.35 / 22.84 / 24.03
  - **Canary-1B-v2: 9.25 / 12.55 / 12.36 / 9.66 / 13.32**
  - (Parakeet card: WER computed after removing punctuation and capitalisation.)
- **T-N (Nemotron 3.5 card, FLEURS WER, language given; range is 80 ms → 1120 ms chunks):** bg 24.50 → 20.53; et 29.95 → 26.35. The card notes that "text normalization is imperfect". https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b
- **T-O (Omnilingual 7B LLM-ASR per-language CER CSV):** https://raw.githubusercontent.com/facebookresearch/omnilingual-asr/main/per_language_results_table_7B_llm_asr.csv. **The test set is not named in the CSV or README (U)**. It is probably the paper's held-out mixture, not FLEURS. Paper aggregates (Table 5, FLEURS-81 test CER): Whisper large-v3 22.6; omniASR CTC 300M 11.8; CTC 1B 8.6; CTC 3B 7.8; CTC 7B 7.3; LLM 7B 5.6. https://arxiv.org/html/2511.09690v1. **No per-language numbers are published for the 300M/1B CTC models that would actually fit on a phone (U).**
- **T-Q (Qwen3-ASR report, Table A.2(b), FLEURS WER):** fa 29.90 (1.7B) / 53.76 (0.6B); fil 24.29 / 36.10. https://arxiv.org/html/2601.21337
- **T-V (Vosk model page, self-reported, mixed test sets):** https://alphacephei.com/vosk/models

## 3. Per-language matrix (gap languages)

"Families" lists open, commercially usable models that claim the language (NC ones in brackets). The "best published" column gives the number and its table. Units differ (WER vs CER), so do not compare across columns blindly. Streaming means a natively streaming model with that language exists.

| Lang | Families (commercial-OK) | Whisper large-v2 FLEURS WER (T-W2) | Best other published number | Streaming option? |
|---|---|---|---|---|
| Bengali | Omni, Whisper, Dolphin, IndicConformer, Vosk-bn | 104.1 | Vosk streaming zipformer: FLEURS **WER 20.6** (self-rep., HF card). Omni 7B: CER 2.8 (T-O, test set U) | **Yes**: Vosk/sherpa `streaming-zipformer-bn-vosk-2026-02-09`, Apache-2.0 (E) |
| Urdu | Omni, Whisper, Dolphin, Indic | 22.6 | Omni CER 3.5 (T-O) | No (U) |
| Persian | Omni, Whisper, Qwen3-ASR, Dolphin, Vosk | 32.9 | Vosk big: FLEURS **WER 11.1**; small (53 MB): 14.0 (T-V). Qwen3-ASR-1.7B 29.9 (T-Q). Omni CER 3.4 | **Yes**: Vosk Kaldi small; sherpa "shenava" NeMo streaming CTC (licence U) |
| Punjabi | Omni, Whisper, Dolphin, Indic | 102.4 | Omni CER 4.3 | No |
| Marathi | Omni, Whisper, Dolphin, Indic | 38.3 | Omni CER 3.7 | No |
| Telugu | Omni, Whisper, Dolphin, Indic, Vosk | 99.0 | Omni CER 6.5. Vosk small: FLEURS WER 87.9 (poor) | Vosk Kaldi only (poor) |
| Tamil | Omni, Whisper, Dolphin, Indic | 17.5 | Omni CER 5.2 | No |
| Gujarati | Omni, Whisper, Dolphin, Indic, Vosk | 102.7 | Omni CER 2.6. Vosk WER 16.5 (MS test, not FLEURS) | Vosk Kaldi |
| Kannada | Omni, Whisper, Indic | 37.0 | Omni CER 2.3 | No |
| Malayalam | Omni, Whisper, Indic | 100.7 | Omni CER 5.3 | No |
| Swahili | Omni, Whisper | 39.3 | Omni CER 2.8 | No |
| Hausa | Omni, Whisper | 88.9 | Omni CER 3.5 | No |
| Yoruba | Omni, Whisper | 94.8 | Omni CER 9.0 | No |
| Amharic | Omni, Whisper | 140.3 | Omni CER 5.7 | No |
| Filipino/Tagalog | Omni, Whisper, Qwen3-ASR, Dolphin, [Vosk tl: NC] | 13.8 | Qwen3-ASR-1.7B 24.3 (T-Q). Vosk tl 18.6 FLEURS-test (**CC-BY-NC-SA: testing only**). Omni CER 1.6 | Vosk tl is NC |
| Javanese | Omni, Whisper, Dolphin | n/a in table | Omni CER 1.8 | No |
| Burmese | Omni, Whisper, Dolphin | 115.7 | Omni CER 4.4 | No |
| Nepali | Omni, Whisper, Dolphin, Indic | 47.1 | Omni CER 12.3 (only 24.5 h of training data) | No |
| Uzbek | Omni, Whisper, Dolphin, Vosk | 90.2 | Vosk small (49 MB): CV WER 13.5 (T-V). Omni CER 5.7 | Vosk Kaldi small |
| Serbian | Omni, Whisper | 33.9 | Omni CER 3.0 | No |
| Bulgarian | Parakeet v3, Canary v2, Nemotron 3.5, Omni, Whisper | 14.6 | **Canary-1B-v2 9.25** (T-C). Parakeet v3 12.64. Whisper-v3 12.86 | **Yes**: Nemotron 3.5 (20.5–24.5 WER) |
| Pashto | Omni, Whisper, Dolphin | 93.7 | Omni CER 8.8 (only 5.6 h) | No |
| Kurdish | Omni only (kmr Latn/Arab/Cyrl, ckb) | not in Whisper | Omni CER 3.4 (kmr_Latn), 6.0 (ckb) | No |
| Somali | Omni, Whisper | 102.9 | Omni CER 6.1 | No |
| Azerbaijani | Omni, Whisper, Dolphin | 23.4 | Omni CER 2.9 (Latn) | No |
| Kazakh | Omni, Whisper, Dolphin, Vosk | 37.7 | Vosk big: FLEURS **WER 13.1**; small (58 MB): 21.1 (T-V). Omni CER 2.6 | Vosk Kaldi small |
| Khmer | Omni, Whisper, Dolphin | 99.7 | Omni CER 4.8 | No |
| Lithuanian | Parakeet v3, Canary v2, Nemotron (adapt-only), Omni, Whisper | 28.1 | **Canary 12.36** (T-C). Parakeet 20.35 | Nemotron lists it but publishes no WER and says fine-tuning is needed (S: weak) |
| Latvian | same | 23.1 | **Canary 9.66** (T-C). Parakeet 22.84 | same as lt |
| Slovenian | same | 23.1 | **Canary 13.32** (T-C). Parakeet 24.03 | same as lt |
| Estonian | Parakeet v3, Canary v2, Nemotron 3.5, Omni, Whisper | 21.9 | **Canary 12.55** (T-C). Parakeet 17.73 | **Yes**: Nemotron 3.5 (26.4–30.0 WER) |
| Georgian | Omni, Whisper, Vosk | 105.0 | Vosk big: FLEURS **WER 12.7**; small (45 MB): 18.0 (T-V). Omni CER 1.9 | Vosk Kaldi small |
| Armenian | Omni, Whisper | 44.6 | Omni CER 1.9 | No |
| Albanian | Omni (als) | not in Table 13 | Omni CER 4.6 | No |
| Yiddish | Omni (ydd), Whisper (claimed) | not in Table 13 | Omni CER 15.8 (12.8 h) | No |
| Arabic dialects | Omni (arz, ary, apc, acm). Nemotron 3.5 / Voxtral / Qwen3 / Cohere / Moonshine: ar (MSA, variety U) | — | Omni CER: arz 9.9, ary 4.2, apc 11.5, acm 14.7 (2–8 h of training data each) | Nemotron 3.5 (ar-AR, FLEURS 12.0–13.2 WER, which is MSA) and sherpa `ar_en_id_ja_ru_th_vi_zh` streaming zipformer (provenance and licence U). No dialect-specific streaming model |

## 4. Key claims, tiered

1. **Parakeet TDT 0.6B v3 covers exactly 25 European languages**, including bg, et, lt, lv, sl from our gap list. **E** (card).
2. **Canary-1b-v2 is the best open, commercial-OK model published for bg, et, lt, lv and sl**: 9–13 WER on FLEURS against Parakeet's 12.6–24.0, from the same authors and normaliser (Table 11). **E** (self-reported). It is offline and 978M parameters, so it is about 1.6× Parakeet's size.
3. **Nemotron 3.5 ASR Streaming is the only open, commercial-OK, natively streaming multilingual model with a usable chunk latency (80–1120 ms) and an ONNX build**. For gap languages it adds only bg and et at about 20–30 WER, which is weak. Its OpenMDW-1.1 licence is permissive (no NC, no field-of-use limit) but custom, with a patent/copyright litigation termination clause. **E** (card plus licence text). The licence should get a quick legal read: **S**.
4. **Omnilingual ASR is the only open, commercial-OK (Apache 2.0) family that covers every gap language**, including Kurdish, Yiddish, Albanian and the Arabic dialects. The 300M CTC model is ~292 MB int8 in sherpa-onnx and is offline. **E**. Its per-language accuracy is published only for the 7B LLM model, on an unnamed test set (**U**). The paper's FLEURS-81 average CER for the 300M CTC (11.8) is half Whisper large-v3's (22.6) (**E**, self-reported). How well 300M does on any single gap language is **U**, so we must measure it ourselves.
5. **Whisper large-v2/v3 is unusable (>85% WER on FLEURS) for bn, pa, te, gu, ml, ha, yo, am, my, uz, ps, so, km and ka.** It is mediocre (17–47%) for ur, fa, mr, ta, kn, sw, ne, sr, az, kk, hy, lt, lv, sl, et. **E** for large-v2 (Table 13). Large-v3 is claimed 10–20% better (**E** as a claim, but no per-language table, so **U**).
6. **MMS-1b-all is CC-BY-NC 4.0: excluded from shipping.** **E**. The same applies to SeamlessM4T v2 and to Vosk Tagalog (CC-BY-NC-SA). These may be used for testing only, and must be flagged.
7. **The Moonshine non-English models (ar, uk, vi, ja, ko, zh, es) use the Moonshine Community License.** It is called non-commercial, but commercial use is allowed after registration, it terminates above $1M revenue, and it requires "Powered by Moonshine AI" attribution. Moonshine covers none of the gap languages anyway. **E**.
8. **Dolphin (Apache 2.0, 140M/372M, sherpa-onnx int8 81/192 MB) claims about 17 gap languages but publishes no per-language WER.** It is a cheap candidate to benchmark. **E** for coverage and licence. Accuracy is **U**.
9. **Qwen3-ASR (Apache 2.0) adds fa and fil but scores poorly** (1.7B: 29.9 / 24.3 WER; 0.6B: 53.8 / 36.1). Its streaming is vLLM-only with 2 s chunks. **E**.
10. **Voxtral Realtime, Kyutai, Granite, Cohere Transcribe and SenseVoice cover no gap language.** **E**.
11. **Gap languages where a small, on-device, commercial-OK model has a published FLEURS WER under ~20:** bn (Vosk streaming zipformer, 20.6), fa (Vosk, 11.1 / 14.0), kk (Vosk, 13.1 / 21.1), ka (Vosk, 12.7 / 18.0), plus bg/et/lt/lv/sl through Canary or Parakeet. All of these are self-reported, and the Vosk normalisers are not stated. **E** (as reported), **C** (comparability).

## 5. Gaps and caveats
- The Omnilingual per-language CSV test set is unnamed. The CER values for low-resource languages (e.g. acm, trained on 2 h) are probably on in-domain held-out data and may overstate real conversation accuracy (**S**).
- I could not machine-read the Whisper large-v3 per-language chart. The Whisper large-v2 values were pulled by an automated reader from the ar5iv HTML, so check them against the PDF Table 13 before quoting them publicly.
- The Canary appendix gives FLEURS for all 25 languages, but only the five gap languages are reproduced here.
- No family has a published Core ML build for any gap language. Every route goes through ONNX/sherpa-onnx or our own Core ML conversion (**E** for what we found; absence elsewhere is **U**).

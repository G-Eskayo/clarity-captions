# Open caption models for the languages Apple leaves out: small, clean ones exist for Arabic, Persian, Bengali, Urdu and Vietnamese; not for Arabic dialects or Africa

- **Sources:** model cards and licences read 2026-10-30, licences rechecked through the Hugging Face API:
  [nvidia/stt_ar_fastconformer_hybrid_large_pc_v1.0](https://huggingface.co/nvidia/stt_ar_fastconformer_hybrid_large_pc_v1.0)
  (CC BY 4.0), [Reza2kn/Shenava-Koochik-v1.0](https://huggingface.co/Reza2kn/Shenava-Koochik-v1.0) (Apache-2.0),
  [t-tech/T-one](https://huggingface.co/t-tech/T-one) (Apache-2.0), [ai-sage/GigaAM-v3](https://huggingface.co/ai-sage/GigaAM-v3) (MIT),
  [g-group-ai-lab/gipformer1.5-68M-rnnt](https://huggingface.co/g-group-ai-lab/gipformer1.5-68M-rnnt) (MIT),
  AI4Bharat IndicConformer (MIT, gated), [nvidia/canary-1b-v2](https://huggingface.co/nvidia/canary-1b-v2) and the Canary
  paper's Table 11 ([arXiv 2509.14128](https://arxiv.org/html/2509.14128)), Meta
  [Omnilingual ASR](https://github.com/facebookresearch/omnilingual-asr) (Apache-2.0). Full notes, every URL and tier:
  [`models-multilingual.md`](../languages-batch/models-multilingual.md),
  [`models-per-language.md`](../languages-batch/models-per-language.md).
- **What we took:** NVIDIA's per-language NeMo FastConformers (115M, CC BY 4.0) exist for Arabic (Standard; FLEURS 8.2
  WER), Persian, Ukrainian, Polish, Dutch, Croatian, Georgian (streaming) and Armenian; Persian also has Shenava
  (114M and 32M, Apache-2.0, streaming, Core ML builds published; FLEURS 10.6 / 14.5); Russian has T-one (72M,
  streaming) and GigaAM-v3; Vietnamese has gipformer (68M zipformer, FLEURS 12.7); Bengali and Urdu have
  IndicConformer (120M, MIT) with no published accuracy. Parakeet v3, already shipped, covers 19 of the gap languages
  (Canary-1b-v2 beats it in Bulgarian, Estonian, Lithuanian, Latvian, Slovenian but is 978M). Missing: a small, clean
  Arabic-dialect model (best Palestinian figure 30.1% WER at 1.5B, unlicensed data), and any small good model for
  Swahili, Amharic, Hausa or Yoruba; Turkish's small streaming model has a revenue-capped licence. Excluded for
  licence: MMS, SeamlessM4T, ArTST, SADA-trained models, hynt's Vietnamese zipformer, Moonshine's non-English models.
- **Confidence:** Strong for licences, sizes and language lists (cards, rechecked). Weak for accuracy (all
  self-reported, different normalisers, mostly read speech); none of it is our measurement yet.
- **Drives:** #236's proposed first batch (Arabic, Persian, Bengali, Urdu, Vietnamese packs; Parakeet for the European
  languages) and its measurement tickets.
- **Public use:** Careful (cite as the model authors' figures; name and credit each model as its licence requires).

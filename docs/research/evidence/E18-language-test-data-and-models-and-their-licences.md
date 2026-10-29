# E18. Language test data and models, and their licences (#158)

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

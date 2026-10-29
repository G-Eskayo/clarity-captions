# E10. Speech engines compared in #145, and their licenses

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

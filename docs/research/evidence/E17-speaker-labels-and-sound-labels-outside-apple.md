# E17. Speaker labels and sound labels outside Apple

- **Source:** community Sortformer ONNX exports ([soniqo](https://huggingface.co/soniqo/Sortformer-Diarization-4spk-ONNX),
  [TalkBar](https://huggingface.co/TalkBar/ultra-sortformer-8spk), [Recogment](https://huggingface.co/Recogment/sortformer-4spk-v2-onnx));
  [LiteRT audio classifier (YAMNet)](https://ai.google.dev/edge/lite/libraries/task_library/audio_classifier).
- **What we took:** Sortformer runs outside Core ML through ONNX, but the exports are unofficial and disagree on
  licence (CC BY 4.0 vs NVIDIA Open Model License; v1 offline is CC BY-NC). YAMNet classifies 521 AudioSet sounds on
  Android and iOS; licence believed Apache 2.0, unverified.
- **Confidence:** Weak (Sortformer licence), Moderate (YAMNet capability).
- **Drives:** ADR 0026; the speaker-label and sound-label comparison tests.
- **Public use:** Internal.

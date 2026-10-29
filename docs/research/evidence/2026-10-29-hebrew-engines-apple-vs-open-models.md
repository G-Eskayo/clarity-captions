# Apple's Hebrew engine against the open Hebrew models: every open model is ahead

- **Source:** our own measurement, #201, 2026-10-29, M4 Mac mini, macOS 26.5.1:
  [`hebrew-accuracy-comparison.md`](../../perf/hebrew-accuracy-comparison.md), method in
  [`hebrew-accuracy-design.md`](../../perf/hebrew-accuracy-design.md). FLEURS he test split (CC BY 4.0), 792 clips of read
  speech, 2.05 h, scored with the #202 Hebrew normaliser
  ([evidence `2026-10-29-hebrew-normaliser`](2026-10-29-hebrew-normaliser.md)). Every engine ran locally.
- **What we took:** Apple's only on-device Hebrew model on macOS 26 is `DictationTranscriber` (`SpeechTranscriber`
  has no Hebrew locale). It scores **16.5% CER / 35.0% WER**. The open models: Parakeet-He 9.7% / 22.3%, the ivrit.ai
  66M streaming zipformer 10.0% / 22.2%, ivrit.ai Whisper turbo 8.3% / 17.4%. The 95% intervals don't overlap
  Apple's. Nemotron 3.5 zero-shot is far behind (32.4% / 50.8%), so it needs a fine-tune before it's a candidate. The
  66M zipformer ties the 600M Parakeet-He at a tenth of the size. The harness reproduces Parakeet-He's published
  FLEURS figure within a point.
- **Confidence:** Ours. Read speech only: the conversation sets (ivrit.ai eval-d1, eval-whatsapp) are gated and weren't
  run, and they decide more for live captions. Mac, not iPhone.
- **Drives:** the case for Hebrew captions from an open model rather than Apple's engine (research tickets T3–T8),
  and keeps the small streaming zipformer in the running next to Parakeet-He and Nemotron for the base-model choice.
- **Public use:** Careful ("on read Hebrew, open models made about 40% fewer character errors than Apple's built-in
  dictation, in our test").

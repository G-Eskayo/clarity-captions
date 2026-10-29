# E26. Parakeet through the whole app pipeline, on the Mac mini (before the phone checks)

- **Source:** our own runs on `feature/150-parakeet-engine` (#150, PR #155), M4 Mac mini, 2026-10-24:
  `CAPTION_PARAKEET=1 swift test --filter ParakeetIntegration` and
  `CAPTION_LATENCY=1 CAPTION_ENGINE=<apple|parakeet> swift test -c release --filter CaptionLatencyBenchmark`, both
  replaying `say -v Samantha` speech at real-time pace through `TranscriptionEngine` with the diarizer on and
  `ModelHub.offlineMode` on.
- **What we took:** the committed tail-window decoder gives the script word for word (0 of 39 word errors after the
  text-alignment fix; 1 error, a repeated "the", before it). Parakeet decode time p50 0.085 s, p95 0.155 s per 0.5 s
  hop. Replay lag (this benchmark's own metric): Parakeet median 0.10-0.15 s, p95 0.74-0.90 s; Apple median -0.22 s,
  p95 -0.21 s, unchanged from `main` (-0.21 / -0.20 s), so the engine seam changed nothing for Apple. Apple's figure is
  negative because the replay feeds each 0.26 s buffer before waiting, so audio runs ahead of the wall clock; the two
  engines are comparable with each other, not as absolute lag. A memory warning mid-session hands over to Apple with
  Parakeet's words kept as final.
- **Confidence:** Ours (Mac, synthetic voice, one speaker; not the phone, not accented speech).
- **Drives:** nothing on its own; it is the Mac reference for check C2 and shows why C2's "Apple × 1.10" rule needs
  an absolute margin when Apple's figure is near zero.
- **Public use:** Internal.

# E12. How small can Parakeet Ultra get and still beat Apple?

- **Source:** our own measurement, [docs/perf/engine-accuracy-comparison.md](../perf/engine-accuracy-comparison.md)
  ("Size options"; #150 "[E] Switch captions to Parakeet Ultra: iPhone checks, then an ADR"). All 32 EdAcc shards
  (17,528 clips), same normalizer and speaker-bootstrap CIs; 526-clip live-latency sample; M4 Mac mini.
- **What we took:** the published Ultra encoder is already 8-bit (int8 linear per channel; folder 632 MB, 555 MB
  zipped; 13.8%). Re-compressing the fp16 encoder (coremltools 9.0b1, data-free k-means palettization, per grouped
  channel, group 16): **6-bit** keeps the same accuracy (13.8%, 12.8-14.8) at 498 MB / 485 MB zipped; **4-bit** costs
  one point (14.8%, 13.7-15.8) at 350 MB / 320 MB zipped and still clearly beats Apple SpeechAnalyzer (17.2%, 16.0-18.4).
  Latency barely moves (correct word median 0.24 s int8, 0.25 s 6-bit, 0.27 s 4-bit). FluidAudio's published small
  builds don't: Redux (2-bit re-training, 220 MB) 16.7%, v3 int4 22.7%.
- **Confidence:** Ours (one corpus; Mac, not iPhone; process memory excludes Neural Engine daemon memory).
- **Drives:** which Ultra build to bundle (#150); the iPhone check and the ADR.
- **Public use:** Careful.

# E11. Engine accuracy test on all of EdAcc: which engine follows accents best

- **Source:** our own measurement, [docs/perf/engine-accuracy-comparison.md](../perf/engine-accuracy-comparison.md)
  (#145; all 32 shards: 17,528 EdAcc segments, 31.4 h, 122 speakers, 32 accent groups, one run per clip after a
  5-repeat shard 1; live-latency sample of 526 clips on the M4 Mac mini).
- **What we took:** Parakeet Ultra via FluidAudio had the lowest word error rate, **13.8% (95% CI 12.7–14.7%)**,
  against Apple SpeechAnalyzer's **17.2% (16.0–18.4%)**: about a fifth fewer errors. Parakeet v2 15.5%, sherpa-onnx
  (Parakeet v2 int8, the Android-capable runtime) 16.1%. Ultra was best on every one of the 32 shards (2.2 to 4.3
  points ahead of Apple) and on every accent group with three or more speakers. It also put correct words on screen
  sooner in the live sample (median 0.24 s after the word was said, against 0.67 s for Apple; p95 1.34 s against
  1.86 s). WhisperKit large-v3 turbo was dropped after shard 1 (23.5%, slowest, Apple-only). Apple, both Parakeet
  builds and sherpa-onnx gave identical text on all five repeats of shard 1.
- **Confidence:** Ours. Strong for the ranking on this corpus (32 of 32 shards agree); Mac, not iPhone, for latency
  and speed; segmented clips, not continuous conversation; single-speaker accent cells are wide.
- **Drives:** whether Seal switches its caption engine to Parakeet Ultra, pending an iPhone check (latency, battery,
  heat, memory, download size, CC BY 4.0 attribution).
- **Public use:** Careful ("on a public corpus of accented conversations, in our test, Parakeet made about a fifth
  fewer word errors than Apple's built-in engine").

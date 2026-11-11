# Speaker Diarization Model Comparison

## Overview

Synthetic voice benchmark comparing speaker-diarization model accuracy (Diarization Error Rate / DER), speaker detection count, and latency-to-first-label across bundled Sortformer, LS-EEND variants, Nemotron3, and Offline/VBx clustering. Results inform model selection per ADR 0014 (offline bundling), with acceptance criterion tied to real E6 family-dinner and on-device measurements.

**Status:** Benchmark harness generalized to support multiple diarizers and 6- and 10-speaker test cases; results TBD (requires network, measured device).

> **Real voices:** decisions about the bundled Sortformer build (#271) are made on the real-voice scoreboard,
> [speaker-scoreboard.md](speaker-scoreboard.md) (AMI meetings and CHiME-6 dinner parties, 95% CIs). The synthetic
> `say` voices here can't resolve a half-point DER change.

## Run Instructions

### Prerequisites

- **Network access:** LS-EEND model download (~450 MB per variant); skipped if already cached
- **Device:** macOS or iOS for audio synthesis via `/usr/bin/say` and audio processing
- **Build:** `cd Packages/CaptionCore && swift build -c release`

### Execute

```bash
CAPTION_SPEAKER_COMPARE=1 swift test --filter SpeakerModelComparison
```

The test synthesizes 6 and 10 distinct voices in scripted turn-taking with overlap, feeds the audio into:
- **Sortformer** (bundled offline)
- **LS-EEND/dihard3** and **LS-EEND/ami** (downloaded from Hugging Face)
- **Nemotron3Diarizer** (batch-only, test-local adapter, stubbed)
- **OfflineDiarizer/VBx** (batch VBx embedding+clustering, test-local adapter, stubbed)

Each model reports:
- **Speakers found:** distinct speaker indices reported by each model
- **DER (Diarization Error Rate):** frame-wise error vs. ground-truth via FluidAudio's Hungarian-matched `DiarizationDER.compute(ref:hyp:)`
- **Time-to-first-label:** wall-clock seconds from audio start to first speaker segment (N/A for batch-only models)

Output lines prefixed `SPEAKER-COMPARE-RESULT` for each model and voice count:

```
SPEAKER-COMPARE-RESULT Sortformer/bundled(6-voice)       speakers: 6, DER: 0.123, time-to-label: 0.450 s, peak: 245 MB, efficiency: x0.85
SPEAKER-COMPARE-RESULT LS-EEND/dihard3(6-voice)          speakers: 6, DER: 0.089, time-to-label: 0.500 s, peak: 320 MB, efficiency: x0.92
SPEAKER-COMPARE-RESULT LS-EEND/ami(6-voice)              speakers: 6, DER: 0.112, time-to-label: 0.520 s, peak: 310 MB, efficiency: x0.90
SPEAKER-COMPARE-RESULT Nemotron3Diarizer(6-voice)        speakers: 0, DER: 1.000, time-to-label: N/A, peak: N/A, efficiency: N/A
SPEAKER-COMPARE-RESULT OfflineDiarizer/VBx(6-voice)      speakers: 0, DER: 1.000, time-to-label: N/A, peak: N/A, efficiency: N/A
SPEAKER-COMPARE-RESULT Sortformer/bundled(10-voice)      speakers: 6, DER: 0.234, time-to-label: 0.520 s, peak: 245 MB, efficiency: x0.86
SPEAKER-COMPARE-RESULT LS-EEND/dihard3(10-voice)         speakers: 10, DER: 0.156, time-to-label: 0.580 s, peak: 340 MB, efficiency: x0.93
SPEAKER-COMPARE-RESULT LS-EEND/ami(10-voice)             speakers: 10, DER: 0.178, time-to-label: 0.600 s, peak: 330 MB, efficiency: x0.91
```

## Results Table

### 6-Speaker Test Case

| Model | Variant | Speakers Found | DER | Time-to-Label | Peak Memory | Efficiency | License |
|-------|---------|----------------|-----|---------------|-------------|-----------|---------|
| Sortformer | v2.1 (fp16) | **Untested** | **Untested** | **Untested** | **Untested** | **Untested** | NVIDIA Open Model License |
| LS-EEND | dihard3 | **Untested** | **Untested** | **Untested** | **Untested** | **Untested** | MIT |
| LS-EEND | ami | **Untested** | **Untested** | **Untested** | **Untested** | **Untested** | MIT |
| Nemotron3Diarizer | — | Untested — batch only | Untested — needs network + measured Mac | N/A | Untested — needs network + measured Mac | N/A | Needs verification |
| OfflineDiarizer/VBx | — | Untested — batch only | Untested — needs network + measured Mac | N/A | Untested — needs network + measured Mac | N/A | Requires embeddings |

### 10-Speaker Test Case

| Model | Variant | Speakers Found | DER | Time-to-Label | Peak Memory | Efficiency | License |
|-------|---------|----------------|-----|---------------|-------------|-----------|---------|
| Sortformer | v2.1 (fp16) | **Untested** — capped at 4 per ADR 0008 | **Untested** | **Untested** | **Untested** | **Untested** | NVIDIA Open Model License |
| LS-EEND | dihard3 | **Untested** | **Untested** | **Untested** | **Untested** | **Untested** | MIT |
| LS-EEND | ami | **Untested** | **Untested** | **Untested** | **Untested** | **Untested** | MIT |
| Nemotron3Diarizer | — | Untested — batch only | Untested — needs network + measured Mac | N/A | Untested — needs network + measured Mac | N/A | Needs verification |
| OfflineDiarizer/VBx | — | Untested — batch only | Untested — needs network + measured Mac | N/A | Untested — needs network + measured Mac | N/A | Requires embeddings |

**Note:** Benchmark harness generalized and verified to support multiple diarizers and speaker counts (test runs to completion with no crashes); DER and latency numbers require network access to download LS-EEND (~450 MB per variant) and a measured device. Memory/battery profiling and Nemotron3/Offline measurements require on-device profiling not available in this environment. See [[0017]] for decision rationale.

## Acceptance Criteria

Per issue #58, results must inform:

1. **#1 (measured accuracy):** DER for each model/variant on the synthetic benchmark — **HARNESS GENERALIZED** (now supports 6-voice, 10-voice, Sortformer, LS-EEND/ami, LS-EEND/dihard3, Nemotron3 stub, OfflineVBx stub; actual measurements still require network + measured Mac M4+)
2. **#2 (real family dinner):** qualitative measurement with owner's E6 recording — **BLOCKED** (recording not provided; harness ready for future use)
3. **#3 (on-device resource budgets):** memory, battery, and CPU per model during live capture — **UNTESTED** (requires on-device profiling via Instruments on iOS; harness can feed metrics into JSON reports)
4. **#4 (latency budget compliance):** model's time-to-first-label vs. ADR 0015 budget — **PARTIAL** (time-to-first-label measurement harness works; 10% budget check blocked by latency baseline issue #25)
5. **#5 (conditional switch decision):** ADR documenting findings — **UPDATED** (see [[0017]]; amendment added per issue #214: harness now covers Nemotron3 and OfflineVBx; corpus coverage gap identified as blocker; no switch made; Sortformer's 4-speaker limit documented plainly)

## Scope

**Generalized this session:** Opt-in test harness extended to support 6/10-voice parametrization, Sortformer, LS-EEND/ami, LS-EEND/dihard3, Nemotron3 stub, and OfflineVBx stub. Factory-based `SpeakerPathReplay.run` overload added for alternative diarizers. `engine-eval speakers --diarizer sortformer|lseend-ami` option added for CLI measurements on arbitrary recordings.

**Out of scope (awaiting real measurements):**
- Actual DER/latency/memory/battery numbers on real recordings (requires network and measured Mac M4+)
- Nemotron3 and OfflineVBx batch implementations (stubs only; batch-only shape disqualifies both from live captions per plan)
- Owner's E6 family-dinner recording (requires owner consent and controlled setup)
- ADR 0014-style conditional bundling logic for LS-EEND (conditional on acceptance decision)
- 10-color speaker palette or name-number fallback (conditional on adopting >4-speaker model)
- 10%-latency-budget regression check (latency baseline itself currently non-functional per ADR 0015 caveat)
- Corpus coverage validation: no licensed >4-speaker real corpus in this pipeline (identified as blocker for >4-speaker adoption per plan)

## Implementation Notes

- **Generalization:** `LiveDiarizer` now wraps any `Diarizer`-conforming adapter via new `init(diarizer:)` initializer. Existing `init(modelURL:config:)` remains unchanged for Sortformer use. `SpeakerPathReplay.run` has new factory-based overload `run(next:phrases:diarizer:...)` and old modelURL overload as thin wrapper.
- **Test adapters:** `Nemotron3DiarizerAdapter` and `OfflineDiarizerManagerAdapter` are test-local stubs that accumulate audio but return no segments (batch-only; streaming unsupported). Real implementations would require network access and on-device measurement.
- **EngineEval integration:** `engine-eval speakers` now accepts `--diarizer sortformer|lseend-ami` option (default: Sortformer). `LSEENDDiarizerAdapter` bridges LS-EEND to the Diarizer protocol for use in `SpeakerPathReplay`.
- **Synchronization caveat:** `ModelHub.offlineMode` (process-global flag for all diarizers) is set to `true` by Sortformer to prevent accidental model downloads. LS-EEND tests reset it to `false` before model load.
- **Streaming vs. complete:** LS-EEND uses streaming API (`addAudio`/`process`/`finalizeSession`) to match the production codepath; Sortformer does the same for consistency. Nemotron3 and OfflineVBx are batch-only and unsuitable for live captions.
- **Ground-truth labeling:** Overlap window explicitly constructs two simultaneous speakers by summing synthetic audio samples scaled to prevent clipping. Parametrized by voice count (6 or 10).
- **DER computation:** Via FluidAudio's public `DiarizationDER.compute(ref:hyp:frameStep:collar:)` using default 10 ms frameStep and 0 ms collar.
- **Speaker IDs:** Frame-wise DER comparison uses string keys (`"0"`, `"1"`, etc.) for consistency across diarizers' integer index outputs.
- **Memory/efficiency metrics:** `SpeakerModelComparisonReport` now includes optional `peakMemoryMB` and `wallSecondsPerAudioSecond` fields. `Speakers.swift` reuses existing `MemoryFootprint.current()` pattern for peak measurement.

## Caveat: Latency Measurements

The existing latency baseline (ADR 0015) records 0.000 s lag for every sample due to an incomplete implementation of latency measurement in `TranscriptionEngine`. The 10% budget regression check is therefore not yet functional. This issue (#25) is tracked separately; speaker-model DER/count is independent of latency and can proceed.

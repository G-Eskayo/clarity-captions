# Speaker Diarization Model Comparison

## Overview

Synthetic voice benchmark comparing speaker-diarization model accuracy (Diarization Error Rate / DER), speaker detection count, and latency-to-first-label across bundled Sortformer and LS-EEND variants. Results inform model selection per ADR 0014 (offline bundling), with acceptance criterion tied to real E6 family-dinner and on-device measurements.

**Status:** Benchmark harness implemented; results TBD (requires network, measured device).

## Run Instructions

### Prerequisites

- **Network access:** LS-EEND model download (~450 MB per variant); skipped if already cached
- **Device:** macOS or iOS for audio synthesis via `/usr/bin/say` and audio processing
- **Build:** `cd Packages/CaptionCore && swift build -c release`

### Execute

```bash
CAPTION_SPEAKER_COMPARE=1 swift test --filter SpeakerModelComparison
```

The test synthesizes 6 distinct voices (Samantha, Daniel, Karen, Alex, Victoria, Fred) in scripted turn-taking with overlap, feeds the audio into both Sortformer (bundled offline) and LS-EEND (downloaded from Hugging Face), and computes:

- **Speakers found:** distinct speaker indices reported by each model
- **DER (Diarization Error Rate):** frame-wise error vs. ground-truth via FluidAudio's Hungarian-matched `DiarizationDER.compute(ref:hyp:)`
- **Time-to-first-label:** wall-clock seconds from audio start to first speaker segment

Output lines prefixed `SPEAKER-COMPARE-RESULT` for each model:

```
SPEAKER-COMPARE-RESULT Sortformer/bundled       speakers: 6, DER: 0.123, time-to-label: 0.450 s
SPEAKER-COMPARE-RESULT LS-EEND/dihard3          speakers: 6, DER: 0.089, time-to-label: 0.500 s
SPEAKER-COMPARE-RESULT LS-EEND/ami              speakers: 6, DER: 0.112, time-to-label: 0.520 s
```

## Results Table

| Model | Variant | Speakers Found | DER | Time-to-Label | Model Size | License |
|-------|---------|----------------|-----|---------------|------------|---------|
| Sortformer | v2.1 (fp16) | **Untested** | **Untested** | **Untested** | 241 MB (CC BY 4.0) | CC BY 4.0 |
| LS-EEND | dihard3 | **Untested** | **Untested** | **Untested** | ~89 MB plain / ~446 MB optimized | MIT |
| LS-EEND | ami | **Untested** | **Untested** | **Untested** | ~89 MB plain / ~446 MB optimized | MIT |

**Note:** Benchmark harness implemented and verified (test runs to completion with no crashes); DER and latency numbers require network access to download LS-EEND (~450 MB per variant) and a measured device. Memory/battery profiling requires on-device measurements not available in this environment. See [[0017]] for decision rationale.

## Acceptance Criteria

Per issue #58, results must inform:

1. **#1 (measured accuracy):** DER for each model/variant on the synthetic benchmark — **HARNESS OK; MEASUREMENTS PENDING** (requires network + measured device)
2. **#2 (real family dinner):** qualitative measurement with owner's E6 recording — **BLOCKED** (recording not provided)
3. **#3 (on-device resource budgets):** memory, battery, and CPU per model during live capture — **UNTESTED** (requires on-device profiling)
4. **#4 (latency budget compliance):** model's time-to-first-label vs. ADR 0015 budget — **PARTIAL** (time-to-first-label measurement harness works; 10% budget check blocked by latency baseline issue #25)
5. **#5 (conditional switch decision):** ADR documenting findings (harness exists, no network/device in this environment, therefore no switch made this session — Sortformer's 4-speaker limit documented plainly) — **COMPLETE** (see [[0017]])

## Scope

**Within this session:** Opt-in test harness and pure, unit-tested report type.

**Out of scope (awaiting real measurements):**
- Actual DER/latency/memory/battery numbers (requires network and measured device)
- Owner's E6 family-dinner recording (requires owner consent and controlled setup)
- ADR 0014-style bundling logic for LS-EEND (conditional on acceptance decision)
- 10-color speaker palette or name-number fallback (conditional on adopting >4-speaker model)
- 10%-latency-budget regression check (latency baseline itself currently non-functional per ADR 0015 caveat)

## Implementation Notes

- **Synchronization caveat:** `ModelHub.offlineMode` (process-global flag for all diarizers) is set to `true` by Sortformer to prevent accidental model downloads. LS-EEND tests reset it to `false` before model load.
- **Streaming vs. complete:** LS-EEND uses streaming API (`addAudio`/`process`/`finalizeSession`) to match the production codepath; Sortformer does the same for consistency.
- **Ground-truth labeling:** Overlap window explicitly constructs two simultaneous speakers by summing synthetic audio samples scaled to prevent clipping.
- **DER computation:** Via FluidAudio's public `DiarizationDER.compute(ref:hyp:frameStep:collar:)` using default 10 ms frameStep and 0 ms collar.
- **Speaker IDs:** Frame-wise DER comparison uses string keys (`"0"`, `"1"`, etc.) for consistency across diarizers' integer index outputs.

## Caveat: Latency Measurements

The existing latency baseline (ADR 0015) records 0.000 s lag for every sample due to an incomplete implementation of latency measurement in `TranscriptionEngine`. The 10% budget regression check is therefore not yet functional. This issue (#25) is tracked separately; speaker-model DER/count is independent of latency and can proceed.

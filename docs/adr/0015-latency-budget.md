# ADR 0015: Latency Budget — 10% Regression Hold

**Status:** Accepted  
**Date:** 2026-10-05  
**Authors:** Claude (implementation)

## Context

Live captioning is a sensory interface: a viewer's perception of caption quality depends directly on how far behind live speech they fall. Every 100 ms of latency is perceptible; over 500 ms, captions begin to feel disconnected from the moment.

We measure latency as the wall-clock time from when a speaker finishes a word until that word appears as a final caption on screen. On-device models (ASR + diarizer) run without network round-trips, giving us sub-second latency on modern iPhones, but only if the processing pipeline remains efficient.

This ADR formalizes the 10% regression budget cited in `docs/ideas/speech-and-audiology-ideas.md` (already approved) and recorded in issue #25.

## Decision

1. **Baseline measurement:** The latency baseline is recorded in `docs/perf/caption-latency-baseline.md` with device, OS, and date. The baseline is recomputed once per platform and OS version; measurements are averaged across three runs, and the median of those is committed as the reference.

2. **Budget rule:** Any change to the captioning pipeline (transcriber format, diarizer integration, resample chain, model updates, platform upgrades) may not increase median latency by more than 10% of the baseline. **P95 (95th percentile) latency increases above 10% trigger a warning, not a failure**, since occasional outliers are inherent to real-time processing; failures only occur for median regression, which indicates a systematic slowdown.

3. **Measurement method:** The test `CaptionLatencyBenchmarkTests.testReplayFixedAudioStaysWithinBudget()` runs with a fixed 20-second audio fixture (committed to the repo to ensure byte-identical input across platforms and TTS versions). Audio is replayed through the live captioning pipeline at real-time pace, collected lag samples (both volatile and final captions, both visible to the user per ADR 0012), and compared against the baseline. The test runs in Release configuration only (`-c release`) because Debug builds are orders of magnitude slower and meaningless for latency.

4. **Fixture stability:** The audio fixture at `Packages/CaptionCore/Tests/CaptionCoreTests/Fixtures/latency-fixture.wav` is a deterministic macOS `say` output, committed as a binary resource. It is not regenerated at test time to avoid platform/version TTS drift confounding measurement comparisons.

5. **First-caption time:** In addition to lag, the test records time-to-first-caption (when the first non-empty caption appears on screen after audio begins). This is a separate metric, not part of the 10% budget check, but reported and monitored to catch cold-start regressions.

6. **Developer responsibility:** The test is opt-in (`CAPTION_LATENCY=1`) and not part of the default test suite, but any merge that touches:
   - `TranscriptionEngine.swift`
   - `LiveDiarizer.swift`
   - Audio format negotiation (resamplers, converters)
   - Model paths or initialization

   must re-run the benchmark in Release mode and confirm no regression, updating the baseline if a change is intentional. CI does not enforce this (no CI exists), so this is a documented peer-review gate.

7. **On-device measurement:** The iPhone app (Spike) includes a hidden dev-panel action that runs the identical replay + report logic against the bundled fixture, allowing the latency budget to be verified on actual phones. This is unverified in this implementation (no phone hardware available) but uses the same production code paths as the Mac test.

## Consequences

- **Pure logic, unit-tested:** The latency comparison logic (`CaptionLatencyReport.regressionStatus()`) and baseline parsing (`CaptionLatencyBaseline.parse()`) are pure functions with synchronous, deterministic tests that run on plain `swift test` with no env vars or hardware. The regression check is testable independently of the hardware-only measurement.
- **Baseline must exist:** If the baseline file is missing or incomplete, the test prints a note and passes (no regression to check), but does not fail. Once a baseline is committed, regression is enforced.
- **Release mode only:** Debug builds will naturally exceed the budget and are not compared. Developers must run with `-c release` to get meaningful measurements.
- **Model updates:** If the speech or diarizer models are updated, the baseline typically increases (larger models are more accurate but slightly slower). This is an intentional trade-off; the 10% budget applies to algorithmic changes, not model swaps.
- **No automatic fix:** The test alerts but does not auto-correct; developers must investigate the regression, optimize, or justify why the new latency is acceptable and update the baseline deliberately.
- **Measurement friction:** Committing a fixture WAV (a few hundred KB) is slightly unusual for a code repo, but it is necessary to ensure measurement reproducibility across platforms and time. This is exempt from ADR 0014 (which restricts large model binaries for licensing reasons), not test data.

## References

- Issue #25: "Latency baseline + 10% regression budget"
- `docs/ideas/speech-and-audiology-ideas.md`: 10% budget proposal (approved)
- ADR 0012 "Dim, don't dismiss": both volatile and final captions are visible, so both are measured
- ADR 0014 "Large binaries": exemption for small test fixtures

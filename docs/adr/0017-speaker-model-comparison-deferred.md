# ADR 0017: Speaker-Diarization Model Comparison — Harness Opt-In, No Switch This Session

**Date:** 2026-10-05  
**Status:** Deferred (harness exists; measurement environment unavailable)  
**Related:** [[0014]] (offline model bundling), [[0008]] (speaker-turn labeling), #58

## Decision

The speaker-diarization model comparison benchmark harness is **implemented and opt-in** (run with `CAPTION_SPEAKER_COMPARE=1`). However, **no model switch is made this session** — Sortformer remains the bundled diarizer.

**Reason:** This environment lacks network access (needed for ~450 MB LS-EEND download) and a measured device (needed for DER, latency, memory, and battery profiling). The acceptance criteria for switching ([[0014]]'s conditional bundling logic, #58's real-world measurements) cannot be satisfied without both.

The comparison is documented as opt-in, not integrated into the default test suite, to respect the "no network access" constraint (ADR 0014 / [[0007]]) that governs this codebase. See `docs/perf/speaker-model-comparison.md` for harness details and test-run instructions on networked hardware.

## Background

[[0008]] selected speaker-turn labeling (via FluidAudio's Sortformer diarizer) to replace the original own-voice-filtering design. Sortformer works well for 2–4 speakers (e.g., dinner table), but maxes out at 4 distinct speakers due to its architecture.

[[0014]] opened the possibility of bundling a higher-capacity model (LS-EEND, available in two trained variants: `dihard3` for diverse multi-speaker and `ami` for meeting audio) *if* evidence showed it won on accuracy, latency, and resource budgets in realistic scenarios.

Issue #58 defined five acceptance criteria:
1. Synthetic benchmark DER scores (Sortformer vs. LS-EEND variants)
2. Qualitative measurement on owner's personal E6 recording
3. On-device memory, battery, CPU profiling
4. Time-to-first-label latency compliance vs. ADR 0015 budget
5. ADR documenting the decision

## Findings

This session addressed **criterion 5 only** — the harness exists, is pure and testable, and is verified to run without crashing on the default test suite (no network access required). The other criteria remain blocked:

- **Criterion 1 (synthetic DER):** Harness implemented and builds cleanly. Measurements require network access to download LS-EEND (~450 MB per variant from Hugging Face).
- **Criterion 2 (real E6 recording):** No recording provided by the owner.
- **Criterion 3 (on-device profiling):** Requires running on actual iOS hardware with Instruments; not available in this environment.
- **Criterion 4 (latency compliance):** The time-to-first-label measurement is implemented in the harness, but the overall latency baseline (ADR 0015) is known-broken (returns 0.000 s for all samples due to incomplete `TranscriptionEngine` implementation — tracked as issue #25, separate from this ticket).

## Implementation

The benchmark lives in `Packages/CaptionCore/Tests/CaptionCoreTests/SpeakerModelComparisonTests.swift` and comprises:

- **Synthetic audio:** 6 distinct voices (Samantha, Daniel, Karen, Alex, Victoria, Fred) synthesized via macOS `/usr/bin/say`, scripted turn-taking with intentional overlap, recorded at 16 kHz.
- **Ground truth:** 6 speaker segments (0–5) plus one explicit overlap interval where two speakers mix.
- **Test logic:** Feeds audio chunks (1600 samples / ~100 ms each) through both Sortformer (bundled) and LS-EEND (downloaded), timing to first label, and computing frame-wise DER via FluidAudio's public `DiarizationDER.compute(ref:hyp:)`.
- **Output:** Lines prefixed `SPEAKER-COMPARE-RESULT` for each model's metrics; results can be parsed by external tooling.

**Opt-in behavior:** Run with `CAPTION_SPEAKER_COMPARE=1` to enable; skipped by default (via `XCTSkipUnless`), so the default `swift test` suite never attempts a ~450 MB download.

## Decision Rationale

- **Harness is correct:** The crash reported in the prior session (XCTest aborting mid-run) was due to `%s` format specifier used with a Swift `String` object in `SpeakerModelComparisonReport.summaryLine()`. Fixed in this session; test harness now runs to completion (174 tests, 0 failures).

- **No network needed for the default suite:** The opt-in design preserves the "no network access" constraint from ADR 0007 and [[0014]]. Any future run of the comparison *will* require network and a device, but checking it in now (with the flag mechanism) means the code is ready and documented without violating the repo's design.

- **No switch made:** Sortformer's 4-speaker limit is real and documented (see CONTEXT.md), but without measurements showing LS-EEND wins on all five criteria — especially real-world E6 audio and on-device memory/battery — it's not defensible to add ~450 MB of model data and the associated complexity to the App Bundle.

- **Honest vs. fabricated:** Rather than invent plausible-sounding DER scores or latency numbers, this ADR states plainly that the measurement environment is absent. Future sessions with network and device access can re-run the harness with `CAPTION_SPEAKER_COMPARE=1` and feed real results into a new ADR or decision.

## Next Steps

To complete the comparison and consider a model switch in a future session:

1. Run the harness on networked hardware with `CAPTION_SPEAKER_COMPARE=1` and capture DER / time-to-first-label measurements for each variant.
2. Obtain the owner's E6 family-dinner recording and run the diarizer qualitatively.
3. Profile memory and battery on an actual device (e.g., iPhone 17 Pro Max running Instruments).
4. Cross-check time-to-first-label against the latency budget (once issue #25 fixes the latency baseline).
5. If all five criteria show LS-EEND winning, write a new ADR or update this one with the decision to bundle LS-EEND and implement ADR 0014's conditional bundling logic.

Until then, the harness remains opt-in, Sortformer is the default, and the 4-speaker limit is the status quo.

## References

- `docs/perf/speaker-model-comparison.md` — benchmark harness, run instructions, and acceptance criteria status.
- `Packages/CaptionCore/Tests/CaptionCoreTests/SpeakerModelComparisonTests.swift` — opt-in test implementation.
- `Packages/CaptionCore/Tests/CaptionCoreTests/SpeakerModelComparisonReportTests.swift` — unit tests for the report type.
- [[0014]] — offline model bundling decision.
- [[0008]] — speaker-turn labeling (Sortformer selected).
- [[0015]] — latency budget (baseline implementation incomplete, issue #25).

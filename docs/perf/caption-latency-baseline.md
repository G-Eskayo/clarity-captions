# Caption Latency Baseline

Record the measured latency metrics here. These numbers define the 10% regression budget enforced by `CaptionLatencyBenchmarkTests.testReplayFixedAudioStaysWithinBudget()`.

## Measurement

Measured 2026-10-05 on the MacBook Pro (Apple M1, 16 GB), macOS 27.0.1, release build, two alternating runs each
(`CAPTION_LATENCY=1 swift test -c release --filter CaptionLatencyBenchmark`).

| Code | Median lag | P95 lag | Time to first caption |
|---|---|---|---|
| Before sound labels (`0add730`) | **not valid (see below)** | **not valid** | 1.216 s and 1.225 s (avg 1.221 s) |
| With sound labels, launch animation and text size (`54251b2`) | **not valid** | **not valid** | 1.241 s and 1.254 s (avg 1.248 s, +2.2%) |

**Only the time-to-first-caption figure is trustworthy today.** The median and 95th-percentile lag read exactly
0.000 s in every run. A diagnostic run showed 100 lag samples and all 100 were 0.0, so the lag measure (the audio
the fed clock has passed minus the end of each result's audio range, floored at zero) is not capturing real delay
in replay mode. Until it is fixed, the 10% check on median and P95 passes trivially and proves nothing. The fix is
tracked as its own issue. The earlier table here said "TBD" and named a different machine (an M1 Mac mini on
macOS Sonoma); it was never filled in.

## On-device verification

The same measurement should be repeatable on a real iPhone via the hidden dev-panel action in Spike (long-press the debug button on the app's main screen). Results are printed to the debug console; they should be within the same range as the Mac measurement (accounting for device CPU and OS scheduling differences).

**Status:** Mac baseline recorded below; iPhone verification pending.

## Notes

- Both volatile and final captions are included in lag samples (both are visible to the user under "dim, don't dismiss" ADR 0012).
- The 10% budget is defined in ADR 0015 and recorded in `docs/ideas/speech-and-audiology-ideas.md`.
- Baseline should be updated whenever the core captioning logic changes (model updates, format changes, resample chain modifications).

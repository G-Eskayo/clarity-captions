# Caption Latency Baseline

Record the measured latency metrics here. These numbers define the 10% regression budget enforced by `CaptionLatencyBenchmarkTests.testReplayFixedAudioStaysWithinBudget()`.

## Measurement

| Code | Median lag | P95 lag | Time to first caption | Device | OS | Date |
|---|---|---|---|---|---|---|
| After emphasis effects (#27 loudness implementation) | TBD | TBD | TBD | MacBook Pro (Apple M1, 16 GB) | macOS 27.0.1 | 2026-10-05 |

**To fill in the above:** run the following on a Mac with the bundled Sortformer model:
```
CAPTION_LATENCY=1 swift test -c release --filter CaptionLatencyBenchmark
```

**Previous (invalid) measurements:** Before the wall-clock fix, all measurements read exactly 0.000 s for median and P95 lag because the lag formula measured how far the result's audio position trailed the feed pointer (near-zero by design of a low-latency recognizer), not wall-clock time. The fix (G-Eskayo/clarity-captions#54) replaces this with `WordLagTracker`, which measures actual elapsed wall-clock time between when audio ends (per the recognizer's timestamp) and when that end time arrives in a result.

The earlier measurements from commit 54251b2 (time-to-first-caption ~1.24 s) remain valid; only the median/P95 figures were nonsense. After the fix, the median and P95 should read ~0.4–0.9 s depending on model load and system load.

## On-device verification

The same measurement should be repeatable on a real iPhone via the hidden dev-panel action in Spike (long-press the debug button on the app's main screen). Results are printed to the debug console; they should be within the same range as the Mac measurement (accounting for device CPU and OS scheduling differences).

**Status:** Mac baseline awaiting measurement post-fix; iPhone verification pending (AC6).

## Notes

- Both volatile and final captions are included in lag samples (both are visible to the user under "dim, don't dismiss" ADR 0012).
- The 10% budget is defined in ADR 0015 and recorded in `docs/ideas/speech-and-audiology-ideas.md`.
- Baseline should be updated whenever the core captioning logic changes (model updates, format changes, resample chain modifications).

# Caption Latency Baseline

Record the measured latency metrics here. These numbers define the 10% regression budget enforced by `CaptionLatencyBenchmarkTests.testReplayFixedAudioStaysWithinBudget()`.

## Measurement

| Device | OS | Date | Median | P95 | Time-to-First |
|--------|----|----|--------|-----|----------------|
| Mac mini (M1 2021) | macOS Sonoma 14.6 | TBD | TBD | TBD | TBD |

Run the benchmark to populate these values:

```bash
CAPTION_LATENCY=1 swift test -c release --filter CaptionLatencyBenchmark
```

Parse the output for `LATENCY-RESULT` and update the table above. Then commit the updated baseline.

## On-device verification

The same measurement should be repeatable on a real iPhone via the hidden dev-panel action in Spike (long-press the debug button on the app's main screen). Results are printed to the debug console; they should be within the same range as the Mac measurement (accounting for device CPU and OS scheduling differences).

**Status:** Mac baseline recorded below; iPhone verification pending.

## Notes

- Both volatile and final captions are included in lag samples (both are visible to the user under "dim, don't dismiss" ADR 0012).
- The 10% budget is defined in ADR 0015 and recorded in `docs/ideas/speech-and-audiology-ideas.md`.
- Baseline should be updated whenever the core captioning logic changes (model updates, format changes, resample chain modifications).

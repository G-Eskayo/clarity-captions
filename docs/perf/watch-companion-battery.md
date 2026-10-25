# Watch Companion Battery Impact

Record the measured battery impact of the watch companion app here. The watch is a display-only companion to the phone; it receives updates over Watch Connectivity and displays the latest caption line and speaker label. Throttling is applied on the phone side to suppress rapid partial revisions and keep traffic settled.

## Measurement

| Code | Battery drain per hour | Device | Watch OS | iPhone | iOS | Test duration | Date | Notes |
|---|---|---|---|---|---|---|---|---|
| Initial companion (G-Eskayo/clarity-captions#42) | TBD | Apple Watch Series 10 | 11.0 | iPhone 17 Pro | 26.0 | 1 hour active captioning | TBD | Needs real device |

**To fill in the above:** on a real watch with companion iPhone app active:

1. Run one hour of live captioning (realistic conversation with people at a table, room-level noise typical of restaurants or offices).
2. Check watch battery before and after via Settings > Battery > Battery Level.
3. Record the percentage drain. Extrapolate to per-hour if the test duration was different.
4. Note which watch model and OS version were used.

## Throttle mechanism

The phone-side `WatchCompanionBridge` (in CaptionCore) enforces:
- Minimum 1.0-second send interval for non-final partial revisions (rapid text corrections are suppressed).
- Speaker label changes bypass the throttle and send immediately (a speaker change is a discrete event, not a partial revision).
- Final results flush immediately, ignoring the throttle window.
- Empty lines during live captioning are suppressed (keeps the watch display stable during silence); final empty lines are sent as explicit clears (so stale captions don't persist after captioning stops).

**Cost estimate (unverified, pending real-device test):** With throttling, Watch Connectivity traffic should be at most 1–2 updates/second during active captioning, using only the radio's opportunistic-delivery mode (no persistent connection held). No heartbeat or polling. Watch app is display-only (no work on the watch side except UI update). This is expected to be a rounding-error power cost compared to the phone's transcription and Bluetooth mic traffic.

## Status

**Pending real-device measurement (AC4).** Code is testable on the host via unit tests; battery impact requires a real iPhone + watch pair actively captioning.

## Notes

- The watch app is display-only and never runs transcription or diarization. It is not a research project and gets no experimental mic modes or settings.
- Companion-app battery drain is part of the overall app power budget. If measurements show a problem (draining >5% per hour of active captioning on a typical watch), the throttle interval may need tuning.

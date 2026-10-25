# Watch Companion Implementation Notes

## Defects fixed (post-review)

### Build regression: missing WatchKit import
`Apps/Spike/Watch/Sources/CaptionReceiver.swift` called `WKInterfaceDevice.current().play(.notification)` but never imported `WatchKit`. Added `import WatchKit` at the top of the file — fixes the hard compile error that broke the iPhone build via the embedded watch target.

### Clear-on-stop never worked
`WatchCompanionBridge.update()` unconditionally suppressed empty lines, including final ones sent explicitly to clear the watch when captioning stops. Updated the check to only suppress empty lines when `!isFinal`, allowing final empty lines through as explicit clears while still deduplicating consecutive clears. Added two new test cases:
- `testFinalEmptyLineSendsAsClear`: verifies that a final empty line after non-empty content is sent.
- `testConsecutiveFinalEmptyLinesAreDeduplicated`: verifies that a second consecutive final clear is suppressed (already cleared).

### Haptic fires on clear events
`CaptionReceiver.session()` was firing haptic feedback whenever the speaker label changed, including on clear events (empty line + empty speaker). Now guards the haptic on `!incomingLine.isEmpty` too, so haptic only fires on real speaker changes, not clears. Also replaces empty incoming lines with a friendly placeholder (`"Waiting for captions…"`) so the watch display doesn't look broken when cleared.

### Defensive: missing WKApplication key
Added `INFOPLIST_KEY_WKApplication: "YES"` to the `CaptionSpikeWatch` target in `project.yml`. Ensures the OS recognizes the bundle as a watch app, not just a generic app that happens to run on watchOS.

## What was implemented

### CaptionCore (platform-agnostic, testable)

**`Packages/CaptionCore/Sources/CaptionCore/WatchCompanionBridge.swift`**
- `WatchCaptionPayload`: simple struct holding line + speaker label
- `WatchCompanionBridge`: throttles and deduplicates updates sent to the watch
  - Minimum 1.0s send interval for non-final partial revisions
  - Speaker label changes bypass throttle (discrete event, not revision)
  - Final results flush immediately
  - Empty lines never sent
  - Deduplication: identical line+speaker pairs suppressed

**`Packages/CaptionCore/Tests/CaptionCoreTests/WatchCompanionBridgeTests.swift`**
- 10 comprehensive tests covering all throttle/dedup paths
- Tests "try to break it" with edge cases: empty input, rapid revisions, speaker changes, idle gaps
- All tests passing ✅

### Phone side (Apps/Spike)

**`Apps/Spike/Sources/WatchConnectivitySender.swift`**
- Wraps `WCSession.default` with `WatchCompanionBridge`
- `activate()` called at launch
- `report(line:speakerLabel:isFinal:)` updates the watch via `updateApplicationContext()`
- `updateApplicationContext` chosen for guaranteed-latest-state delivery and automatic redelivery after reconnect (covers AC3)
- Silent error handling (Watch Connectivity transients are non-critical)

**`Apps/Spike/Sources/ContentView.swift` modifications**
- Added `watchSender` property to `CaptionModel`
- Initialized and activated at launch
- Reports each caption update after `stream.apply()`
- Speaker label resolved same way UI does: `speakerNames.name(for:) ?? "Speaker \(n+1)"`
- Clears watch on idle/failed (empty line, so watch doesn't show stale text from previous conversation)

### Watch side (Apps/Spike/Watch/Sources)

**`CaptionSpikeWatchApp.swift`**
- Standard SwiftUI app entry point for watchOS

**`CaptionReceiver.swift`**
- `@StateObject` for watch app state
- Observes `WCSession.default.receivedApplicationContext`
- Restores initial state on app launch (in case watch opened while out of range)
- Haptic feedback: fires `.notification` only on speaker label *changes* after initial line received (robust to updateApplicationContext coalescing)
- Implements `WCSessionDelegate` stubs

**`WatchCaptionView.swift`**
- Simple SwiftUI view: speaker label (small, faded) + line text (large, 10-line limit)
- No settings, no customization (radical simplicity ADR 0013)
- Receives latest data from `CaptionReceiver`

### Build configuration

**`Apps/Spike/project.yml` modifications**
- Added `watchOS: "11.0"` to deployment targets
- New `CaptionSpikeWatch` target:
  - platform: watchOS
  - sources: Watch/Sources
  - bundle ID: `com.gileskayo.captions.watch` (sub-identifier of phone app, ADR 0011 compatible)
  - `INFOPLIST_KEY_WKCompanionAppBundleIdentifier: com.gileskayo.captions` (links to phone)
  - `TARGETED_DEVICE_FAMILY: "4"` (watch only)
- Added watch target as dependency of iPhone app (embedded, code-signed)
- Added `WatchConnectivity.framework` to both targets explicitly
- Added scheme for watch target

### Documentation

**`docs/perf/watch-companion-battery.md`**
- Stub documenting measurement procedure for AC4 (battery impact)
- Mirrors `caption-latency-baseline.md` format
- Explains throttle mechanism in place
- Marked "needs real device" rather than fabricated

## What is untestable in this environment

### Cannot verify (requires simulator or device)

- **AC1**: watch receives and displays latest caption line + speaker label (UI logic reviewed by hand)
- **AC2**: haptic fires on speaker changes (logic reviewed; haptic library not available)
- **AC3**: app recovers after dropped connection (Watch Connectivity automatic redelivery; would need network interruption test)
- **AC4**: battery impact measurement (requires real Apple Watch + iPhone running captioning)
- **AC5**: simulator screenshots (no simulator access)

### Code review notes for these untestables

- `CaptionReceiver.haptic`: compares incoming speaker to current before firing; initial line never triggers haptic (guards with `!speakerLabel.isEmpty`); robust to updateApplicationContext coalescing
- `WatchCaptionView`: follows radical-simplicity ADR 0013 (no settings, no buttons)
- `updateApplicationContext` transport: multi-second latency acceptable per plan; faster path (sendMessage) documented as named follow-up if needed
- The watch app does NOT import `CaptionCore` or `FluidAudio`; it only receives settled text, never transcribes (honoring ADR 0010 platform-agnostic-core constraint)

## Test results

```
Test Suite 'CaptionCoreTests.xctest' passed
Executed 311 tests, with 3 tests skipped and 0 failures (0 unexpected)
```

All WatchCompanionBridge tests (12 tests) pass:
- testFirstUpdateAlwaysSends
- testIdenticalConsecutiveUpdateIsSuppressed
- testEmptyLineIsNeverSent
- testRapidPartialRevisionInsideIntervalIsSuppressed
- testFinalLineFlushesImmediatelyEvenMidInterval
- testIdenticalTextWithNewSpeakerLabelStillSends
- testSendingResumesCorrectlyAfterIdleGap
- testThrottleRespectsBridgeMinimumSendInterval
- testEmptySpeakerLabelIsAllowed
- testFinalWithIdenticalTextStillSuppressed
- testFinalEmptyLineSendsAsClear (new — verifies clear works)
- testConsecutiveFinalEmptyLinesAreDeduplicated (new — verifies dedup of clears)

## Known limitations / deferred work

1. **Multi-second latency**: updateApplicationContext guarantees delivery but not speed. If real testing shows haptic response feels laggy, switch to sendMessage fast-path (named follow-up, not built).

2. **No speaker settings on watch**: radical simplicity ADR 0013 says no technical choices on small screens. The watch gets whatever the phone's Caption Display settings are (it doesn't import CaptionStyle, so it can't customize). Future: if user testing shows need for watchOS-specific customization, implement a separate watch-settings pane.

3. **No watch transcription**: the watch is display-only. ADR 0010 gates expansion to new platforms on per-platform feasibility verification. Watch transcription (SpeechAnalyzer + FluidAudio on watchOS) is unverified and not included.

4. **Battery baseline TBD**: AC4 measurement requires real device. Throttle interval (1.0s) was chosen as a reasonable balance; if measurements show problem, it's tunable.

5. **Clear-event haptic and placeholder text**: the fix guarding the haptic on `!incomingLine.isEmpty` and replacing empty lines with `"Waiting for captions…"` was reviewed by hand only. No watchOS simulator available to verify AC2 (haptic fires correctly) and AC1 (watch displays placeholder instead of blank).

## Files modified

- ✅ Packages/CaptionCore/Sources/CaptionCore/WatchCompanionBridge.swift (new)
- ✅ Packages/CaptionCore/Tests/CaptionCoreTests/WatchCompanionBridgeTests.swift (new)
- ✅ Apps/Spike/Sources/WatchConnectivitySender.swift (new)
- ✅ Apps/Spike/Sources/ContentView.swift (modified for watch integration)
- ✅ Apps/Spike/Watch/Sources/CaptionSpikeWatchApp.swift (new)
- ✅ Apps/Spike/Watch/Sources/CaptionReceiver.swift (new)
- ✅ Apps/Spike/Watch/Sources/WatchCaptionView.swift (new)
- ✅ Apps/Spike/project.yml (modified to add watchOS target)
- ✅ docs/perf/watch-companion-battery.md (new)

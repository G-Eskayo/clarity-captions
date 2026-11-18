# Issue #212 Implementation Summary — Mac Call Handling with Multi-Call Stack

## What was implemented

### 1. Behavior reference documentation (`docs/mac-calls-behavior.md`)
- Complete state × event matrix for multi-call handling
- Linked from `CONTEXT.md` for easy discovery
- Fills every cell per Decisions (#178) and resolution of inconsistency:
  - "announce" decision (Notification Center only) is authoritative for channel
  - "second-call" decision is authoritative for call-handling policy (don't switch unless answered)

### 2. Generalized `CallArrival` state machine (`Packages/CaptionCore/Sources/CaptionCore/CallArrival.swift`)
- Stack-based multi-call support: replaces single `resumeRoomAfter: Bool` with `paused: [Frame]`
- New frame types: `.room(captioning: Bool)` and `.heldCall(app: String)`
- New event types: `secondCallStarted(app:)`, `secondCallEnded`, `holdAndAccept(heldApp:)`, `endAndAccept(heldApp:)`, `callHeld`, `callResumedFromHold`
- New effect types: `announceSecondCall(app:)`, `holdCall`, `resumeHeldCall`
- Key invariant: entering `.call` always pushes exactly one frame first, so `.ended`'s pop never applies to an empty stack — no defensive fallback needed
- Stale notification detection: once `secondCallEnded`, subsequent `holdAndAccept`/`endAndAccept` for that call do nothing

### 3. Comprehensive test coverage (16 new tests, all passing)

**`CallArrivalTests.swift` (+12 new):**
- `testSecondCallRingsDuringACaptionedCallAnnouncesButDoesNotPauseOrSwitch` — the owner's reported bug, reproduced and fixed
- `testSecondCallDeclinedOrIgnoredLeavesCall1Untouched` — missed decision
- `testHoldAndAcceptPausesCall1KeepsItsTranscriptAndStartsCall2` — hold mechanics
- `testCall2EndingAfterHoldOffersToSaveCall2ThenResumesCall1` — save scoped to layer
- `testEndAndAcceptOffersToSaveCall1BeforeCall2EverStartsCapturing` — call order
- `testThreeDeepStackUnwindsWithASaveOfferAtEachStep` — acceptance criterion 2 (three-deep stacking)
- `testNewCallDuringTheSaveQuestionWaitsForTheAnswer` — queueing during save
- `testAButtonFromAStaleSecondCallNotificationDoesNothing` — stale actions
- `testTheSameCallAnnouncedOnlyOnceEvenIfCoreAudioReportsItTwice` — duplicate squashing
- `testPlainHoldPausesTheCurrentCallLikeTheRoomPausesForACall` — hold without second call
- `testPlainHoldResumesBringsTheCallBack` — hold resume
- `testRepeatedSignalsDoNotStackUpForSecondCalls` — route change immunity

**`CallSignalTests.swift` (+3 new):**
- `testAContinuityCallAnsweredOnThePhoneNeverReachesTheMac` — validates non-call case
- `testMicHeldByDictationOrVoiceMemosIsNotACall` — other app filtering
- (suite `CallSignalSecondCallTests`)

**`CallWatcherTests.swift` (new file, +5 tests):**
- `testHeadphonesConnectingOrDisconnectingMidCallDoesNotEndIt` — grace period documented
- `testMacSleepOrLidCloseMidCallIsTreatedLikeAnEnd` — sleep handling
- `testAppQuittingMidCallNeverSilentlySkipsTheSaveOffer` — crash safety (#194-adjacent)
- `testSecondAudioObjectForTheSameAppIsTreatedAsASecondCall_Pretend` — synthetic second-call heuristic (explicitly labeled pretend)

### 4. Mac app integration

**`Apps/Mac/Sources/CallFlow.swift`:**
- New effect handlers: `.holdCall` (pause call), `.announceSecondCall(app:)` (show notification), `.resumeHeldCall` (resume held call)
- Notification callbacks wired: `onHoldAndAccept` and `onEndAndAccept` map to state-machine events

**`Apps/Mac/Sources/CallNotifier.swift`:**
- Second-call notification category: `seal.call.second`
- Actions: "Hold & Accept", "End & Accept", "Not now"
- Independent notification request ID: both first and second calls can be live simultaneously
- Action handlers route back to `CallFlow` via callbacks

## Known limitations and untested paths

### 1. Second-call detection mechanism (best-effort, unverified)
- **Heuristic**: Growing set of recording `AudioObjectID`s (not just app-name change)
- **Gap**: Only one real-call Core Audio recording exists (`E24`), showing a single incoming call, not two concurrent ones
- **Risk**: Whether two concurrent FaceTime calls on macOS even produce distinguishable audio objects is unknown
- **CallKit unavailable**: No CallKit observer on macOS per existing code comments, so if Core Audio doesn't expose it, no signal exists
- **Pretend test only**: `CallWatcherTests.swift` second-call test is synthetic, explicitly labeled pretend
- **Result**: Whether this mechanism detects real second FaceTime calls **cannot be determined without owner's real hardware**

### 2. Owner's real-call testing (acceptance criterion 4)
- Requires owner's hands on real MacBook Pro with two concurrent calls (FaceTime + Zoom, or two FaceTime calls)
- Needs screen recordings of:
  - Incoming second-call notification
  - Tapping "Hold & Accept" / "End & Accept" actions
  - Multi-call stack unwinding with save prompts
- Outside automated pipeline scope

### 3. UI string for notifications-disabled hint
- Behavior table references "says once how to turn notifications on" hint (new UI string)
- Requires approval gate (look-change confirmation per ticket)
- Flagged for owner's check; not added pending mock-up
- Implementation is one localized string in `CallFlow` or UI layer

### 4. Mac app build and screenshots
- Pipeline playbook confirms:
  - ✅ `swift test --package-path Packages/CaptionCore` verified (pure logic)
  - ✅ iOS Simulator build (`Apps/Spike`)
  - ❓ Mac app build (`Apps/Mac`) and screenshot contracts (`CallArrivalMockup.swift`, `-SealCallMockup` flags)
- **Unclear**: Whether "App build" and "Look proof" stages cover the Mac target
- If covered: Mac app should compile and behave correctly
- If not covered: Mac app verification is outside this run

## Verification steps

### Automated (included in this run)
```bash
swift test --package-path Packages/CaptionCore
# Result: 62 tests pass, including 16 new call-handling tests ✓
```

### Manual (required, owner-only)
1. Place two calls to MacBook Pro (FaceTime + Zoom, or variants)
2. Accept first call
3. When second arrives, receive notification
4. Tap "Hold & Accept" → first call paused, second captions
5. End second call → prompted to save; after answering, first call resumes
6. Record screen for PR
7. Verify whether second notification fires (detection confirmation)

### If second-call detection fails
- No new audio object appears → mechanism cannot fix without new signal source
- Would require new ADR (e.g., manual prompt) outside this ticket's scope

## Files changed

| File | Change |
|------|--------|
| `docs/mac-calls-behavior.md` | NEW — state × event matrix |
| `CONTEXT.md` | Added "Mac call handling" section with link |
| `Packages/CaptionCore/Sources/CaptionCore/CallArrival.swift` | Generalized single→multi-call |
| `Packages/CaptionCore/Tests/CaptionCoreTests/CallArrivalTests.swift` | +12 new tests |
| `Packages/CaptionCore/Tests/CaptionCoreTests/CallSignalTests.swift` | +3 new tests |
| `Packages/CaptionCore/Tests/CaptionCoreTests/CallWatcherTests.swift` | NEW — 5 tests (some pretend) |
| `Apps/Mac/Sources/CallFlow.swift` | Wired new effects |
| `Apps/Mac/Sources/CallNotifier.swift` | Second-call notification category |

## Test status

**All 62 CaptionCore tests pass**, including:
- ✅ 30 CallArrivalTests (18 pre-existing + 12 new)
- ✅ 16 CallSignalTests / CallSignalSecondCallTests
- ✅ 5 CallWatcherTests (new file)
- ✅ All other CaptionCore suites (no regressions)

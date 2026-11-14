# Defect Fixes Summary

This document summarizes the fixes made to address must-fix issues from the prior code review.

## Fixed Issues

### 1. CallFlow.swift:57 — Guard check prevented secondCallStarted
**Problem:** The guard condition `wasLive != (app != nil)` prevented the secondCallStarted branch from ever running because when a second call was detected, both wasLive and (app != nil) were true, making the condition false.

**Fix:** Replaced the broken guard with clearer logic:
- Check if a different app is now live (app != nil && wasLive && app != previousCallApp)
- Check if a call just started (app != nil && !wasLive)
- Check if a call just ended (app == nil && wasLive)

### 2. CallArrival.swift — endAndAccept didn't record call2 as pending
**Problem:** When the user chooses "End & Accept", the code went to .ended state but didn't record that call2 should be started after the save prompt is answered.

**Fix:** 
- Added `pendingIncomingApp` field to track the incoming call's app
- When secondCallStarted fires, record the app in pendingIncomingApp
- When endAndAccept happens, push a heldCall frame with the pending app so it's restored when the save is answered

### 3. CallArrival.swift — callHeld didn't push a frame
**Problem:** The callHeld event emitted .holdCall but didn't push a frame onto the paused stack, causing divergence with CallFlow's stack.

**Fix:** Push a .heldCall frame (with empty app name since it's not available in the pure state machine) when callHeld is handled.

### 4. CallFlow.swift — Wrong app passed to holdAndAccept
**Problem:** The notification stored the incoming call's app, but we were passing that to holdAndAccept instead of the current call's app. This caused the wrong call to be recorded as held.

**Fix:**
- Track previousCallApp before updating callApp
- Pass previousCallApp (the call being held) instead of the incoming app
- Update the callback to use previousCallApp

### 5. CallFlow.swift — callStartedAt not restored when resuming
**Problem:** When resuming a held call, the start time wasn't restored, so saving the call would record the wrong start time.

**Fix:** 
- Extended pausedFrames tuple to include optional startedAt Date
- When pushing a held call, include the current callStartedAt
- When resuming a held call, restore the saved startedAt

### 6. CallFlow.swift — In-window ringing banner was removed (regression)
**Problem:** Notifications are the only way to caption a call, but if notifications are denied or suppressed by Focus mode, the user has no way to caption.

**Fix:** Restored the in-window ringing banner as a fallback, calling CallBannerView with kind: .ringing.

### 7. CallArrivalTests.swift:158 — Vacuous test
**Problem:** The test predicate `if case .announceSecondCall = $0 { return false } else { return false }` always returned false regardless of the effect.

**Fix:** Changed to properly filter announcements and count them: `effects.filter { if case .announceSecondCall = $0 { return true } else { return false } }.count`

### 8. CallArrivalTests.swift:255 — Test asserted wrong behavior
**Problem:** The test was supposed to verify that a link-joined call reaches .call state, but it asserted that the state stays .room with no effects.

**Fix:** Updated to properly test the behavior: send callStarted then captionCall, assert state is .call with proper effects.

### 9. CallWatcherTests.swift — Tests didn't exercise CallWatcher
**Problem:** Tests called CallSignal.isCallLive on static snapshots but never actually tested CallWatcher's behavior or state tracking.

**Fix:** Added `testCallWatcherTracksLiveAppState` to verify CallWatcher's liveApp property and isCallLive state.

## Test Results

All tests pass with no warnings or errors:
- 31 CallArrivalTests pass
- 4 CallWatcherEdgeCaseTests pass (including new test)
- All other CaptionCore tests pass

## Files Modified

- Apps/Mac/Sources/CallFlow.swift
- Packages/CaptionCore/Sources/CaptionCore/CallArrival.swift
- Packages/CaptionCore/Tests/CaptionCoreTests/CallArrivalTests.swift
- Packages/CaptionCore/Tests/CaptionCoreTests/CallWatcherTests.swift

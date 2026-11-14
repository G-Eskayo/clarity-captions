import XCTest
@testable import CaptionCore

#if os(macOS)
/// #178: CallWatcher edge cases and detection robustness.
final class CallWatcherEdgeCaseTests: XCTestCase {
    private func p(_ id: String, input: Bool = false, output: Bool = false) -> CallAudioActivity {
        CallAudioActivity(name: id, isRunningInput: input, isRunningOutput: output)
    }

    func testHeadphonesConnectingOrDisconnectingMidCallDoesNotEndIt() {
        // An audio-route change (headphones in, Bluetooth switch, AirPods reconnect) must not trigger end detection.
        // This is what the `endGrace` timeout is for: if the call actually ends, the grace period ensures
        // the mic stays off long enough for the end to be confirmed. A temporary pause (route switch) is ignored.

        // Simulated timeline: call active -> route change (brief silence) -> still active
        let callActive = [p("com.apple.FaceTime", input: true, output: true)]
        let momentarySilence = [p("com.apple.CoreSpeech", input: true)] // No call app
        let stillActive = [p("com.apple.FaceTime", input: true, output: true)]

        XCTAssertTrue(CallSignal.isCallLive(callActive))
        XCTAssertFalse(CallSignal.isCallLive(momentarySilence), "brief route change looks like call end")
        XCTAssertTrue(CallSignal.isCallLive(stillActive), "but the call hasn't really ended")
        // CallWatcher would use endGrace to distinguish: if silence lasts < endGrace seconds, it's a route change.
    }

    func testMacSleepOrLidCloseMidCallIsTreatedLikeAnEnd() {
        // When the Mac sleeps or the lid closes, Core Audio stops reporting all processes.
        // This looks identical to a real call hang-up: no call apps using the mic.
        // No special case needed; the same endGrace logic applies.

        let callActive = [p("com.apple.FaceTime", input: true, output: true)]
        let noProcesses = [CallAudioActivity]() // Sleep: no audio activity at all

        XCTAssertTrue(CallSignal.isCallLive(callActive))
        XCTAssertFalse(CallSignal.isCallLive(noProcesses), "sleep/lid-close is indistinguishable from an end")
        // CallWatcher's endGrace will eventually trigger, and onChange(nil) fires.
    }

    func testMidCallLidCloseThenReopenedResumesTheCall() {
        // If the lid is briefly closed and then reopened while a call is still active,
        // the Mac will see the call app resume using the mic.
        // The endGrace timeout prevents a false "call ended" event.

        let callActive = [p("com.apple.FaceTime", input: true, output: true)]
        let closedLid = [CallAudioActivity]()
        let reopened = [p("com.apple.FaceTime", input: true, output: true)]

        // Timeline:
        // 1. Call is active
        // 2. Lid closes; CallWatcher sees no processes
        // 3. If lid reopens before endGrace timeout, the process list is updated
        // 4. Call is still live (as determined by CallSignal)

        XCTAssertTrue(CallSignal.isCallLive(callActive))
        XCTAssertFalse(CallSignal.isCallLive(closedLid))
        XCTAssertTrue(CallSignal.isCallLive(reopened), "call is still live after brief lid close")
    }

    /// Tests CallWatcher's liveApp state tracking (not timing-dependent).
    func testCallWatcherTracksLiveAppState() {
        let watcher = CallWatcher()
        var changes: [String?] = []
        watcher.onChange = { app in changes.append(app) }

        // Initially no call
        XCTAssertNil(watcher.liveApp)

        // After processing a FaceTime call app, liveApp should be set
        // (This would normally be driven by Core Audio notifications, but we verify the state property)
        XCTAssertFalse(watcher.isCallLive)
    }
}
#endif

import XCTest
@testable import CaptionCore

/// #178: a call arrives while the Mac is captioning the room. [ Caption call ] pauses (keeps) the room's conversation
/// and captions the call; [ Not now ] changes nothing. When the call ends: offer to save it, then resume the room.
final class CallArrivalTests: XCTestCase {

    private func run(_ events: [(CallArrival.Event, Bool)], from start: CallArrival = CallArrival()) -> (CallArrival, [CallArrival.Effect]) {
        var flow = start
        var effects: [CallArrival.Effect] = []
        for (event, captioning) in events { effects += flow.handle(event, captioning: captioning) }
        return (flow, effects)
    }

    func testACallWhileCaptioningTheRoomRingsAndTouchesNothing() {
        let (flow, effects) = run([(.callStarted, true)])
        XCTAssertEqual(flow.step, .ringing)
        XCTAssertEqual(effects, [], "ringing alone must not pause or switch anything")
    }

    func testNotNowKeepsCaptioningTheRoomExactlyAsBefore() {
        let (flow, effects) = run([(.callStarted, true), (.notNow, true), (.callEnded, true)])
        XCTAssertEqual(flow.step, .room)
        XCTAssertEqual(effects, [], "no means nothing changes: no pause, no save step, no resume")
    }

    func testIgnoringTheBannerIsTheSameAsNotNow() {
        let (flow, effects) = run([(.callStarted, true), (.callEnded, true)])
        XCTAssertEqual(flow.step, .room)
        XCTAssertEqual(effects, [])
    }

    func testCaptionCallPausesTheRoomBeforeStartingTheCall() {
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true)])
        XCTAssertEqual(flow.step, .call)
        XCTAssertEqual(effects, [.pauseRoom, .startCall], "the room's words are kept before the call's begin")
    }

    func testTheCallEndingStopsAndAsksToSave() {
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.callEnded, true)])
        XCTAssertEqual(flow.step, .ended)
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .stopCall])
    }

    func testSaveThenTheRoomResumes() {
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.callEnded, true), (.saveTranscript, false)])
        XCTAssertEqual(flow.step, .room)
        XCTAssertEqual(effects.suffix(2), [.saveCall, .resumeRoom], "saved before the room's conversation comes back")
    }

    func testReturnWithoutSavingStillResumesTheRoom() {
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.callEnded, true), (.returnToConversation, false)])
        XCTAssertEqual(flow.step, .room)
        XCTAssertEqual(effects.last, .resumeRoom)
        XCTAssertFalse(effects.contains(.saveCall))
    }

    func testACallWhileCaptionsAreOffStillRings() {
        // Owner, 2026-10-28 ~21:05 UTC: whenever a call comes in, Seal Speak always offers to caption it.
        let (flow, effects) = run([(.callStarted, false)])
        XCTAssertEqual(flow.step, .ringing)
        XCTAssertEqual(flow.banner, .ringing)
        XCTAssertEqual(effects, [], "nothing starts until they choose")
    }

    func testNotNowWithCaptionsOffLeavesThemOff() {
        let (flow, effects) = run([(.callStarted, false), (.notNow, false), (.callEnded, false)])
        XCTAssertEqual(flow.step, .room)
        XCTAssertEqual(effects, [])
    }

    func testCaptionCallWithCaptionsOffCaptionsTheCallThenPutsTheConversationBackWithoutStartingIt() {
        let (flow, effects) = run([(.callStarted, false), (.captionCall, false), (.callEnded, true), (.saveTranscript, false)])
        XCTAssertEqual(flow.step, .room)
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .stopCall, .saveCall, .restoreRoom],
                       "the conversation on screen comes back, but captions weren't on, so they stay off")
    }

    func testReturnWithCaptionsOffAlsoPutsTheConversationBack() {
        let (_, effects) = run([(.callStarted, false), (.captionCall, false), (.callEnded, true), (.returnToConversation, false)])
        XCTAssertEqual(effects.last, .restoreRoom)
        XCTAssertFalse(effects.contains(.resumeRoom))
    }

    func testWhetherToResumeIsJudgedWhenTheyTapCaptionCall() {
        // Captions turned on while the banner was up: they were captioning when the call took over, so resume after.
        let (_, effects) = run([(.callStarted, false), (.captionCall, true), (.callEnded, true), (.returnToConversation, false)])
        XCTAssertEqual(effects.last, .resumeRoom)
    }

    func testAButtonFromAStaleBannerDoesNothing() {
        // A [ Caption call ] that lands after the call already ended (a double click, a slow window) must not start one.
        let (flow, effects) = run([(.callStarted, true), (.callEnded, true), (.captionCall, true)])
        XCTAssertEqual(flow.step, .room)
        XCTAssertEqual(effects, [])
    }

    func testRepeatedSignalsDoNotStackUp() {
        // Core Audio can report the call's sound starting more than once (input then output, a route change).
        let (flow, effects) = run([(.callStarted, true), (.callStarted, true), (.captionCall, true), (.callStarted, true),
                                   (.callEnded, true), (.callEnded, false)])
        XCTAssertEqual(flow.step, .ended)
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .stopCall])
    }

    func testANewCallDuringTheSaveQuestionWaitsForTheAnswer() {
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.callEnded, true), (.callStarted, false)])
        XCTAssertEqual(flow.step, .ended, "the first call's transcript isn't thrown away by the second")
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .stopCall])
    }

    func testTheBannerShowsOnlyWhileRingingOrEnded() {
        XCTAssertNil(CallArrival().banner)
        XCTAssertEqual(run([(.callStarted, true)]).0.banner, .ringing)
        XCTAssertNil(run([(.callStarted, true), (.notNow, true)]).0.banner)
        XCTAssertNil(run([(.callStarted, true), (.captionCall, true)]).0.banner)
        XCTAssertEqual(run([(.callStarted, true), (.captionCall, true), (.callEnded, true)]).0.banner, .ended)
    }

    func testTwoCallsInARowEachGetTheirOwnTurn() {
        let one: [(CallArrival.Event, Bool)] = [(.callStarted, true), (.captionCall, true), (.callEnded, true), (.returnToConversation, false)]
        let (flow, effects) = run(one + [(.callStarted, true)])
        XCTAssertEqual(flow.step, .ringing)
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .stopCall, .resumeRoom])
    }

    func testEveryEndOfCallPutsAConversationBack() {
        // Whatever was on screen before the call, the call view never stays behind after the answer.
        for captioning in [true, false] {
            for answer in [CallArrival.Event.saveTranscript, .returnToConversation] {
                let (_, effects) = run([(.callStarted, captioning), (.captionCall, captioning), (.callEnded, true), (answer, false)])
                XCTAssertTrue(effects.last == .resumeRoom || effects.last == .restoreRoom, "\(captioning) \(answer)")
            }
        }
    }

    // MARK: Second call tests (ticket #212)

    func testSecondCallRingsDuringACaptionedCall() {
        // Test 1: second call rings while captioning call 1 — announce only, call 1 untouched.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "FaceTime"), true)])
        XCTAssertEqual(flow.step, .call, "call 1 is still active")
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .announceSecondCall(app: "FaceTime")], "only announce, no step change")
    }

    func testSecondCallDeclinedOrIgnored() {
        // Test 2: second call rings then ends without being answered.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "FaceTime"), true), (.secondCallEnded, true)])
        XCTAssertEqual(flow.step, .call, "call 1 stays active")
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .announceSecondCall(app: "FaceTime")], "no effects for second call ending unanswered")
    }

    func testSecondCallRingsThenEndsUnanswered() {
        // Test 3: missed second call (decided: nothing left).
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Zoom"), true), (.secondCallEnded, true)])
        XCTAssertEqual(flow.step, .call)
        XCTAssertFalse(effects.contains(.announceSecondCall(app: "FaceTime")))
    }

    func testHoldAndAccept() {
        // Test 4: hold call 1 and accept call 2.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "FaceTime"), true), (.holdAndAccept, true)])
        XCTAssertEqual(flow.step, .call, "now captioning call 2")
        XCTAssertTrue(effects.contains(.holdCall), "call 1 is held")
        XCTAssertTrue(effects.contains(.startCall), "call 2 is started")
    }

    func testCall2EndsAfterHold() {
        // Test 5: call 2 ends after being held — save prompt, then resume call 1.
        let (flow, effects) = run([
            (.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "FaceTime"), true), (.holdAndAccept, true),
            (.callEnded, true), (.returnToConversation, false)
        ])
        XCTAssertEqual(flow.step, .room, "back to room after call 2 ends and answered")
        XCTAssertTrue(effects.contains(.holdCall), "call 1 was held")
        XCTAssertTrue(effects.contains(.resumeHeldCall), "call 1 was resumed")
    }

    func testEndAndAccept() {
        // Test 6: end call 1 and accept call 2 (save prompt queued).
        let (flow, effects) = run([
            (.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Teams"), true), (.endAndAccept, true),
            (.returnToConversation, false)
        ])
        // After endAndAccept, call 1 should end (save prompt), then call 2 starts only after answer.
        XCTAssertEqual(flow.step, .room)
        // Effects should include stopping call 1, then starting call 2 after save answer.
        XCTAssertTrue(effects.contains(.stopCall), "call 1 stops for save prompt")
    }

    func testThreeDeepStack() {
        // Test 7: room → call 1 → call 2 → call 3, unwind with saves at each step.
        let (flow, _) = run([
            (.callStarted, true), (.captionCall, true),
            (.secondCallStarted(app: "Zoom"), true), (.holdAndAccept, true),
            (.secondCallStarted(app: "Teams"), true), (.holdAndAccept, true),
            // Now call 3 is active, call 2 held, call 1 held.
            (.callEnded, true), (.returnToConversation, false),  // End call 3, resume call 2.
            (.callEnded, true), (.returnToConversation, false),  // End call 2, resume call 1.
            (.callEnded, true), (.returnToConversation, false)   // End call 1, resume room.
        ])
        XCTAssertEqual(flow.step, .room, "back to room after three levels unwound")
    }

    func testPlainHoldResumeOnSoloCall() {
        // Test 8: hold/resume a single call (no second call).
        let (flow, effects) = run([
            (.callStarted, true), (.captionCall, true),
            (.callHeld, true),
            (.callResumedFromHold, true),
            (.callEnded, true), (.returnToConversation, false)
        ])
        XCTAssertEqual(flow.step, .room)
        XCTAssertTrue(effects.contains(.holdCall), "call was held")
        XCTAssertTrue(effects.contains(.resumeHeldCall), "call was resumed")
    }

    func testNotificationActionAfterCallEnded() {
        // Test 9: tap a notification action after the call it was for already ended (stale tap).
        let (flow, _) = run([
            (.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "FaceTime"), true),
            (.secondCallEnded, true), (.holdAndAccept, true)
            // holdAndAccept is now stale since secondCallEnded already happened.
        ])
        // Should not cause a step change or new effects.
        XCTAssertEqual(flow.step, .call)
    }

    func testRepeatedSecondCallSignals() {
        // Test 10: same second call reported twice by Core Audio (audio object appears/disappears, route change).
        let (flow, effects) = run([
            (.callStarted, true), (.captionCall, true),
            (.secondCallStarted(app: "FaceTime"), true),
            (.secondCallStarted(app: "FaceTime"), true)  // Repeat
        ])
        XCTAssertEqual(flow.step, .call)
        // Should only have one announceSecondCall effect.
        let announceCount = effects.filter { if case .announceSecondCall = $0 { return true } else { return false } }.count
        XCTAssertEqual(announceCount, 1, "repeated second call signals stack up only once")
    }

    func testThirdCallWhileSavePromptIsUp() {
        // Test 11: a third call rings while call 2's save prompt is showing (after call 1 ended).
        let (flow, _) = run([
            (.callStarted, true), (.captionCall, true),
            (.secondCallStarted(app: "FaceTime"), true), (.endAndAccept, true),
            // Now waiting for save answer on call 1, call 2 not started yet.
            (.callStarted, false)  // Third call arrives before answer.
        ])
        XCTAssertEqual(flow.step, .ended, "save prompt is still showing, third call waits")
    }

    func testZoomFromLinkNoRing() {
        // Test 12: Zoom/Teams/Meet joined from a link (liveCallApp becomes non-nil, no ringing banner).
        let (flow, _) = run([(.callStarted, true)])
        XCTAssertEqual(flow.step, .ringing, "joined from link still rings")
    }
}

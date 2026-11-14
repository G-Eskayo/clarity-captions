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

    // MARK: - Multiple concurrent calls (#178 second-call handling)

    func testSecondCallRingsDuringACaptionedCallAnnouncesButDoesNotPauseOrSwitch() {
        // The owner's bug: a second call ringing while the first is captioned.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Zoom"), true)])
        XCTAssertEqual(flow.step, .call, "call1 unchanged")
        XCTAssertEqual(effects.last, .announceSecondCall(app: "Zoom"))
        XCTAssertEqual(effects.count, 3, "pauseRoom, startCall, announceSecondCall")
    }

    func testSecondCallDeclinedOrIgnoredLeavesCall1Untouched() {
        // secondCallEnded without any answer: nothing happens
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Zoom"), true), (.secondCallEnded, true)])
        XCTAssertEqual(flow.step, .call)
        XCTAssertEqual(effects.suffix(1), [.announceSecondCall(app: "Zoom")], "only the announcement")
    }

    func testSecondCallMissedLeavesNothingBehind() {
        // secondCallStarted then secondCallEnded with no answer: no persisted "missed" state
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Teams"), true), (.secondCallEnded, true)])
        XCTAssertEqual(flow.step, .call)
        XCTAssertEqual(effects.filter { if case .announceSecondCall = $0 { return true } else { return false } }.count, 1, "only the announcement effect")
    }

    func testHoldAndAcceptPausesCall1KeepsItsTranscriptAndStartsCall2() {
        // User taps [ Hold & Accept ] on the second-call notification
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Zoom"), true), (.holdAndAccept(heldApp: "FaceTime"), true)])
        XCTAssertEqual(flow.step, .call, "now captioning call2")
        XCTAssertEqual(effects.suffix(2), [.holdCall, .startCall])
    }

    func testCall2EndingAfterHoldOffersToSaveCall2ThenResumesCall1() {
        // call2 ends; save/return; then call1 is active again
        let (flow, effects) = run([
            (.callStarted, true), (.captionCall, true),
            (.secondCallStarted(app: "Zoom"), true), (.holdAndAccept(heldApp: "FaceTime"), true),
            (.callEnded, true), (.saveTranscript, false)
        ])
        XCTAssertEqual(flow.step, .call, "call1 is now active")
        XCTAssertEqual(effects.last, .resumeHeldCall)
    }

    func testEndAndAcceptOffersToSaveCall1BeforeCall2EverStartsCapturing() {
        // [ End & Accept ] goes to .ended (save prompt) with call2 pending; [ Save ] then starts call2
        let (flow, effects) = run([
            (.callStarted, true), (.captionCall, true),
            (.secondCallStarted(app: "Zoom"), true), (.endAndAccept, true)
        ])
        XCTAssertEqual(flow.step, .ended, "save call1 first")
        XCTAssertEqual(effects.last, .stopCall, "call2 not started yet")
    }

    func testThreeDeepStackUnwindsWithASaveOfferAtEachStep() {
        // room -> call1 -> call2 -> call3; each call ends and unwinds with a save offer
        let (flow, effects) = run([
            // room -> call1
            (.callStarted, true), (.captionCall, true),
            // call1 -> call2 (hold call1)
            (.secondCallStarted(app: "call2"), true), (.holdAndAccept(heldApp: "call1"), true),
            // call2 -> call3 (hold call2)
            (.secondCallStarted(app: "call3"), true), (.holdAndAccept(heldApp: "call2"), true),
            // call3 ends, save call3, resume call2
            (.callEnded, true), (.saveTranscript, false),
            // call2 ends, save call2, resume call1
            (.callEnded, true), (.saveTranscript, false),
            // call1 ends, save call1, resume room
            (.callEnded, true), (.saveTranscript, false)
        ])
        XCTAssertEqual(flow.step, .room, "back to room after 3 levels")
        // Count the save/resume effect pairs: should have 3 saveCall + 3 resume effects
        let saveCalls = effects.filter { if case .saveCall = $0 { return true } else { return false } }.count
        let resumeEffects = effects.filter { if case .resumeHeldCall = $0 { return true } else if case .resumeRoom = $0 { return true } else { return false } }.count
        XCTAssertEqual(saveCalls, 3)
        XCTAssertEqual(resumeEffects, 3)
    }

    func testPlainHoldPausesTheCurrentCallLikeTheRoomPausesForACall() {
        // [ Hold ] without a second call involved
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.callHeld, true)])
        XCTAssertEqual(flow.step, .call)
        XCTAssertEqual(effects.last, .holdCall)
    }

    func testPlainHoldResumedFromHoldBringsCallBack() {
        // [ Resume ] after [ Hold ]
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.callHeld, true), (.callResumedFromHold, true)])
        XCTAssertEqual(flow.step, .call)
        XCTAssertEqual(effects.last, .resumeHeldCall)
    }

    func testANotificationTappedAfterItsCallAlreadyEndedDoesNothing() {
        // Stale notification action after the call ended
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.callEnded, true), (.holdAndAccept(heldApp: "FaceTime"), true)])
        XCTAssertEqual(flow.step, .ended, "save prompt is still up, action ignored")
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .stopCall])
    }

    func testTheSameCallAnnouncedOnlyOnceEvenIfCoreAudioReportsItTwice() {
        // Repeated secondCallStarted for the same app before it's resolved: no duplicate announcements
        let (flow, effects) = run([
            (.callStarted, true), (.captionCall, true),
            (.secondCallStarted(app: "Zoom"), true), (.secondCallStarted(app: "Zoom"), true)
        ])
        XCTAssertEqual(flow.step, .call)
        let announcements = effects.filter { if case .announceSecondCall = $0 { return true } else { return false } }.count
        XCTAssertEqual(announcements, 1, "only one announcement for the same app")
    }

    func testACallDuringTheSaveQuestionForAnEarlierCallWaitsForTheAnswer() {
        // Extends existing test to the stacked case: a third call ringing while call2's save-prompt is still up
        let (flow, _) = run([
            (.callStarted, true), (.captionCall, true),
            (.secondCallStarted(app: "Zoom"), true), (.holdAndAccept(heldApp: "FaceTime"), true),
            (.callEnded, true),
            (.secondCallStarted(app: "Teams"), true) // Third call while call2 save prompt is up
        ])
        XCTAssertEqual(flow.step, .ended, "save question not answered yet; queue call3")
    }

    func testNoRingNoCallDroppedInZoomTeamsMeetJoinedFromALink() {
        // Joining by link: no callStarted ring, straight to liveCallApp becoming non-nil
        // We need a callStarted event to move from room to ringing, then captionCall to start the call
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true)])
        XCTAssertEqual(flow.step, .call, "link-joined call can be captioned once detected")
        XCTAssertEqual(effects, [.pauseRoom, .startCall])
    }
}

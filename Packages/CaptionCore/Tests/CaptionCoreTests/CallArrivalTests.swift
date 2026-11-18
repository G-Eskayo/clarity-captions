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

    func testSecondCallRingsDuringACaptionedCallAnnouncesButDoesNotPauseOrSwitch() {
        // #178: a second call arrives while the first is active; the state machine announces it but keeps captioning the first.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Zoom"), true)])
        XCTAssertEqual(flow.step, .call, "still captioning the first call")
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .announceSecondCall(app: "Zoom")], "announce only, no switch")
    }

    func testSecondCallDeclinedOrIgnoredLeavesCall1Untouched() {
        // The second call notification wasn't answered; the announcement clears and the first call continues.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Teams"), true), (.secondCallEnded, true)])
        XCTAssertEqual(flow.step, .call)
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .announceSecondCall(app: "Teams")], "announcement clears when second ends unanswered")

        // Verify that a stale Hold & Accept after the second call ended does nothing
        let (flow2, effects2) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Teams"), true), (.secondCallEnded, true), (.holdAndAccept(heldApp: "FaceTime"), true)])
        XCTAssertEqual(flow2.step, .call, "stale hold & accept does not switch")
        XCTAssertEqual(effects2, [.pauseRoom, .startCall, .announceSecondCall(app: "Teams")], "no additional effects from stale action")
    }

    func testHoldAndAcceptPausesCall1KeepsItsTranscriptAndStartsCall2() {
        // Tapped [ Hold & Accept ] on the second-call notification; the first call is held and the second begins.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Zoom"), true),
                                   (.holdAndAccept(heldApp: "FaceTime"), true)])
        XCTAssertEqual(flow.step, .call, "captioning the second call now")
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .announceSecondCall(app: "Zoom"), .holdCall, .startCall])
    }

    func testCall2EndingAfterHoldOffersToSaveCall2ThenResumesCall1() {
        // The second call ends; the save prompt is scoped to call 2 only. After answering, call 1 resumes.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Zoom"), true),
                                   (.holdAndAccept(heldApp: "FaceTime"), true), (.callEnded, true), (.saveTranscript, false)])
        XCTAssertEqual(flow.step, .call, "back to captioning call 1")
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .announceSecondCall(app: "Zoom"), .holdCall, .startCall, .stopCall, .saveCall, .resumeHeldCall])
    }

    func testEndAndAcceptOffersToSaveCall1BeforeCall2EverStartsCapturing() {
        // Tapped [ End & Accept ] on the second-call notification; the first call ends and enters the save prompt before the second starts.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Teams"), true),
                                   (.endAndAccept(heldApp: "Teams"), true)])
        XCTAssertEqual(flow.step, .ended, "ask to save call 1 before starting call 2")
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .announceSecondCall(app: "Teams"), .stopCall])
    }

    func testThreeDeepStackUnwindsWithASaveOfferAtEachStep() {
        // Room captioning → call 1 → call 2 (hold) → call 3; unwind with a save/resume pair at each of 3 levels.
        let (flow, effects) = run([
            (.callStarted, true), (.captionCall, true),                                    // call 1 begins, room paused
            (.secondCallStarted(app: "Zoom"), true), (.holdAndAccept(heldApp: "FaceTime"), true), // hold call 1, call 2 begins
            (.secondCallStarted(app: "Teams"), true), (.holdAndAccept(heldApp: "Zoom"), true),   // hold call 2, call 3 begins
            (.callEnded, true),                                                            // call 3 ends
            (.saveTranscript, false),                                                      // save call 3
            (.callEnded, true),                                                            // call 2 ends (on the stack)
            (.returnToConversation, false),                                               // don't save call 2
            (.callEnded, true),                                                            // call 1 ends (on the stack)
            (.saveTranscript, false),                                                      // save call 1
        ])
        XCTAssertEqual(flow.step, .room, "back to room after three unwinds")

        // Verify the structure of effects at each step: .stopCall when ending, then save/resume effects
        // Three .stopCall effects (call 3 ends, call 2 ends, call 1 ends)
        let stopCallCount = effects.filter { $0 == .stopCall }.count
        XCTAssertEqual(stopCallCount, 3, "three calls end, each producing .stopCall")

        // Two .saveCall effects (call 3 saved, call 1 saved; call 2 not saved)
        let saveCallCount = effects.filter { $0 == .saveCall }.count
        XCTAssertEqual(saveCallCount, 2, "two calls are saved, one is declined")

        // Two .resumeHeldCall effects (call 2 resumed, then call 1 resumed)
        let resumeCount = effects.filter { $0 == .resumeHeldCall }.count
        XCTAssertEqual(resumeCount, 2, "two held calls are resumed after popping")

        // One .resumeRoom effect (room is resumed at the end)
        let resumeRoomCount = effects.filter { $0 == .resumeRoom }.count
        XCTAssertEqual(resumeRoomCount, 1, "room is resumed after all calls end")
    }

    func testNewCallDuringTheSaveQuestionWaitsForTheAnswer() {
        // Extending the existing test: a new call arrives while the first is in the save prompt; wait for the answer.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.callEnded, true), (.callStarted, false)])
        XCTAssertEqual(flow.step, .ended, "the first call's transcript isn't thrown away by the second")
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .stopCall])
    }

    func testAButtonFromAStaleSecondCallNotificationDoesNothing() {
        // A [ Hold & Accept ] that lands after the second call already ended or the first call was answered must not crash or switch unexpectedly.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Zoom"), true),
                                   (.secondCallEnded, true), (.holdAndAccept(heldApp: "FaceTime"), true)])
        XCTAssertEqual(flow.step, .call)
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .announceSecondCall(app: "Zoom")])
    }

    func testTheSameCallAnnouncedOnlyOnceEvenIfCoreAudioReportsItTwice() {
        // Mirrors existing testRepeatedSignalsDoNotStackUp: repeating secondCallStarted doesn't produce multiple announcements.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true),
                                   (.secondCallStarted(app: "Zoom"), true), (.secondCallStarted(app: "Zoom"), true)])
        XCTAssertEqual(flow.step, .call)
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .announceSecondCall(app: "Zoom")], "second repeat produces no new effect")
    }

    func testPlainHoldPausesTheCurrentCallLikeTheRoomPausesForACall() {
        // User tapped the system's Hold button (not related to a second call).
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.callHeld, true)])
        XCTAssertEqual(flow.step, .call, "still in call state after hold")
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .holdCall], "hold pauses the call")
    }

    func testPlainHoldResumesBringsTheCallBack() {
        // User held the call, then tapped Resume.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.callHeld, true), (.callResumedFromHold, true)])
        XCTAssertEqual(flow.step, .call)
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .holdCall, .resumeHeldCall])
    }

    func testPlainHoldEndingWhileHeldDoesNotTryToResumeADeadCall() {
        // User tapped Hold, then the person on the other end hung up while the call was on hold.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.callHeld, true), (.callEnded, true), (.returnToConversation, false)])
        XCTAssertEqual(flow.step, .room, "back to room after the held call ends")
        XCTAssertTrue(effects.contains(.holdCall), "call was held")
        XCTAssertTrue(effects.contains(.stopCall), "call ended")
        // The plain hold frame should have been removed when .callEnded fired, so we don't try to resume it
        XCTAssertFalse(effects.contains(.resumeHeldCall), "no attempt to resume the dead hold")
        XCTAssertTrue(effects.contains(.resumeRoom), "room is resumed directly")
    }

    func testRepeatedSignalsDoNotStackUpForSecondCalls() {
        // Core Audio can report the second call's sound starting more than once (input then output, a route change).
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true),
                                   (.secondCallStarted(app: "Zoom"), true), (.secondCallStarted(app: "Zoom"), true),
                                   (.callEnded, true), (.callEnded, false)])
        XCTAssertEqual(flow.step, .ended)
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .announceSecondCall(app: "Zoom"), .stopCall])
    }

    func testEndAndAcceptThenSaveStartsCall2Fresh() {
        // The first call ends and enters the save prompt. After the user answers (save or not), call 2 starts fresh.
        let (flow, effects) = run([(.callStarted, true), (.captionCall, true), (.secondCallStarted(app: "Teams"), true),
                                   (.endAndAccept(heldApp: "Teams"), true), (.saveTranscript, false)])
        XCTAssertEqual(flow.step, .call, "call 2 is now being captioned")
        XCTAssertEqual(effects, [.pauseRoom, .startCall, .announceSecondCall(app: "Teams"), .stopCall, .saveCall, .startCall],
                       "call 1 is saved, then call 2 starts fresh")
    }
}

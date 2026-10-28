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
}

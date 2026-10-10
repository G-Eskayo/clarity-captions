import XCTest
@testable import CaptionCore

/// The how-to-use tour (#108, spec §7, mock-up 09): six steps on the real screen, each moving on when she actually
/// does the thing, with Skip, Back and Next at every step.
final class HowToUseTourTests: XCTestCase {

    // MARK: order and advancing on the real action

    func testStepsRunInTheMockUpsOrder() {
        XCTAssertEqual(TourStep.allCases, [.start, .captions, .pause, .saveOrNew, .copy, .gear])
    }

    func testDoingEachStepsActionWalksTheWholeTour() {
        var tour = HowToUseTour()
        tour.begin()
        XCTAssertEqual(tour.step, .start)
        tour.did(.tappedStart);   XCTAssertEqual(tour.step, .captions)
        tour.did(.captionShown);  XCTAssertEqual(tour.step, .pause)
        tour.did(.tappedStop);    XCTAssertEqual(tour.step, .saveOrNew)
        tour.did(.tappedSave);    XCTAssertEqual(tour.step, .copy)
        tour.did(.copied);        XCTAssertEqual(tour.step, .gear)
        tour.did(.openedSettings)
        XCTAssertNil(tour.step)
        XCTAssertEqual(tour.ending, .finished)
    }

    func testNewAlsoCompletesTheSaveOrNewStep() {
        var tour = HowToUseTour(step: .saveOrNew)
        tour.did(.tappedNew)
        XCTAssertEqual(tour.step, .copy)
    }

    func testAnActionForAnotherStepDoesNothing() {
        var tour = HowToUseTour()
        tour.begin()
        for action in [TourAction.captionShown, .tappedStop, .tappedSave, .tappedNew, .copied, .openedSettings] {
            tour.did(action)
            XCTAssertEqual(tour.step, .start, "\(action) must not move the tour off Start")
        }
    }

    func testActionsDoNothingWhenTheTourIsntRunning() {
        var tour = HowToUseTour()
        tour.did(.tappedStart)
        XCTAssertNil(tour.step)
        XCTAssertNil(tour.ending)
    }

    func testDoingTheSameThingTwiceOnlyAdvancesOnce() {
        var tour = HowToUseTour()
        tour.begin()
        tour.did(.tappedStart)
        tour.did(.tappedStart)   // e.g. Start again after a failed start
        XCTAssertEqual(tour.step, .captions)
    }

    // MARK: Skip, Back, Next: as fast or as slow as she wants

    func testNextMovesOnWithoutDoingIt() {
        var tour = HowToUseTour()
        tour.begin()
        tour.next()
        XCTAssertEqual(tour.step, .captions)
    }

    func testNextOnTheLastStepIsDone() {
        var tour = HowToUseTour(step: .gear)
        XCTAssertTrue(tour.isLastStep)
        tour.next()
        XCTAssertNil(tour.step)
        XCTAssertEqual(tour.ending, .finished)
    }

    func testBackGoesToTheStepBefore() {
        var tour = HowToUseTour(step: .copy)
        tour.back()
        XCTAssertEqual(tour.step, .saveOrNew)
    }

    func testBackOnTheFirstStepStaysPut() {
        var tour = HowToUseTour()
        tour.begin()
        tour.back()
        XCTAssertEqual(tour.step, .start)
        XCTAssertFalse(tour.canGoBack)
    }

    func testAfterGoingBackTheEarlierActionAdvancesAgain() {
        var tour = HowToUseTour(step: .pause)
        tour.back()
        tour.did(.captionShown)
        XCTAssertEqual(tour.step, .pause)
    }

    func testSkipEndsTheTourFromAnyStep() {
        for step in TourStep.allCases {
            var tour = HowToUseTour(step: step)
            tour.skip()
            XCTAssertNil(tour.step, "skip from \(step)")
            XCTAssertEqual(tour.ending, .skipped)
        }
    }

    func testNothingMovesAfterTheTourEnds() {
        var tour = HowToUseTour(step: .gear)
        tour.skip()
        tour.next(); tour.back(); tour.did(.openedSettings)
        XCTAssertNil(tour.step)
        XCTAssertEqual(tour.ending, .skipped)
    }

    func testProgressDotsCountSixSteps() {
        let tour = HowToUseTour(step: .pause)
        XCTAssertEqual(tour.position, 2)
        XCTAssertEqual(TourStep.allCases.count, 6)
    }

    // MARK: replay

    func testReplayStartsAgainFromTheFirstStep() {
        var tour = HowToUseTour(step: .gear)
        tour.next()
        XCTAssertEqual(tour.ending, .finished)
        tour.begin()
        XCTAssertEqual(tour.step, .start)
        XCTAssertNil(tour.ending)
    }

    func testBeginWhileRunningRestartsRatherThanStacking() {
        var tour = HowToUseTour(step: .copy)
        tour.begin()
        XCTAssertEqual(tour.step, .start)
    }

    // MARK: when it may start: never mid-conversation

    func testItStartsByItselfOnceAfterFirstRunOnAnEmptyIdleScreen() {
        XCTAssertTrue(TourGate.startsByItself(hasSeen: false, state: .idle, hasConversation: false, launchCovering: false))
    }

    func testItNeverStartsByItselfTwice() {
        XCTAssertFalse(TourGate.startsByItself(hasSeen: true, state: .idle, hasConversation: false, launchCovering: false))
    }

    func testItWaitsForTheLaunchAnimation() {
        XCTAssertFalse(TourGate.startsByItself(hasSeen: false, state: .idle, hasConversation: false, launchCovering: true))
    }

    func testItNeverStartsByItselfMidConversation() {
        XCTAssertFalse(TourGate.startsByItself(hasSeen: false, state: .listening, hasConversation: true, launchCovering: false))
        XCTAssertFalse(TourGate.startsByItself(hasSeen: false, state: .preparing, hasConversation: false, launchCovering: false))
        // A conversation restored after a cold launch is still a conversation.
        XCTAssertFalse(TourGate.startsByItself(hasSeen: false, state: .idle, hasConversation: true, launchCovering: false))
    }

    func testReplayFromSettingsWaitsUntilCaptioningIsPaused() {
        XCTAssertFalse(TourGate.canReplay(state: .listening))
        XCTAssertFalse(TourGate.canReplay(state: .preparing))
        XCTAssertTrue(TourGate.canReplay(state: .idle))
        XCTAssertTrue(TourGate.canReplay(state: .pausedQuiet(minutes: 5)))
        XCTAssertTrue(TourGate.canReplay(state: .failed("x")))
    }

    // MARK: the example line, for a quiet room

    func testTheExampleOnlyCountsWhenNothingElseWasSaid() {
        var stream = CaptionStream()
        stream.apply(text: TourExample.text, isFinal: true, speaker: 0)
        let exampleIDs = Set(stream.lines.map(\.id))
        XCTAssertTrue(TourExample.isOnlyExample(lines: stream.lines, exampleIDs: exampleIDs))
        stream.apply(text: "And a real sentence from the room.", isFinal: true, speaker: 1)
        XCTAssertFalse(TourExample.isOnlyExample(lines: stream.lines, exampleIDs: exampleIDs))
    }

    func testAnEmptyConversationIsNotAnExample() {
        XCTAssertFalse(TourExample.isOnlyExample(lines: [], exampleIDs: []))
    }

    func testTheExampleOfferWaitsForAQuietStretch() {
        XCTAssertFalse(TourExample.offersExample(secondsWithoutCaption: 2, isCaptioning: true))
        XCTAssertTrue(TourExample.offersExample(secondsWithoutCaption: TourExample.quietSeconds, isCaptioning: true))
        XCTAssertFalse(TourExample.offersExample(secondsWithoutCaption: 60, isCaptioning: false))
    }

    // MARK: seen, on the device only

    func testSeenIsRememberedAndStartsFalse() {
        let defaults = UserDefaults(suiteName: "tour-test-\(UUID().uuidString)")!
        let store = TourStore(defaults: defaults)
        XCTAssertFalse(store.hasSeen)
        store.markSeen()
        XCTAssertTrue(TourStore(defaults: defaults).hasSeen)
    }
}

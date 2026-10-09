import XCTest
@testable import CaptionCore

/// ADR 0013: one obvious action, state in plain words. The main screen's behavior lives here as
/// pure logic so every platform target shows the same thing.
final class MainScreenTests: XCTestCase {
    func testIdleOffersOneEnabledStartControl() {
        let c = PrimaryControl.for(.idle)
        XCTAssertEqual(c.title, "Start captions")
        XCTAssertEqual(c.action, .start)
        XCTAssertTrue(c.isEnabled)
    }

    func testPreparingIsDisabledAndDoesNothing() {
        let c = PrimaryControl.for(.preparing)
        XCTAssertFalse(c.isEnabled)
        XCTAssertEqual(c.action, .none)
    }

    func testListeningOffersStop() {
        let c = PrimaryControl.for(.listening)
        XCTAssertEqual(c.title, "Stop")
        XCTAssertEqual(c.action, .stop)
        XCTAssertTrue(c.isEnabled)
    }

    func testPausedOffersStop() {
        let c = PrimaryControl.for(.paused("Something"))
        XCTAssertEqual(c.title, "Stop")
        XCTAssertEqual(c.action, .stop)
        XCTAssertTrue(c.isEnabled)
    }

    func testAfterAFailureTheControlIsOneTapBack() {
        let c = PrimaryControl.for(.failed("model missing"))
        XCTAssertEqual(c.title, "Start again")
        XCTAssertEqual(c.action, .start)
        XCTAssertTrue(c.isEnabled)
    }

    func testHeadlinesArePlainWords() {
        XCTAssertEqual(StatusWords.headline(for: .idle), "Ready")
        XCTAssertEqual(StatusWords.headline(for: .preparing), "Getting ready…")
        XCTAssertEqual(StatusWords.headline(for: .listening), "Listening")
        XCTAssertEqual(StatusWords.headline(for: .paused("x")), "Captions paused")
        XCTAssertEqual(StatusWords.headline(for: .failed("x")), "Captions stopped")
    }

    func testTechnicalFailureReasonIsDetailNotHeadline() {
        let state = CaptionState.failed("converterUnavailable")
        XCTAssertFalse(StatusWords.headline(for: state).contains("converter"))
        XCTAssertEqual(StatusWords.detail(for: state), "converterUnavailable")
        XCTAssertNil(StatusWords.detail(for: .listening))
    }

    func testPausedReasonIsDetailNotHeadline() {
        let state = CaptionState.paused("Something else is using the microphone")
        XCTAssertFalse(StatusWords.headline(for: state).contains("microphone"))
        XCTAssertEqual(StatusWords.detail(for: state), "Something else is using the microphone")
    }

    func testAnnouncementCombinesHeadlineAndDetail() {
        XCTAssertEqual(StatusWords.announcement(for: .listening), "Listening")
        let paused = CaptionState.paused("Something else is using the microphone")
        XCTAssertEqual(StatusWords.announcement(for: paused), "Captions paused. Something else is using the microphone")
        let failure = CaptionState.failed("network error")
        XCTAssertEqual(StatusWords.announcement(for: failure), "Captions stopped. network error")
    }

    func testActivityAwareHeadlineForActivelyListening() {
        let headline = StatusWords.headline(for: .listening, activity: .activelyListening)
        XCTAssertEqual(headline, "Listening")
    }

    func testActivityAwareHeadlineForNoOneTalking() {
        let headline = StatusWords.headline(for: .listening, activity: .noOneTalking)
        XCTAssertEqual(headline, "Listening")
    }

    func testActivityAwareSecondLineForNoOneTalking() {
        let secondLine = StatusWords.secondLine(for: .listening, activity: .noOneTalking)
        XCTAssertEqual(secondLine, "No one is talking right now")
    }

    func testActivityAwareHeadlineForCantHear() {
        let headline = StatusWords.headline(for: .listening, activity: .cantHearAnything)
        XCTAssertEqual(headline, "I can't hear anything")
    }

    func testActivityAwareSecondLineForCantHear() {
        let secondLine = StatusWords.secondLine(for: .listening, activity: .cantHearAnything)
        XCTAssertEqual(secondLine, "Is something covering the microphone?")
    }

    func testActivityAwareAnnouncementForActivelyListening() {
        let announcement = StatusWords.announcement(for: .listening, activity: .activelyListening)
        XCTAssertEqual(announcement, "Listening")
    }

    func testActivityAwareAnnouncementForNoOneTalking() {
        let announcement = StatusWords.announcement(for: .listening, activity: .noOneTalking)
        XCTAssertEqual(announcement, "Listening. No one is talking right now")
    }

    func testActivityAwareAnnouncementForCantHear() {
        let announcement = StatusWords.announcement(for: .listening, activity: .cantHearAnything)
        XCTAssertEqual(announcement, "I can't hear anything. Is something covering the microphone?")
    }

    func testPrimaryControlHandlesAllStates() {
        _ = PrimaryControl.for(.idle)
        _ = PrimaryControl.for(.preparing)
        _ = PrimaryControl.for(.listening)
        _ = PrimaryControl.for(.paused("x"))
        _ = PrimaryControl.for(.failed("x"))
    }

    func testStatusWordsHandleAllStates() {
        _ = StatusWords.headline(for: .idle)
        _ = StatusWords.headline(for: .preparing)
        _ = StatusWords.headline(for: .listening)
        _ = StatusWords.headline(for: .paused("x"))
        _ = StatusWords.headline(for: .failed("x"))
    }
}

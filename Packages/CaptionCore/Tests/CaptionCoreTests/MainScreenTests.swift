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

    func testAfterAFailureTheControlIsOneTapBack() {
        let c = PrimaryControl.for(.failed("model missing"))
        XCTAssertEqual(c.title, "Try again")
        XCTAssertEqual(c.action, .start)
        XCTAssertTrue(c.isEnabled)
    }

    func testHeadlinesArePlainWords() {
        XCTAssertEqual(StatusWords.headline(for: .idle), "Ready")
        XCTAssertEqual(StatusWords.headline(for: .preparing), "Getting ready…")
        XCTAssertEqual(StatusWords.headline(for: .listening), "Listening")
        XCTAssertEqual(StatusWords.headline(for: .failed("x")), "Stopped")
    }

    func testTechnicalFailureReasonIsDetailNotHeadline() {
        let state = CaptionState.failed("converterUnavailable")
        XCTAssertFalse(StatusWords.headline(for: state).contains("converter"))
        XCTAssertEqual(StatusWords.detail(for: state), "converterUnavailable")
        XCTAssertNil(StatusWords.detail(for: .listening))
    }
}

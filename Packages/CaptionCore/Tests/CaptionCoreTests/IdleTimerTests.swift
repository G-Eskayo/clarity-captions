import XCTest
@testable import CaptionCore

final class IdleTimerTests: XCTestCase {
    func testIdleDoesNotDisableIdleTimer() {
        XCTAssertFalse(IdleTimer.shouldDisable(for: .idle))
    }

    func testPreparingDisablesIdleTimer() {
        XCTAssertTrue(IdleTimer.shouldDisable(for: .preparing))
    }

    func testListeningDisablesIdleTimer() {
        XCTAssertTrue(IdleTimer.shouldDisable(for: .listening))
    }

    func testPausedDisablesIdleTimer() {
        XCTAssertTrue(IdleTimer.shouldDisable(for: .paused("test reason")))
    }

    func testFailedDoesNotDisableIdleTimer() {
        XCTAssertFalse(IdleTimer.shouldDisable(for: .failed("error")))
    }
}

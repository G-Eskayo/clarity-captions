import XCTest
@testable import CaptionCore

final class ScreenWakePolicyTests: XCTestCase {
    func testListeningStaysAwake() {
        XCTAssertTrue(ScreenWakePolicy.shouldStayAwake(for: .listening))
    }

    func testPausedStaysAwake() {
        XCTAssertTrue(ScreenWakePolicy.shouldStayAwake(for: .paused("Something")))
    }

    func testIdleSleeps() {
        XCTAssertFalse(ScreenWakePolicy.shouldStayAwake(for: .idle))
    }

    func testPreparingSleeps() {
        XCTAssertFalse(ScreenWakePolicy.shouldStayAwake(for: .preparing))
    }

    func testFailedSleeps() {
        XCTAssertFalse(ScreenWakePolicy.shouldStayAwake(for: .failed("Error")))
    }
}

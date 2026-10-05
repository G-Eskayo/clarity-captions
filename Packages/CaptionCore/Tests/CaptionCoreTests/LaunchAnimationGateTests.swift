import XCTest
@testable import CaptionCore

final class LaunchAnimationGateTests: XCTestCase {
    func testRemainingDelayWhenNothingHasElapsed() {
        XCTAssertEqual(LaunchAnimationGate.remainingDelay(elapsed: 0), 0.5)
    }

    func testRemainingDelayWhenPartialTimeHasElapsed() {
        XCTAssertEqual(LaunchAnimationGate.remainingDelay(elapsed: 0.2), 0.3)
    }

    func testRemainingDelayWhenMinimumHasJustElapsed() {
        XCTAssertEqual(LaunchAnimationGate.remainingDelay(elapsed: 0.5), 0)
    }

    func testRemainingDelayWhenMinimumHasAlreadyElapsed() {
        XCTAssertEqual(LaunchAnimationGate.remainingDelay(elapsed: 1.0), 0)
    }

    func testRemainingDelayWithCustomMinimum() {
        XCTAssertEqual(LaunchAnimationGate.remainingDelay(elapsed: 0.3, minimumDuration: 1.0), 0.7)
    }

    func testRemainingDelayWithCustomMinimumAlreadyElapsed() {
        XCTAssertEqual(LaunchAnimationGate.remainingDelay(elapsed: 1.5, minimumDuration: 1.0), 0)
    }
}

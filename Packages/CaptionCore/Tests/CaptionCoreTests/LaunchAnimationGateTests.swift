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

    // The branded animation must not flash on a quick start: it appears only if getting ready is genuinely slow.
    func testNothingIsShownUntilGettingReadyHasTakenAWhile() {
        XCTAssertEqual(LaunchAnimationGate.delayBeforeShowing(elapsedPreparing: 0), LaunchAnimationGate.showDelay)
        XCTAssertEqual(LaunchAnimationGate.delayBeforeShowing(elapsedPreparing: 0.2), LaunchAnimationGate.showDelay - 0.2, accuracy: 0.0001)
    }

    func testItAppearsOnceGettingReadyHasTakenLongEnough() {
        XCTAssertEqual(LaunchAnimationGate.delayBeforeShowing(elapsedPreparing: LaunchAnimationGate.showDelay), 0)
        XCTAssertEqual(LaunchAnimationGate.delayBeforeShowing(elapsedPreparing: 5), 0)
    }

    func testTheShowDelayIsLongerThanATypicalWarmStart() {
        // A warm start took 0.1 to 0.6 s in device measurements; the animation must not cover that.
        XCTAssertGreaterThanOrEqual(LaunchAnimationGate.showDelay, 0.6)
    }

    func testOnceShownItStaysLongEnoughNotToFlicker() {
        XCTAssertGreaterThanOrEqual(LaunchAnimationGate.minimumDuration, 0.4)
        XCTAssertEqual(LaunchAnimationGate.remainingDelay(elapsed: 0.1), LaunchAnimationGate.minimumDuration - 0.1, accuracy: 0.0001)
    }
}

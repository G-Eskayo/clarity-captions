import XCTest
@testable import CaptionCore

final class BrandMomentTests: XCTestCase {
    let gate = BrandAnimationGate()

    func testNotFinishedBeforeMinimumEvenWhenReady() {
        XCTAssertFalse(gate.isFinished(ready: true, elapsed: 0.0))
        XCTAssertFalse(gate.isFinished(ready: true, elapsed: 0.2))
        XCTAssertFalse(gate.isFinished(ready: true, elapsed: 0.39))
    }

    func testNeverFinishedWhileNotReadyRegardlessOfElapsedTime() {
        XCTAssertFalse(gate.isFinished(ready: false, elapsed: 0.0))
        XCTAssertFalse(gate.isFinished(ready: false, elapsed: 0.4))
        XCTAssertFalse(gate.isFinished(ready: false, elapsed: 1.0))
    }

    func testFinishedExactlyAtTheMinimum() {
        XCTAssertTrue(gate.isFinished(ready: true, elapsed: 0.4))
    }

    func testFinishedAfterMinimum() {
        XCTAssertTrue(gate.isFinished(ready: true, elapsed: 0.5))
        XCTAssertTrue(gate.isFinished(ready: true, elapsed: 1.0))
    }

    func testRemainingDelayCountsDown() {
        XCTAssertEqual(gate.remainingDelay(elapsed: 0.0), 0.4, accuracy: 0.001)
        XCTAssertEqual(gate.remainingDelay(elapsed: 0.2), 0.2, accuracy: 0.001)
        XCTAssertEqual(gate.remainingDelay(elapsed: 0.4), 0.0, accuracy: 0.001)
    }

    func testRemainingDelayNeverNegative() {
        XCTAssertEqual(gate.remainingDelay(elapsed: 0.5), 0.0)
        XCTAssertEqual(gate.remainingDelay(elapsed: 1.0), 0.0)
    }

    func testCustomMinimumDuration() {
        let custom = BrandAnimationGate(minimumDuration: 1.0)
        XCTAssertFalse(custom.isFinished(ready: true, elapsed: 0.9))
        XCTAssertTrue(custom.isFinished(ready: true, elapsed: 1.0))
        XCTAssertEqual(custom.remainingDelay(elapsed: 0.6), 0.4, accuracy: 0.001)
    }

    func testPresentationBasedOnReduceMotion() {
        XCTAssertEqual(BrandAnimationPresentation.for(reduceMotion: false), .animated)
        XCTAssertEqual(BrandAnimationPresentation.for(reduceMotion: true), .calmStatic)
    }
}

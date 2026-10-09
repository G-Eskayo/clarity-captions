import XCTest
@testable import CaptionCore

final class BackgroundReturnTrackerTests: XCTestCase {
    func testBackgroundThenActiveReturnsTrue() {
        var tracker = BackgroundReturnTracker()
        tracker.appDidEnterBackground()
        let result = tracker.appDidBecomeActive()
        XCTAssertTrue(result, "should return true for a real background/active cycle")
    }

    func testActivateWithoutBackgroundReturnsFalse() {
        var tracker = BackgroundReturnTracker()
        let result = tracker.appDidBecomeActive()
        XCTAssertFalse(result, "should return false if never backgrounded")
    }

    func testSecondCycleFiresAgain() {
        var tracker = BackgroundReturnTracker()
        tracker.appDidEnterBackground()
        _ = tracker.appDidBecomeActive()
        tracker.appDidEnterBackground()
        let result = tracker.appDidBecomeActive()
        XCTAssertTrue(result, "second background/active cycle should also fire")
    }

    func testMultipleActivateCallsReturnFalseAfterFirst() {
        var tracker = BackgroundReturnTracker()
        tracker.appDidEnterBackground()
        _ = tracker.appDidBecomeActive()
        let secondResult = tracker.appDidBecomeActive()
        XCTAssertFalse(secondResult, "subsequent activates without background should return false")
    }
}

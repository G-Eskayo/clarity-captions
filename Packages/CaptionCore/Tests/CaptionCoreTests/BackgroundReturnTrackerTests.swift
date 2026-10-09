import XCTest
@testable import CaptionCore

final class BackgroundReturnTrackerTests: XCTestCase {
    func testActiveWithoutBackgroundDoesNotSignalReturn() {
        var tracker = BackgroundReturnTracker()
        let result = tracker.appDidBecomeActive()
        XCTAssertFalse(result)
    }

    func testEnterBackgroundThenBecomeActiveSignalsReturn() {
        var tracker = BackgroundReturnTracker()
        tracker.appDidEnterBackground()
        let result = tracker.appDidBecomeActive()
        XCTAssertTrue(result)
    }

    func testSecondActiveCallWithoutBackgroundDoesNotSignal() {
        var tracker = BackgroundReturnTracker()
        tracker.appDidEnterBackground()
        _ = tracker.appDidBecomeActive()
        let secondResult = tracker.appDidBecomeActive()
        XCTAssertFalse(secondResult)
    }

    func testBackgroundThenActiveThenBackgroundThenActiveSignalsBothReturns() {
        var tracker = BackgroundReturnTracker()
        tracker.appDidEnterBackground()
        let first = tracker.appDidBecomeActive()
        XCTAssertTrue(first)
        tracker.appDidEnterBackground()
        let second = tracker.appDidBecomeActive()
        XCTAssertTrue(second)
    }

    func testMultipleBackgroundCallsThenOneActiveSignalsOnce() {
        var tracker = BackgroundReturnTracker()
        tracker.appDidEnterBackground()
        tracker.appDidEnterBackground()
        let result = tracker.appDidBecomeActive()
        XCTAssertTrue(result)
    }
}

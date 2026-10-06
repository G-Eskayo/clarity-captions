import XCTest
@testable import CaptionCore

final class WordLagTrackerTests: XCTestCase {
    func testFirstSample() {
        var tracker = WordLagTracker()
        let lag = tracker.sample(elapsed: 1.0, audioEnds: [0.5])
        XCTAssertEqual(lag, 0.5)
    }

    func testDeduplicationOfRepeatedEnd() {
        var tracker = WordLagTracker()
        let lag1 = tracker.sample(elapsed: 1.0, audioEnds: [0.5])
        XCTAssertEqual(lag1, 0.5)

        let lag2 = tracker.sample(elapsed: 1.1, audioEnds: [0.5])
        XCTAssertNil(lag2, "Repeated end time should not be re-sampled")
    }

    func testNegativeLag() {
        var tracker = WordLagTracker()
        let lag = tracker.sample(elapsed: 0.3, audioEnds: [0.5])
        XCTAssertEqual(lag, -0.2, "Negative lag is returned as-is, not floored")
    }

    func testNoEnds() {
        var tracker = WordLagTracker()
        let lag = tracker.sample(elapsed: 1.0, audioEnds: [])
        XCTAssertNil(lag)
    }

    func testMaxEndOfBatch() {
        var tracker = WordLagTracker()
        let lag = tracker.sample(elapsed: 2.0, audioEnds: [0.3, 0.7, 0.5])
        XCTAssertEqual(lag, 1.3, "Only the maximum end is sampled")
    }

    func testMultipleBatchesNewEnds() {
        var tracker = WordLagTracker()

        let lag1 = tracker.sample(elapsed: 1.0, audioEnds: [0.3, 0.5])
        XCTAssertEqual(lag1, 0.5)

        let lag2 = tracker.sample(elapsed: 1.5, audioEnds: [0.5, 0.6, 0.8])
        XCTAssertEqual(lag2, 0.7)

        let lag3 = tracker.sample(elapsed: 2.0, audioEnds: [0.3, 0.8])
        XCTAssertNil(lag3, "0.8 was already sampled in previous batch")
    }

    func testReset() {
        var tracker = WordLagTracker()
        _ = tracker.sample(elapsed: 1.0, audioEnds: [0.5])
        tracker.reset()

        let lag = tracker.sample(elapsed: 1.1, audioEnds: [0.5])
        XCTAssertNotNil(lag, "After reset, the same end can be sampled again")
    }
}

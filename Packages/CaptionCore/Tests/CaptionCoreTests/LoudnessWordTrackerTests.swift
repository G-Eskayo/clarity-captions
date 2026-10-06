import XCTest
@testable import CaptionCore

final class LoudnessWordTrackerTests: XCTestCase {
    func testFirstMeasurementIsRetrievable() {
        var tracker = LoudnessWordTracker()
        tracker.feed(span: 0.0...0.5, loudness: -10)
        let level = tracker.measurement(for: 0.0...0.5)
        XCTAssertEqual(level, -10)
    }

    func testDeduplicationAvoidsMeasuringTheSameWordTwice() {
        var tracker = LoudnessWordTracker()
        tracker.feed(span: 0.0...0.5, loudness: -10)
        let level1 = tracker.measurement(for: 0.0...0.5)
        XCTAssertEqual(level1, -10)

        tracker.feed(span: 0.0...0.5, loudness: -8)
        let level2 = tracker.measurement(for: 0.0...0.5)
        XCTAssertNil(level2, "Already-seen span should not be re-measured")
    }

    func testProgressingForwardWorks() {
        var tracker = LoudnessWordTracker()
        tracker.feed(span: 0.0...0.3, loudness: -10)
        tracker.feed(span: 0.3...0.6, loudness: -8)
        tracker.feed(span: 0.6...0.9, loudness: -5)

        let level1 = tracker.measurement(for: 0.0...0.3)
        XCTAssertEqual(level1, -10)

        let level2 = tracker.measurement(for: 0.3...0.6)
        XCTAssertEqual(level2, -8)

        let level3 = tracker.measurement(for: 0.6...0.9)
        XCTAssertEqual(level3, -5)
    }

    func testNoMeasurementYieldsNil() {
        var tracker = LoudnessWordTracker()
        tracker.feed(span: 0.0...0.3, loudness: -10)
        let level = tracker.measurement(for: 0.3...0.6)
        XCTAssertNil(level, "Span not in measurements should return nil")
    }

    func testRegressingBackwardIsRefused() {
        var tracker = LoudnessWordTracker()
        tracker.feed(span: 0.0...0.3, loudness: -10)
        tracker.feed(span: 0.3...0.6, loudness: -8)

        let level1 = tracker.measurement(for: 0.3...0.6)
        XCTAssertEqual(level1, -8)

        tracker.feed(span: 0.0...0.3, loudness: -10)
        let level2 = tracker.measurement(for: 0.0...0.3)
        XCTAssertNil(level2, "Cannot re-measure a span at an earlier audio time")
    }

    func testResetClearsMeasurements() {
        var tracker = LoudnessWordTracker()
        tracker.feed(span: 0.0...0.3, loudness: -10)
        let level1 = tracker.measurement(for: 0.0...0.3)
        XCTAssertEqual(level1, -10)

        tracker.reset()
        tracker.feed(span: 0.0...0.3, loudness: -8)
        let level2 = tracker.measurement(for: 0.0...0.3)
        XCTAssertEqual(level2, -8, "After reset, the same span can be re-measured")
    }

    func testMultipleBatchesInSequence() {
        var tracker = LoudnessWordTracker()

        tracker.feed(span: 0.0...0.2, loudness: -15)
        tracker.feed(span: 0.2...0.4, loudness: -12)
        let level1 = tracker.measurement(for: 0.0...0.2)
        XCTAssertEqual(level1, -15)

        tracker.feed(span: 0.4...0.6, loudness: -8)
        let level2 = tracker.measurement(for: 0.2...0.4)
        XCTAssertEqual(level2, -12)

        tracker.feed(span: 0.6...0.8, loudness: -5)
        let level3 = tracker.measurement(for: 0.4...0.6)
        XCTAssertEqual(level3, -8)

        let level4 = tracker.measurement(for: 0.6...0.8)
        XCTAssertEqual(level4, -5)
    }
}

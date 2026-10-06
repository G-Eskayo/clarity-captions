import XCTest
@testable import CaptionCore

final class LoudnessTests: XCTestCase {
    func testDBFSOnSilenceReturnsFloor() {
        XCTAssertEqual(AudioLevel.dBFS(samples: []), -60.0)
        XCTAssertEqual(AudioLevel.dBFS(samples: [0, 0, 0]), -60.0)
    }

    func testDBFSOnFullScaleFloat() {
        let fullScale = [Float](repeating: 1.0, count: 100)
        let dBFS = AudioLevel.dBFS(samples: fullScale)
        XCTAssertEqual(dBFS, 0.0, accuracy: 0.01)
    }

    func testDBFSOnQuietSignal() {
        let quiet = [Float](repeating: 0.1, count: 100)
        let dBFS = AudioLevel.dBFS(samples: quiet)
        XCTAssertGreaterThan(dBFS, -30.0)
        XCTAssertLessThan(dBFS, -10.0)
    }

    func testTimelineAppendAndQuery() {
        var timeline = LoudnessTimeline()
        timeline.append(timeRange: 0.0...1.0, dBFS: -10.0)
        timeline.append(timeRange: 1.0...2.0, dBFS: -15.0)

        let avg = timeline.averageLevel(in: 0.5...1.5)
        XCTAssertEqual(avg ?? 0, -12.5, accuracy: 0.01)
    }

    func testTimelineQueryWithNoOverlap() {
        var timeline = LoudnessTimeline()
        timeline.append(timeRange: 0.0...1.0, dBFS: -10.0)

        let avg = timeline.averageLevel(in: 2.0...3.0)
        XCTAssertNil(avg)
    }

    func testTimelinePartialOverlap() {
        var timeline = LoudnessTimeline()
        timeline.append(timeRange: 0.0...1.0, dBFS: -10.0)
        timeline.append(timeRange: 0.8...1.8, dBFS: -20.0)

        let avg = timeline.averageLevel(in: 0.5...1.5)
        XCTAssertEqual(avg ?? 0, -15.0, accuracy: 0.01)
    }

    func testBaselineStartsUntrustworthy() {
        var baseline = LoudnessBaseline()
        baseline.feed(-10.0)
        XCTAssertFalse(baseline.isTrusted)
        XCTAssertEqual(baseline.current, -10.0)
    }

    func testBaselineBecomeTrustedAfterMinSamples() {
        var baseline = LoudnessBaseline()
        baseline.feed(-10.0)
        baseline.feed(-11.0)
        XCTAssertFalse(baseline.isTrusted)
        baseline.feed(-12.0)
        XCTAssertTrue(baseline.isTrusted)
    }

    func testBaselineConvergesSlowly() {
        var baseline = LoudnessBaseline()
        baseline.feed(-10.0)
        baseline.feed(-11.0)
        baseline.feed(-12.0)
        let step1 = baseline.current ?? 0
        baseline.feed(-20.0)
        let step2 = baseline.current ?? 0
        XCTAssertGreaterThan(step1, step2)
        XCTAssertGreaterThan(step2, -20.0)
    }

    func testBaselineNilWhenEmpty() {
        let baseline = LoudnessBaseline()
        XCTAssertNil(baseline.current)
    }
}

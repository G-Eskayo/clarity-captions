import XCTest
@testable import CaptionCore

final class WatchCompanionBridgeTests: XCTestCase {
    var bridge = WatchCompanionBridge()
    let now = Date()

    func testFirstUpdateAlwaysSends() {
        let payload = bridge.update(line: "hello", speakerLabel: "Speaker 1", isFinal: false, now: now)
        XCTAssertEqual(payload?.line, "hello")
        XCTAssertEqual(payload?.speakerLabel, "Speaker 1")
    }

    func testIdenticalConsecutiveUpdateIsSuppressed() {
        _ = bridge.update(line: "hello", speakerLabel: "Speaker 1", isFinal: false, now: now)
        let payload2 = bridge.update(line: "hello", speakerLabel: "Speaker 1", isFinal: false, now: now.addingTimeInterval(0.1))
        XCTAssertNil(payload2)
    }

    func testEmptyLineIsNeverSent() {
        let payload = bridge.update(line: "", speakerLabel: "Speaker 1", isFinal: false, now: now)
        XCTAssertNil(payload)
    }

    func testRapidPartialRevisionInsideIntervalIsSuppressed() {
        _ = bridge.update(line: "hel", speakerLabel: "", isFinal: false, now: now)
        let payload2 = bridge.update(line: "hello w", speakerLabel: "", isFinal: false, now: now.addingTimeInterval(0.5))
        XCTAssertNil(payload2)
    }

    func testFinalLineFlushesImmediatelyEvenMidInterval() {
        _ = bridge.update(line: "hel", speakerLabel: "", isFinal: false, now: now)
        let payload2 = bridge.update(line: "hello world", speakerLabel: "", isFinal: true, now: now.addingTimeInterval(0.1))
        XCTAssertEqual(payload2?.line, "hello world")
    }

    func testIdenticalTextWithNewSpeakerLabelStillSends() {
        _ = bridge.update(line: "hello", speakerLabel: "Speaker 1", isFinal: false, now: now)
        let payload2 = bridge.update(line: "hello", speakerLabel: "Speaker 2", isFinal: false, now: now.addingTimeInterval(0.1))
        XCTAssertEqual(payload2?.line, "hello")
        XCTAssertEqual(payload2?.speakerLabel, "Speaker 2")
    }

    func testSendingResumesCorrectlyAfterIdleGap() {
        _ = bridge.update(line: "first", speakerLabel: "", isFinal: false, now: now)
        // After a long idle gap...
        let payload2 = bridge.update(line: "second", speakerLabel: "", isFinal: false, now: now.addingTimeInterval(10))
        XCTAssertEqual(payload2?.line, "second")
    }

    func testThrottleRespectsBridgeMinimumSendInterval() {
        let bridge = WatchCompanionBridge(minimumSendInterval: 2.0)
        var mutable = bridge
        _ = mutable.update(line: "text1", speakerLabel: "", isFinal: false, now: now)
        // 1 second later, still suppressed.
        let payload2 = mutable.update(line: "text2", speakerLabel: "", isFinal: false, now: now.addingTimeInterval(1.0))
        XCTAssertNil(payload2)
        // 2 seconds later, sent.
        let payload3 = mutable.update(line: "text2", speakerLabel: "", isFinal: false, now: now.addingTimeInterval(2.0))
        XCTAssertEqual(payload3?.line, "text2")
    }

    func testEmptySpeakerLabelIsAllowed() {
        let payload = bridge.update(line: "hello", speakerLabel: "", isFinal: false, now: now)
        XCTAssertEqual(payload?.speakerLabel, "")
    }

    func testFinalWithIdenticalTextStillSuppressed() {
        _ = bridge.update(line: "hello", speakerLabel: "Speaker 1", isFinal: false, now: now)
        // Even if marked final, identical text+speaker is suppressed.
        let payload2 = bridge.update(line: "hello", speakerLabel: "Speaker 1", isFinal: true, now: now.addingTimeInterval(0.5))
        XCTAssertNil(payload2)
    }

    func testFinalEmptyLineSendsAsClear() {
        // Send a normal line first.
        _ = bridge.update(line: "hello", speakerLabel: "Speaker 1", isFinal: false, now: now)
        // Then send an empty line marked final (explicit clear).
        let payload2 = bridge.update(line: "", speakerLabel: "", isFinal: true, now: now.addingTimeInterval(0.1))
        XCTAssertNotNil(payload2)
        XCTAssertEqual(payload2?.line, "")
        XCTAssertEqual(payload2?.speakerLabel, "")
    }

    func testConsecutiveFinalEmptyLinesAreDeduplicated() {
        _ = bridge.update(line: "hello", speakerLabel: "Speaker 1", isFinal: false, now: now)
        // First final clear.
        _ = bridge.update(line: "", speakerLabel: "", isFinal: true, now: now.addingTimeInterval(0.1))
        // Second final clear in a row should be suppressed (already cleared).
        let payload3 = bridge.update(line: "", speakerLabel: "", isFinal: true, now: now.addingTimeInterval(0.2))
        XCTAssertNil(payload3)
    }
}

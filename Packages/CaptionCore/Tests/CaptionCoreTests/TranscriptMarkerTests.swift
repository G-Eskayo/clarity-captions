import XCTest
@testable import CaptionCore

final class TranscriptMarkerTests: XCTestCase {
    func testWasAwayEquality() {
        let marker1 = TranscriptMarker.wasAway
        let marker2 = TranscriptMarker.wasAway
        XCTAssertEqual(marker1, marker2)
    }

    func testResumedAfterInterruptionEquality() {
        let marker1 = TranscriptMarker.resumedAfterInterruption
        let marker2 = TranscriptMarker.resumedAfterInterruption
        XCTAssertEqual(marker1, marker2)
    }

    func testDifferentMarkersAreNotEqual() {
        let away = TranscriptMarker.wasAway
        let resumed = TranscriptMarker.resumedAfterInterruption
        XCTAssertNotEqual(away, resumed)
    }

    func testWasAwayCaption() {
        let caption = TranscriptMarkerFormatter.caption(for: .wasAway)
        XCTAssertTrue(caption.contains("away"))
    }

    func testResumedAfterInterruptionCaption() {
        let caption = TranscriptMarkerFormatter.caption(for: .resumedAfterInterruption)
        XCTAssertTrue(caption.contains("missed") || caption.contains("call"))
    }

    func testCodability() {
        let marker = TranscriptMarker.wasAway
        let sendable: TranscriptMarker = marker
        _ = sendable
    }
}

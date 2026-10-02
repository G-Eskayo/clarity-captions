import XCTest
@testable import CaptionCore

final class SpeakerAlignerTests: XCTestCase {
    private func seg(_ speaker: Int, _ start: Double, _ end: Double) -> SpeakerSegment {
        SpeakerSegment(speaker: speaker, start: start, end: end)
    }

    func testPicksTheSpeakerWithTheLargestOverlap() {
        let segs = [seg(0, 0, 2), seg(1, 2, 6)]
        // Caption covers 1.5-5.0: 0.5s of speaker 0, 3.0s of speaker 1.
        XCTAssertEqual(SpeakerAligner.speaker(start: 1.5, end: 5.0, segments: segs), 1)
    }

    func testNoSegmentsMeansNoSpeaker() {
        XCTAssertNil(SpeakerAligner.speaker(start: 0, end: 1, segments: []))
    }

    func testNoOverlapMeansNoSpeaker() {
        XCTAssertNil(SpeakerAligner.speaker(start: 10, end: 11, segments: [seg(0, 0, 2)]))
    }

    func testOverlapIsSummedAcrossASpeakersSeparateSegments() {
        // Speaker 0: 1.2s + 1.0s = 2.2s across two segments; speaker 1: 1.8s in one. Summing makes 0 win.
        let segs = [seg(0, 0, 1.2), seg(1, 1.2, 3), seg(0, 3, 4)]
        XCTAssertEqual(SpeakerAligner.speaker(start: 0, end: 4, segments: segs), 0)
    }

    func testZeroLengthCaptionRangeFallsBackToContainingSegment() {
        let segs = [seg(0, 0, 2), seg(1, 2, 4)]
        XCTAssertEqual(SpeakerAligner.speaker(start: 3.0, end: 3.0, segments: segs), 1)
    }
}

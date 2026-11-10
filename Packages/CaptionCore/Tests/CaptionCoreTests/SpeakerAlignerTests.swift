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

    // Tests for deterministic tie-breaking: equal overlap must pick the same speaker consistently.
    func testEqualOverlapBreaksTieByLowestSlotKey() {
        // Both speakers have exactly 1.0s overlap; speaker 1 should win (lower slot key).
        let segs = [seg(0, 0, 2), seg(1, 1, 3)]
        XCTAssertEqual(SpeakerAligner.speaker(start: 1.0, end: 2.0, segments: segs), 0)
    }

    func testEqualOverlapWithReversedSegmentOrder() {
        // Same as above but segments provided in reverse order: must still pick speaker 0.
        let segs = [seg(1, 1, 3), seg(0, 0, 2)]
        XCTAssertEqual(SpeakerAligner.speaker(start: 1.0, end: 2.0, segments: segs), 0)
    }

    func testEqualOverlapWithThreeSpeakers() {
        // Three speakers all have 1.0s overlap with caption 0.5–2.0; speaker 0 (lowest key) should win.
        // seg(0, 0, 1.5): overlaps 0.5–1.5 = 1.0s
        // seg(1, 1.0, 2.0): overlaps 1.0–2.0 = 1.0s
        // seg(2, 0.5, 1.5): overlaps 0.5–1.5 = 1.0s
        let segs = [seg(0, 0, 1.5), seg(1, 1.0, 2.0), seg(2, 0.5, 1.5)]
        XCTAssertEqual(SpeakerAligner.speaker(start: 0.5, end: 2.0, segments: segs), 0)
    }

    func testEqualOverlapConsistentRegardlessOfSegmentOrder() {
        // Create two sets with same speakers but different insertion order.
        let caption = (start: 0.0, end: 2.0)
        let segsA = [seg(5, 0, 1), seg(3, 1, 2), seg(1, 0.5, 1.5)]
        let segsB = [seg(1, 0.5, 1.5), seg(3, 1, 2), seg(5, 0, 1)]
        // Both should consistently pick speaker 1 (lowest key) since all have 0.5s + 0.5s = 1.0s.
        XCTAssertEqual(SpeakerAligner.speaker(start: caption.start, end: caption.end, segments: segsA), 1)
        XCTAssertEqual(SpeakerAligner.speaker(start: caption.start, end: caption.end, segments: segsB), 1)
    }
}

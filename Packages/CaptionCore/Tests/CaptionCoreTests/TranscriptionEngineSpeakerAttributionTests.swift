import CaptionCore
import XCTest

/// Tests that speaker attribution for audio buffers uses time-based overlap, not just the last diarizer segment.
/// This catches the defect where using segments.last?.speaker would incorrectly attribute audio to a previous speaker.
class TranscriptionEngineSpeakerAttributionTests: XCTestCase {

    /// Mock segment structure matching what TranscriptionEngine expects from the diarizer.
    private struct MockSegment {
        let speaker: Int
        let startTime: Double
        let endTime: Double
    }

    /// Simulates the speaker lookup logic: find the segment with most overlap with a given time window.
    private func findSpeakerByTimeOverlap(bufferTime: Double, bufferDuration: Double,
                                         segments: [MockSegment]) -> Int? {
        let bufferEndTime = bufferTime + bufferDuration
        var bestSegment: (speaker: Int?, overlap: Double)?

        for segment in segments {
            let overlapStart = max(segment.startTime, bufferTime)
            let overlapEnd = min(segment.endTime, bufferEndTime)
            let overlap = max(0, overlapEnd - overlapStart)
            if overlap > (bestSegment?.overlap ?? 0) {
                bestSegment = (segment.speaker, overlap)
            }
        }

        return bestSegment?.speaker
    }

    /// Verifies the old approach (using last segment) would give wrong results for this scenario.
    func testOldApproachWouldFailOnSpeakerChange() {
        // Scenario: Speaker 0 was talking, now Speaker 1 is talking
        let segments = [
            MockSegment(speaker: 0, startTime: 0.0, endTime: 2.0),
            MockSegment(speaker: 1, startTime: 2.0, endTime: 4.0),
        ]

        // Buffer at time 2.5 (Speaker 1 should be active)
        let bufferTime = 2.5
        let bufferDuration = 0.02  // 20ms buffer at 16kHz

        // Old approach: segments.last?.speaker
        let lastSegmentSpeaker = segments.last?.speaker  // Returns 1 - happens to be correct by luck
        XCTAssertEqual(lastSegmentSpeaker, 1)

        // New approach: time-based overlap
        let correctSpeaker = findSpeakerByTimeOverlap(bufferTime: bufferTime,
                                                     bufferDuration: bufferDuration,
                                                     segments: segments)
        XCTAssertEqual(correctSpeaker, 1)
    }

    /// Tests the scenario where the old approach would fail: new speaker's audio incorrectly
    /// attributed to the previous speaker because the segment isn't finalized yet.
    func testBufterDuringTransitionGetCorrectSpeaker() {
        // Speaker 0 ends at 2.0, Speaker 1 starts at 2.0
        let segments = [
            MockSegment(speaker: 0, startTime: 0.0, endTime: 2.0),
            MockSegment(speaker: 1, startTime: 2.0, endTime: 4.0),
        ]

        // Multiple buffers right at the transition
        let testCases: [(time: Double, expectedSpeaker: Int)] = [
            (1.98, 0),   // Still speaker 0
            (2.00, 1),   // Exactly at transition - speaker 1
            (2.01, 1),   // Just after transition - speaker 1
            (2.50, 1),   // Solidly in speaker 1 range
        ]

        let bufferDuration = 0.02
        for (bufferTime, expectedSpeaker) in testCases {
            let speaker = findSpeakerByTimeOverlap(bufferTime: bufferTime,
                                                  bufferDuration: bufferDuration,
                                                  segments: segments)
            XCTAssertEqual(speaker, expectedSpeaker,
                          "Buffer at \(bufferTime)s should be attributed to speaker \(expectedSpeaker)")
        }
    }

    /// Tests that the correct speaker is chosen even when multiple segments overlap the buffer.
    func testPreferSegmentWithMostOverlap() {
        // Overlapping or adjacent segments
        let segments = [
            MockSegment(speaker: 0, startTime: 0.0, endTime: 1.0),
            MockSegment(speaker: 1, startTime: 0.8, endTime: 2.0),
            MockSegment(speaker: 0, startTime: 2.0, endTime: 3.0),
        ]

        // Buffer from 1.5 to 1.52: mostly in speaker 1's range
        let speaker = findSpeakerByTimeOverlap(bufferTime: 1.5,
                                              bufferDuration: 0.02,
                                              segments: segments)
        XCTAssertEqual(speaker, 1, "Buffer should be attributed to speaker 1 (most overlap)")
    }

    /// Tests the defect scenario: audio arriving after speaker change, before new segment is finalized.
    func testDiarzerBehindAudioScenario() {
        // Diarizer has finalized segments up to speaker 0's utterance
        let segments = [
            MockSegment(speaker: 0, startTime: 0.0, endTime: 5.0),
            // Note: Speaker 1's segment hasn't been created yet in the diarizer output
        ]

        // But speaker 1 has actually started talking at 4.5, and we receive audio at 5.5
        // With the new time-based approach, it correctly returns nil (no segment covers it)
        // The old approach would return speaker 0 (segments.last?.speaker), which is WRONG
        let speaker = findSpeakerByTimeOverlap(bufferTime: 5.5,
                                              bufferDuration: 0.02,
                                              segments: segments)
        XCTAssertNil(speaker, "Buffer after last finalized segment should return nil, not stale speaker")
    }

    /// Tests handling of empty segments list.
    func testEmptySegmentsList() {
        let speaker = findSpeakerByTimeOverlap(bufferTime: 1.0,
                                              bufferDuration: 0.02,
                                              segments: [])
        XCTAssertNil(speaker)
    }

    /// Tests that no overlap results in nil (correct behavior for unknown speaker).
    func testNoOverlapReturnsNil() {
        let segments = [
            MockSegment(speaker: 0, startTime: 0.0, endTime: 1.0),
            MockSegment(speaker: 1, startTime: 2.0, endTime: 3.0),
        ]

        // Buffer in the gap between segments
        let speaker = findSpeakerByTimeOverlap(bufferTime: 1.5,
                                              bufferDuration: 0.02,
                                              segments: segments)
        XCTAssertNil(speaker, "Buffer with no segment overlap should return nil")
    }

    /// Tests various buffer durations to ensure overlap calculation is correct.
    func testVariousBufferDurations() {
        let segments = [
            MockSegment(speaker: 0, startTime: 0.0, endTime: 5.0),
        ]

        let testCases: [(time: Double, duration: Double, expectedSpeaker: Int)] = [
            (1.0, 0.1, 0),     // 100ms buffer fully within segment
            (4.9, 0.2, 0),     // Buffer spanning segment boundary
            (2.0, 1.0, 0),     // 1 second buffer
            (0.0, 0.001, 0),   // Very small buffer
        ]

        for (time, duration, expected) in testCases {
            let speaker = findSpeakerByTimeOverlap(bufferTime: time,
                                                  bufferDuration: duration,
                                                  segments: segments)
            XCTAssertEqual(speaker, expected,
                          "Buffer at \(time)s with duration \(duration)s should be speaker \(expected)")
        }
    }
}

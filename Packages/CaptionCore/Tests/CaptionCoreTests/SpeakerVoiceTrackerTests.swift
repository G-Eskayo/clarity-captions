import XCTest
@testable import CaptionCore

final class SpeakerVoiceTrackerTests: XCTestCase {
    func testTrackerStartsWithNoProfiles() {
        var tracker = SpeakerVoiceTracker()
        XCTAssertNil(tracker.traits(forSlot: 0))
        XCTAssertNil(tracker.traits(forSlot: 1))
    }

    func testTrackerFeedsToCorrectSlot() {
        var tracker = SpeakerVoiceTracker()
        let samples = generateTone(hz: 200, duration: 3, sampleRate: 16000, amplitude: 0.1)
        let segment = SpeakerSegment(speaker: 0, start: 0, end: 3)
        tracker.feed(samples: samples, sampleRate: 16000, at: 0, segments: [segment])
        tracker.addLine("hello world this is a test", speechSeconds: 3, language: "en", forSlot: 0)
        XCTAssertNotNil(tracker.traits(forSlot: 0))
    }

    func testTrackerIgnoresNoOverlap() {
        var tracker = SpeakerVoiceTracker()
        let samples = generateTone(hz: 200, duration: 1, sampleRate: 16000, amplitude: 0.1)
        let segment = SpeakerSegment(speaker: 0, start: 5, end: 6)
        tracker.feed(samples: samples, sampleRate: 16000, at: 0, segments: [segment])
        XCTAssertNil(tracker.traits(forSlot: 0))
    }

    func testTrackerChoicesDominantOverlap() {
        var tracker = SpeakerVoiceTracker()
        let samples = generateTone(hz: 200, duration: 2, sampleRate: 16000, amplitude: 0.1)
        let segments = [
            SpeakerSegment(speaker: 0, start: 0, end: 0.5),
            SpeakerSegment(speaker: 1, start: 0.5, end: 2)
        ]
        tracker.feed(samples: samples, sampleRate: 16000, at: 0, segments: segments)
        tracker.addLine("hello world this is a test", speechSeconds: 1.5, language: "en", forSlot: 1)
        XCTAssertNil(tracker.traits(forSlot: 0))
        XCTAssertNotNil(tracker.traits(forSlot: 1))
    }

    func testTrackerAddLine() {
        var tracker = SpeakerVoiceTracker()
        let samples = generateTone(hz: 200, duration: 2, sampleRate: 16000, amplitude: 0.1)
        let segment = SpeakerSegment(speaker: 0, start: 0, end: 2)
        tracker.feed(samples: samples, sampleRate: 16000, at: 0, segments: [segment])
        tracker.addLine("hello world", speechSeconds: 2, language: "en", forSlot: 0)
        let traits = tracker.traits(forSlot: 0)
        XCTAssertNotNil(traits)
        XCTAssertGreaterThan(traits!.syllablesPerSecond, 0)
    }

    func testTrackerMultipleSlots() {
        var tracker = SpeakerVoiceTracker()
        let samples1 = generateTone(hz: 150, duration: 3, sampleRate: 16000, amplitude: 0.1)
        let samples2 = generateTone(hz: 250, duration: 3, sampleRate: 16000, amplitude: 0.1)
        let segment1 = SpeakerSegment(speaker: 0, start: 0, end: 3)
        let segment2 = SpeakerSegment(speaker: 1, start: 3, end: 6)

        tracker.feed(samples: samples1, sampleRate: 16000, at: 0, segments: [segment1])
        tracker.addLine("first speaker hello world", speechSeconds: 3, language: "en", forSlot: 0)
        tracker.feed(samples: samples2, sampleRate: 16000, at: 3, segments: [segment2])
        tracker.addLine("second speaker hello world", speechSeconds: 3, language: "en", forSlot: 1)

        let traits0 = tracker.traits(forSlot: 0)
        let traits1 = tracker.traits(forSlot: 1)
        XCTAssertNotNil(traits0)
        XCTAssertNotNil(traits1)
    }

    func testTrackerIgnoresInvalidSampleRate() {
        var tracker = SpeakerVoiceTracker()
        let samples = generateTone(hz: 200, duration: 1, sampleRate: 3000, amplitude: 0.1)
        let segment = SpeakerSegment(speaker: 0, start: 0, end: 1)
        tracker.feed(samples: samples, sampleRate: 3000, at: 0, segments: [segment])
        XCTAssertNil(tracker.traits(forSlot: 0))
    }

    func testTrackerIgnoresEmptySamples() {
        var tracker = SpeakerVoiceTracker()
        let segment = SpeakerSegment(speaker: 0, start: 0, end: 1)
        tracker.feed(samples: [], sampleRate: 16000, at: 0, segments: [segment])
        XCTAssertNil(tracker.traits(forSlot: 0))
    }

    private func generateTone(hz: Double, duration: Double, sampleRate: Double, amplitude: Float) -> [Float] {
        let samplesCount = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: samplesCount)
        for i in 0..<samplesCount {
            let t = Double(i) / sampleRate
            let sine = sin(2 * .pi * hz * t)
            samples[i] = Float(sine) * amplitude
        }
        return samples
    }
}

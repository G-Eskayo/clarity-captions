@testable import CaptionCore
import Foundation
import Testing

@Suite struct SpeakerVoiceTrackerTests {
    @Test func emptyTraitsByDefault() {
        let tracker = SpeakerVoiceTracker()
        #expect(tracker.traits.isEmpty)
    }

    @Test func feedWithEmptySamplesDoesNothing() {
        let tracker = SpeakerVoiceTracker()
        let segments: [SpeakerSegment] = []
        tracker.feed([], sampleRate: 16000, bufferStartTime: 0, segments: segments)
        #expect(tracker.traits.isEmpty)
    }

    @Test func addLineWithoutSpeakerDoesNothing() {
        let tracker = SpeakerVoiceTracker()
        tracker.addLine(speaker: nil, text: "Hello world", speechSeconds: 1.0)
        #expect(tracker.traits.isEmpty)
    }

    @Test func addLineWithZeroSecondsDoesNothing() {
        let tracker = SpeakerVoiceTracker()
        tracker.addLine(speaker: 0, text: "Hello world", speechSeconds: 0)
        #expect(tracker.traits.isEmpty)
    }

    @Test func addLineEstimatesSpeechRate() {
        let tracker = SpeakerVoiceTracker()
        tracker.addLine(speaker: 0, text: "one two three four five", speechSeconds: 1.0)

        let traits = tracker.traits
        #expect(traits[0] != nil)
        #expect(traits[0]?.speaker == 0)
        #expect(traits[0]?.speechRate == 5.0)
    }

    @Test func addLineMultipleSamplesAverageRate() {
        let tracker = SpeakerVoiceTracker()
        tracker.addLine(speaker: 0, text: "one two three four five", speechSeconds: 1.0)
        tracker.addLine(speaker: 0, text: "one two three", speechSeconds: 1.0)

        let traits = tracker.traits
        #expect(traits[0] != nil)
        #expect(traits[0]?.speechRate == 4.0)
    }

    @Test func multipleSpokersTrackedSeparately() {
        let tracker = SpeakerVoiceTracker()
        tracker.addLine(speaker: 0, text: "one two three four five", speechSeconds: 1.0)
        tracker.addLine(speaker: 1, text: "one two three", speechSeconds: 1.0)

        let traits = tracker.traits
        #expect(traits[0]?.speechRate == 5.0)
        #expect(traits[1]?.speechRate == 3.0)
    }

    @Test func feedEstimatesPitch() {
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000
        let frequency = 200.0
        let duration = 0.05
        let samples = generateSineWave(frequency: frequency, sampleRate: sampleRate, duration: duration)

        let segment = SpeakerSegment(speaker: 0, start: 0, end: duration)
        tracker.feed(samples, sampleRate: sampleRate, bufferStartTime: 0, segments: [segment])

        let traits = tracker.traits
        #expect(traits[0] != nil)
        #expect(traits[0]?.pitchHz != nil)
    }

    @Test func feedWithOutOfBoundsSegmentIgnored() {
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000
        let samples = Array(repeating: Float(0), count: 1000)

        let outOfBoundsSegment = SpeakerSegment(speaker: 0, start: 100, end: 200)
        tracker.feed(samples, sampleRate: sampleRate, bufferStartTime: 0, segments: [outOfBoundsSegment])

        #expect(tracker.traits.isEmpty)
    }

    @Test func feedHandlesSessionAbsoluteSegmentTimes() {
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000
        let frequency = 200.0
        let bufferDuration = 0.05

        let samples = generateSineWave(frequency: frequency, sampleRate: sampleRate, duration: bufferDuration)

        let bufferStartTime = 0.5
        let segment = SpeakerSegment(speaker: 0, start: bufferStartTime, end: bufferStartTime + bufferDuration)
        tracker.feed(samples, sampleRate: sampleRate, bufferStartTime: bufferStartTime, segments: [segment])

        let traits = tracker.traits
        #expect(traits[0] != nil)
        #expect(traits[0]?.pitchHz != nil)
    }

    @Test func feedHandlesSessionAbsoluteSegmentTimesCorrectlyWithMultipleBuffers() {
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000
        let frequency = 200.0
        let bufferDuration = 0.05

        let buffer1Samples = generateSineWave(frequency: frequency, sampleRate: sampleRate, duration: bufferDuration)
        let buffer2Samples = generateSineWave(frequency: frequency, sampleRate: sampleRate, duration: bufferDuration)

        let buffer1StartTime = 0.0
        let buffer2StartTime = bufferDuration

        let segment1 = SpeakerSegment(speaker: 0, start: buffer1StartTime, end: buffer1StartTime + bufferDuration)
        let segment2 = SpeakerSegment(speaker: 0, start: buffer2StartTime, end: buffer2StartTime + bufferDuration)

        tracker.feed(buffer1Samples, sampleRate: sampleRate, bufferStartTime: buffer1StartTime, segments: [segment1])
        tracker.feed(buffer2Samples, sampleRate: sampleRate, bufferStartTime: buffer2StartTime, segments: [segment2])

        let traits = tracker.traits
        #expect(traits[0] != nil)
        #expect(traits[0]?.pitchHz != nil)
    }

    @Test func addLineBoundsRateSamples() {
        let tracker = SpeakerVoiceTracker()
        for _ in 0..<250 {
            tracker.addLine(speaker: 0, text: "one two three", speechSeconds: 1.0)
        }

        let traits = tracker.traits
        #expect(traits[0] != nil)
        #expect(traits[0]?.speechRate != nil)
    }

    @Test func feedDetectsLowMaleVoices() {
        // Test that pitch detection covers low male voices (~85-180 Hz).
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000
        let frequency = 100.0  // Low male voice
        let duration = 0.05
        let samples = generateSineWave(frequency: frequency, sampleRate: sampleRate, duration: duration)

        let segment = SpeakerSegment(speaker: 0, start: 0, end: duration)
        tracker.feed(samples, sampleRate: sampleRate, bufferStartTime: 0, segments: [segment])

        let traits = tracker.traits
        #expect(traits[0] != nil)
        #expect(traits[0]?.pitchHz != nil)
        // Should detect close to the input frequency (with some autocorrelation error tolerated).
        if let detected = traits[0]?.pitchHz {
            #expect(detected > 80 && detected < 120, "Expected ~100 Hz, got \(detected) Hz")
        }
    }

    @Test func feedDetectsFemaleVoices() {
        // Test that pitch detection covers female voices (~165-255 Hz).
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000
        let frequency = 200.0  // Female voice
        let duration = 0.05
        let samples = generateSineWave(frequency: frequency, sampleRate: sampleRate, duration: duration)

        let segment = SpeakerSegment(speaker: 0, start: 0, end: duration)
        tracker.feed(samples, sampleRate: sampleRate, bufferStartTime: 0, segments: [segment])

        let traits = tracker.traits
        #expect(traits[0] != nil)
        #expect(traits[0]?.pitchHz != nil)
        if let detected = traits[0]?.pitchHz {
            #expect(detected > 180 && detected < 220, "Expected ~200 Hz, got \(detected) Hz")
        }
    }

    @Test func feedDetectsChildVoices() {
        // Test that pitch detection covers child voices (~250-400 Hz).
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000
        let frequency = 300.0  // Child voice
        let duration = 0.05
        let samples = generateSineWave(frequency: frequency, sampleRate: sampleRate, duration: duration)

        let segment = SpeakerSegment(speaker: 0, start: 0, end: duration)
        tracker.feed(samples, sampleRate: sampleRate, bufferStartTime: 0, segments: [segment])

        let traits = tracker.traits
        #expect(traits[0] != nil)
        #expect(traits[0]?.pitchHz != nil)
        if let detected = traits[0]?.pitchHz {
            #expect(detected > 270 && detected < 330, "Expected ~300 Hz, got \(detected) Hz")
        }
    }

    @Test func remapSpeakerUpdatesTraitsCorrectly() {
        // Test that remapping speaker IDs correctly consolidates pitch and rate data.
        let tracker = SpeakerVoiceTracker()

        // Feed pitch for speaker 0 (raw diarizer ID).
        let sampleRate = 16000
        let frequency = 200.0
        let duration = 0.05
        let samples = generateSineWave(frequency: frequency, sampleRate: sampleRate, duration: duration)
        let segment = SpeakerSegment(speaker: 0, start: 0, end: duration)
        tracker.feed(samples, sampleRate: sampleRate, bufferStartTime: 0, segments: [segment])

        // Add rate for speaker 2 (smoothed speaker ID), before remapping.
        tracker.addLine(speaker: 2, text: "one two three four five", speechSeconds: 1.0)

        var traits = tracker.traits
        #expect(traits[0]?.pitchHz != nil)  // Pitch under raw ID 0
        #expect(traits[2]?.speechRate == 5.0)  // Rate under smoothed ID 2
        #expect(traits[0]?.speechRate == nil)  // No rate under raw ID yet

        // Remap speaker 0 -> 2 (consolidate to smoothed ID).
        tracker.remapSpeaker(from: 0, to: 2)

        traits = tracker.traits
        #expect(traits[0] == nil, "Raw speaker 0 should be gone after remap")
        #expect(traits[2] != nil, "Smoothed speaker 2 should have both pitch and rate")
        #expect(traits[2]?.pitchHz != nil, "Should have pitch after remap")
        #expect(traits[2]?.speechRate == 5.0, "Should have rate after remap")
    }

    private func generateSineWave(frequency: Double, sampleRate: Int, duration: Double) -> [Float] {
        let numSamples = Int(Double(sampleRate) * duration)
        var samples: [Float] = []
        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            let value = Float(sin(2 * .pi * frequency * t)) * 0.5
            samples.append(value)
        }
        return samples
    }
}

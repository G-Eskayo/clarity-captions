@testable import CaptionCore
import Foundation
import Testing

@Suite(.serialized) struct SpeakerVoiceTests {
    @Test func matchReturnsNilWithoutCalibration() {
        VoiceMatch.spanishCalibration = nil
        let traits: [Int: SpeakerTraits] = [0: SpeakerTraits(speaker: 0, pitchHz: 200, speechRate: 2.5)]
        #expect(VoiceMatch.match(speaker: 0, from: traits, language: "es") == nil)
    }

    @Test func matchReturnsNilForNonSpanish() {
        VoiceMatch.spanishCalibration = [VoiceCalibration(pitchSemitones: -5, rateMultiplier: 0.95)]
        let traits: [Int: SpeakerTraits] = [0: SpeakerTraits(speaker: 0, pitchHz: 200, speechRate: 2.5)]
        #expect(VoiceMatch.match(speaker: 0, from: traits, language: "en") == nil)
    }

    @Test func matchReturnsNilWhenSpeakerNotInTraits() {
        VoiceMatch.spanishCalibration = [VoiceCalibration(pitchSemitones: -5, rateMultiplier: 0.95)]
        let traits: [Int: SpeakerTraits] = [:]
        #expect(VoiceMatch.match(speaker: 0, from: traits, language: "es") == nil)
    }

    @Test func matchReturnsNilWhenSpeakerIndexOutOfBounds() {
        VoiceMatch.spanishCalibration = [VoiceCalibration(pitchSemitones: -5, rateMultiplier: 0.95)]
        let traits: [Int: SpeakerTraits] = [0: SpeakerTraits(speaker: 0, pitchHz: 200, speechRate: 2.5)]
        #expect(VoiceMatch.match(speaker: 5, from: traits, language: "es") == nil)
    }

    @Test func matchComputesPitchAndRate() {
        VoiceMatch.spanishCalibration = [
            VoiceCalibration(pitchSemitones: 0, rateMultiplier: 1.0),
            VoiceCalibration(pitchSemitones: 12, rateMultiplier: 1.2),
            VoiceCalibration(pitchSemitones: -12, rateMultiplier: 0.8)
        ]
        // Use measured traits that match what high-pitch calibration would produce.
        // High-pitch calibration (12 semitones = 2x pitch multiplier): 170*2=340 Hz baseline
        // Rate 1.2 multiplier: 2.0*1.2=2.4 wps
        // So a speaker with high measured traits should match the high-pitch calibration.
        let traits: [Int: SpeakerTraits] = [
            0: SpeakerTraits(speaker: 0, pitchHz: 100, speechRate: 2.0),  // low pitch, normal rate -> [2]
            1: SpeakerTraits(speaker: 1, pitchHz: 300, speechRate: 2.4)   // high pitch, faster rate -> [1]
        ]

        let match = VoiceMatch.match(speaker: 1, from: traits, language: "es")
        #expect(match != nil)
        #expect(match?.pitch == 2.0)
        #expect(match?.rate == 1.2)
    }

    @Test func matchHandlesNegativePitchAdjustment() {
        VoiceMatch.spanishCalibration = [VoiceCalibration(pitchSemitones: -12, rateMultiplier: 0.9)]
        let traits: [Int: SpeakerTraits] = [0: SpeakerTraits(speaker: 0, pitchHz: 200, speechRate: 2.5)]

        let match = VoiceMatch.match(speaker: 0, from: traits, language: "es")
        #expect(match != nil)
        #expect(match?.pitch == 0.5)
        #expect(match?.rate == 0.9)
    }

    @Test func speakerTraitsCanBeCreated() {
        let traits = SpeakerTraits(speaker: 0, pitchHz: 150.5, speechRate: 3.2)
        #expect(traits.speaker == 0)
        #expect(traits.pitchHz == 150.5)
        #expect(traits.speechRate == 3.2)
    }

    @Test func speakerTraitsCanHaveNilValues() {
        let traits = SpeakerTraits(speaker: 1, pitchHz: nil, speechRate: nil)
        #expect(traits.speaker == 1)
        #expect(traits.pitchHz == nil)
        #expect(traits.speechRate == nil)
    }

    @Test func matchUsesTraitsNotSlotIndexForSelection() {
        // This test verifies that match selects calibrations based on measured voice, not speaker slot.
        // Three calibrations for different voice types: deep (slot 0), bright (slot 1), high (slot 2).
        VoiceMatch.spanishCalibration = [
            VoiceCalibration(pitchSemitones: -5, rateMultiplier: 0.9),   // deep voice
            VoiceCalibration(pitchSemitones: 0, rateMultiplier: 1.0),     // neutral
            VoiceCalibration(pitchSemitones: +5, rateMultiplier: 1.1)     // bright/high
        ]

        // Speaker 0 (measured high pitch) should get bright calibration, NOT deep calibration at slot 0.
        let highPitchTraits: [Int: SpeakerTraits] = [
            0: SpeakerTraits(speaker: 0, pitchHz: 250, speechRate: 2.5)   // high pitch
        ]
        let highMatch = VoiceMatch.match(speaker: 0, from: highPitchTraits, language: "es")
        #expect(highMatch != nil)
        // Should use calibration with higher pitch adjustment, not the slot-0 deep adjustment.
        #expect(highMatch?.pitch == pow(2.0, 5.0 / 12.0))  // +5 semitones, not -5

        // Speaker 1 (measured low pitch) should get deep calibration, even though slot 1 is neutral.
        let lowPitchTraits: [Int: SpeakerTraits] = [
            1: SpeakerTraits(speaker: 1, pitchHz: 80, speechRate: 2.0)    // low pitch
        ]
        let lowMatch = VoiceMatch.match(speaker: 1, from: lowPitchTraits, language: "es")
        #expect(lowMatch != nil)
        // Should use calibration with lower pitch adjustment, matching the measured low pitch.
        #expect(lowMatch?.pitch == pow(2.0, -5.0 / 12.0))  // -5 semitones, not 0
    }

    @Test func matchWithoutTraitsUsesSlotIndexForBackwardsCompatibility() {
        VoiceMatch.spanishCalibration = [
            VoiceCalibration(pitchSemitones: -3, rateMultiplier: 0.95),
            VoiceCalibration(pitchSemitones: 2, rateMultiplier: 1.05)
        ]
        // When traits exist but have no pitch/rate measurements, fall back to slot-based indexing.
        let traitsWithoutPitch: [Int: SpeakerTraits] = [
            0: SpeakerTraits(speaker: 0, pitchHz: nil, speechRate: nil)
        ]
        let match = VoiceMatch.match(speaker: 0, from: traitsWithoutPitch, language: "es")
        #expect(match != nil)
        #expect(match?.pitch == pow(2.0, -3.0 / 12.0))  // Uses slot 0
    }
}

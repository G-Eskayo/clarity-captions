@testable import CaptionCore
import Foundation
import Testing

@Suite struct ShippedVoiceCalibrationTests {
    @Test func spanishCalibrationLoadsAndValidates() throws {
        guard let fixtureURL = Bundle.module.url(forResource: "voice-match-mac", withExtension: "json", subdirectory: "Fixtures") else {
            #expect(false, "Could not locate voice-match-mac.json fixture")
            return
        }

        let data = try Data(contentsOf: fixtureURL)
        let calibration = try JSONDecoder().decode([VoiceCalibration].self, from: data)

        #expect(calibration.count == 4, "Expected 4 speakers in calibration")
        for (i, cal) in calibration.enumerated() {
            #expect(cal.pitchSemitones >= -12 && cal.pitchSemitones <= 12, "Speaker \(i): pitch out of range")
            #expect(cal.rateMultiplier > 0.5 && cal.rateMultiplier < 2.0, "Speaker \(i): rate out of range")
        }
    }

    @Test func voiceCalibrationCanBeEncoded() throws {
        let cal = VoiceCalibration(pitchSemitones: -3, rateMultiplier: 0.95)
        let encoded = try JSONEncoder().encode(cal)
        let decoded = try JSONDecoder().decode(VoiceCalibration.self, from: encoded)
        #expect(decoded == cal)
    }

    @Test func voiceCalibrationArrayCanBeRoundTripped() throws {
        let calibrations = [
            VoiceCalibration(pitchSemitones: 0, rateMultiplier: 1.0),
            VoiceCalibration(pitchSemitones: -12, rateMultiplier: 0.8)
        ]
        let encoded = try JSONEncoder().encode(calibrations)
        let decoded = try JSONDecoder().decode([VoiceCalibration].self, from: encoded)
        #expect(decoded == calibrations)
    }

    @Test func spanishCalibrationCanBeLoadedFromFixture() throws {
        // Verify that the shipped calibration file can be found and loaded.
        guard let fixtureURL = Bundle.module.url(forResource: "voice-match-mac", withExtension: "json", subdirectory: "Fixtures") else {
            #expect(false, "Fixture not found; Bundle.module may not be properly configured in Package.swift")
            return
        }

        let data = try Data(contentsOf: fixtureURL)
        let calibration = try JSONDecoder().decode([VoiceCalibration].self, from: data)
        #expect(!calibration.isEmpty, "Calibration should not be empty")

        // Simulate app initialization loading the calibration.
        VoiceMatch.spanishCalibration = calibration
        #expect(VoiceMatch.spanishCalibration != nil, "Calibration should be assigned and non-nil")

        // Verify it's usable for matching.
        let traits: [Int: SpeakerTraits] = [0: SpeakerTraits(speaker: 0, pitchHz: 150, speechRate: 2.0)]
        let match = VoiceMatch.match(speaker: 0, from: traits, language: "es")
        #expect(match != nil, "Should be able to match after loading calibration")
    }
}

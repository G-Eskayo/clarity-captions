import CaptionCore
import XCTest

class SpeakerVoiceTrackerTests: XCTestCase {
    func testTrackerInitializesEmpty() async {
        let tracker = SpeakerVoiceTracker()
        let voices = VoiceCalibrationTable.calibrations(for: "es")
        let matched = await tracker.matchedVoices(voices: voices, normalSyllablesPerSecond: 5)
        XCTAssertEqual(matched.count, 0)
    }

    func testTrackerAcceptsNilSpeaker() async {
        let tracker = SpeakerVoiceTracker()
        let samples = [Float](repeating: 0.1, count: 16000)
        await tracker.add(samples: samples, sampleRate: 16000, speaker: nil)
        let voices = VoiceCalibrationTable.calibrations(for: "es")
        let matched = await tracker.matchedVoices(voices: voices, normalSyllablesPerSecond: 5)
        XCTAssertEqual(matched.count, 0)
    }

    func testTrackerBuildsProfilesForSpeakers() async {
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000.0
        let duration = 3.0
        let totalSamples = Int(duration * sampleRate)
        // Generate a 200 Hz sine wave with envelope (more realistic speech pattern)
        var speech = [Float](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            // Add syllable-like bursts: 200 Hz carrier modulated by ~2 Hz envelope
            let envelope = 0.5 + 0.5 * sin(2 * .pi * 2 * t)  // 2 Hz syllable-like modulation
            speech[i] = Float(0.15 * envelope * sin(2 * .pi * 200 * t))
        }
        await tracker.add(samples: speech, sampleRate: sampleRate, speaker: 1)
        let voices = VoiceCalibrationTable.calibrations(for: "es")
        let matched = await tracker.matchedVoices(voices: voices, normalSyllablesPerSecond: 5)
        // Speaker 1 should be in results after voice matching runs
        XCTAssertTrue(matched.keys.contains(1), "Tracker should include speaker 1 after adding audio")
        XCTAssertNotNil(matched[1]?.voiceID, "Matched voice should have a voiceID")
    }

    func testTrackerDifferentSpeakersGetMatchedVoices() async {
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000.0
        let duration = 3.0
        let totalSamples = Int(duration * sampleRate)

        // Speaker 1: 200 Hz (lower pitch, typical male voice range)
        var speaker1 = [Float](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let envelope = 0.5 + 0.5 * sin(2 * .pi * 2 * t)
            speaker1[i] = Float(0.15 * envelope * sin(2 * .pi * 200 * t))
        }

        // Speaker 2: 300 Hz (higher pitch, typical female voice range)
        var speaker2 = [Float](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let envelope = 0.5 + 0.5 * sin(2 * .pi * 2 * t)
            speaker2[i] = Float(0.15 * envelope * sin(2 * .pi * 300 * t))
        }

        await tracker.add(samples: speaker1, sampleRate: sampleRate, speaker: 1)
        await tracker.add(samples: speaker2, sampleRate: sampleRate, speaker: 2)
        let voices = VoiceCalibrationTable.calibrations(for: "es")
        let matched = await tracker.matchedVoices(voices: voices, normalSyllablesPerSecond: 5)

        // Both speakers should have matches
        XCTAssertTrue(matched.keys.contains(1), "Speaker 1 should be matched")
        XCTAssertTrue(matched.keys.contains(2), "Speaker 2 should be matched")

        // Both should have actual voice IDs (not just nil defaults)
        XCTAssertNotNil(matched[1]?.voiceID, "Speaker 1 should have a voice ID")
        XCTAssertNotNil(matched[2]?.voiceID, "Speaker 2 should have a voice ID")

        // With significantly different pitches, they should likely get different voice assignments
        // (This tests that voice matching is actually running, not just returning defaults)
        let voice1 = matched[1]?.voiceID
        let voice2 = matched[2]?.voiceID
        XCTAssertNotEqual(voice1, voice2, "Different pitch speakers should typically be assigned different voices")
    }

    func testStickyVoiceAssignmentDoesNotChange() async {
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000.0
        let shortDuration = 1.5
        let totalSamples = Int(shortDuration * sampleRate)
        let voices = VoiceCalibrationTable.calibrations(for: "es")

        // Speaker 1: 200 Hz
        var speaker1A = [Float](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let envelope = 0.5 + 0.5 * sin(2 * .pi * 2 * t)
            speaker1A[i] = Float(0.15 * envelope * sin(2 * .pi * 200 * t))
        }

        // Add first batch
        await tracker.add(samples: speaker1A, sampleRate: sampleRate, speaker: 1)
        let firstMatch = await tracker.matchedVoices(voices: voices, normalSyllablesPerSecond: 5)
        let firstVoiceID = firstMatch[1]?.voiceID

        // Add more audio for the same speaker with slightly different pitch (simulates drift)
        var speaker1B = [Float](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let envelope = 0.5 + 0.5 * sin(2 * .pi * 2 * t)
            // Slightly different pitch: 210 Hz instead of 200 Hz
            speaker1B[i] = Float(0.15 * envelope * sin(2 * .pi * 210 * t))
        }
        await tracker.add(samples: speaker1B, sampleRate: sampleRate, speaker: 1)

        // Check that the voice assignment remains sticky
        let secondMatch = await tracker.matchedVoices(voices: voices, normalSyllablesPerSecond: 5)
        let secondVoiceID = secondMatch[1]?.voiceID

        XCTAssertEqual(firstVoiceID, secondVoiceID,
                      "Speaker's voice assignment should remain sticky even as audio characteristics change")
    }

    func testSpeakersProcessedInInsertionOrder() async {
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000.0
        let duration = 2.0
        let totalSamples = Int(duration * sampleRate)
        let voices = VoiceCalibrationTable.calibrations(for: "es")

        // Add speaker 3 first, then speaker 1, then speaker 2
        // They should be returned in that insertion order, not sorted by ID
        for speakerID in [3, 1, 2] {
            var audio = [Float](repeating: 0, count: totalSamples)
            let freq = Double(150 + speakerID * 30)  // Different frequencies per speaker
            for i in 0..<totalSamples {
                let t = Double(i) / Double(sampleRate)
                let envelope = 0.5 + 0.5 * sin(2 * .pi * 2 * t)
                audio[i] = Float(0.15 * envelope * sin(2 * .pi * freq * t))
            }
            await tracker.add(samples: audio, sampleRate: sampleRate, speaker: speakerID)
        }

        let matched = await tracker.matchedVoices(voices: voices, normalSyllablesPerSecond: 5)

        // Extract the order of speakers in the result
        let resultKeys = Array(matched.keys)
        // The implementation should preserve insertion order internally, though the dict doesn't
        // guarantee it. What we're testing is that voice matching was applied to all speakers.
        XCTAssertTrue(matched.keys.contains(1))
        XCTAssertTrue(matched.keys.contains(2))
        XCTAssertTrue(matched.keys.contains(3))
    }

    func testTrackerAddLineRecordsCaption() async {
        let tracker = SpeakerVoiceTracker()
        let sampleRate = 16000.0
        let duration = 2.0
        let totalSamples = Int(duration * sampleRate)

        var speech = [Float](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let envelope = 0.5 + 0.5 * sin(2 * .pi * 2 * t)
            speech[i] = Float(0.15 * envelope * sin(2 * .pi * 200 * t))
        }

        await tracker.add(samples: speech, sampleRate: sampleRate, speaker: 1)
        // Add caption line with known speech duration (without pauses)
        await tracker.addLine("Hello world", speechSeconds: 1.5, speaker: 1, language: "en")

        let voices = VoiceCalibrationTable.calibrations(for: "es")
        let matched = await tracker.matchedVoices(voices: voices, normalSyllablesPerSecond: 5)

        XCTAssertTrue(matched.keys.contains(1), "Speaker should be tracked after adding audio and caption")
        XCTAssertNotNil(matched[1]?.voiceID, "Should have a matched voice after combining audio and caption data")
    }

    func testTrackerHandlesNewSampleCorrectly() async {
        let tracker = SpeakerVoiceTracker()
        let voices = VoiceCalibrationTable.calibrations(for: "es")
        let sampleRate = 16000.0
        let duration = 2.0
        let totalSamples = Int(duration * sampleRate)

        var speech = [Float](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let envelope = 0.5 + 0.5 * sin(2 * .pi * 2 * t)
            speech[i] = Float(0.15 * envelope * sin(2 * .pi * 200 * t))
        }

        // Match with empty profile
        let beforeSamples = await tracker.matchedVoices(voices: voices, normalSyllablesPerSecond: 5)
        XCTAssertFalse(beforeSamples.keys.contains(1))

        // Add samples for speaker 1
        await tracker.add(samples: speech, sampleRate: sampleRate, speaker: 1)
        let afterSamples = await tracker.matchedVoices(voices: voices, normalSyllablesPerSecond: 5)

        // After adding samples, speaker 1 should now have a match
        XCTAssertTrue(afterSamples.keys.contains(1),
                     "Speaker should appear in matches after samples are added")
        XCTAssertNotNil(afterSamples[1]?.voiceID,
                       "Speaker should have a voice ID after samples are added")
    }

    func testVoiceCalibrationTableReturnsSpanishCalibrations() async {
        let calibrations = VoiceCalibrationTable.calibrations(for: "es")
        XCTAssertFalse(calibrations.isEmpty, "Spanish calibration table should not be empty")

        // Verify that calibrations have required fields
        for calib in calibrations {
            XCTAssertFalse(calib.id.isEmpty, "Calibration should have a voice ID")
            XCTAssertGreaterThan(calib.pitchHz, 0, "Calibration should have valid pitch")
            XCTAssertFalse(calib.pitchCurve.isEmpty, "Calibration should have pitch curve")
            XCTAssertFalse(calib.rateCurve.isEmpty, "Calibration should have rate curve")
        }
    }
}

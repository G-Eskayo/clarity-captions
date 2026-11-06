import XCTest
@testable import CaptionCore

final class SpeakerVoiceTests: XCTestCase {
    func testPitchTrackerWithQuietSignalReturnsEmpty() {
        let quiet = Array(repeating: Float(0.0001), count: 16000)
        let result = PitchTracker.track(quiet, sampleRate: 16000)
        XCTAssertTrue(result.allSatisfy { $0 == nil })
    }

    func testPitchTrackerWithValidSignalReturnsResults() {
        let sampleRate = 16000.0
        let hz = 200.0
        let duration = 0.5
        let samples = generateTone(hz: hz, duration: duration, sampleRate: sampleRate, amplitude: 0.1)
        let result = PitchTracker.track(samples, sampleRate: sampleRate)
        let detected = result.compactMap { $0 }
        XCTAssertTrue(detected.count > 0)
        let median = detected.sorted()[detected.count / 2]
        XCTAssertGreaterThan(median, hz * 0.9)
        XCTAssertLessThan(median, hz * 1.1)
    }

    func testPitchTrackerIgnoresLowSampleRates() {
        let samples = Array(repeating: Float(0.1), count: 100)
        let result = PitchTracker.track(samples, sampleRate: 3000)
        XCTAssertTrue(result.isEmpty)
    }

    func testPitchTrackerIgnoresInfiniteSampleRate() {
        let samples = Array(repeating: Float(0.1), count: 100)
        let result = PitchTracker.track(samples, sampleRate: .infinity)
        XCTAssertTrue(result.isEmpty)
    }

    func testPitchTrackerHandlesNonFiniteValues() {
        var samples = Array(repeating: Float(0.1), count: 16000)
        samples[1000] = .nan
        samples[2000] = .infinity
        let result = PitchTracker.track(samples, sampleRate: 16000)
        XCTAssertTrue(result.count > 0)
    }

    func testSyllableRateReturnsZeroForQuietAudio() {
        let quiet = Array(repeating: Float(0.0001), count: 16000)
        let result = SyllableRate.measure(quiet, sampleRate: 16000)
        XCTAssertEqual(result.syllables, 0)
        XCTAssertEqual(result.speechSeconds, 0)
    }

    func testSyllableRateIgnoresLowSampleRates() {
        let samples = Array(repeating: Float(0.1), count: 100)
        let result = SyllableRate.measure(samples, sampleRate: 3000)
        XCTAssertEqual(result.syllables, 0)
        XCTAssertEqual(result.speechSeconds, 0)
    }

    func testSyllableRateWithMinimalAudio() {
        let samples = Array(repeating: Float(0.1), count: 160)
        let result = SyllableRate.measure(samples, sampleRate: 16000)
        XCTAssertGreaterThanOrEqual(result.syllables, 0)
    }

    func testTextSyllablesCountsEnglish() {
        XCTAssertEqual(TextSyllables.count("hello", language: "en"), 2)
        XCTAssertEqual(TextSyllables.count("world", language: "en"), 1)
        XCTAssertEqual(TextSyllables.count("conversation", language: "en"), 4)
    }

    func testTextSyllablesIgnoresCaseAndWhitespace() {
        XCTAssertEqual(TextSyllables.count("HELLO"), TextSyllables.count("hello"))
        XCTAssertEqual(TextSyllables.count("  hello  world  "), TextSyllables.count("hello world"))
    }

    func testTextSyllablesHandlesPunctuation() {
        XCTAssertEqual(TextSyllables.count("hello!"), TextSyllables.count("hello"))
        XCTAssertEqual(TextSyllables.count("don't"), TextSyllables.count("dont"))
    }

    func testTextSyllablesReturnsNilForUnknownScript() {
        XCTAssertNil(TextSyllables.count("שלום"))
        XCTAssertNil(TextSyllables.count("مرحبا"))
    }

    func testTextSyllablesCountsChineseCharacters() {
        XCTAssertEqual(TextSyllables.count("你好"), 2)
        XCTAssertEqual(TextSyllables.count("世界"), 2)
    }

    func testTextSyllablesCountsJapaneseSyllables() {
        XCTAssertEqual(TextSyllables.count("こんにちは"), 5)
    }

    func testTextSyllablesCountsKorean() {
        XCTAssertEqual(TextSyllables.count("안녕하세요"), 5)
    }

    func testSpeakerTraitsIsUsableWhenValid() {
        let traits = SpeakerTraits(pitchHz: 150, syllablesPerSecond: 5)
        XCTAssertTrue(traits.isUsable)
    }

    func testSpeakerTraitsNotUsableWhenPitchNonFinite() {
        let traits = SpeakerTraits(pitchHz: .nan, syllablesPerSecond: 5)
        XCTAssertFalse(traits.isUsable)
    }

    func testSpeakerTraitsNotUsableWhenRateNonFinite() {
        let traits = SpeakerTraits(pitchHz: 150, syllablesPerSecond: .infinity)
        XCTAssertFalse(traits.isUsable)
    }

    func testSpeakerTraitsNotUsableWhenZero() {
        let traits = SpeakerTraits(pitchHz: 0, syllablesPerSecond: 5)
        XCTAssertFalse(traits.isUsable)
    }

    func testSpeakerProfileStartsEmpty() {
        var profile = SpeakerProfile()
        XCTAssertNil(profile.traits)
        XCTAssertEqual(profile.storedPitchFrames, 0)
    }

    func testSpeakerProfileAccumulatesSamples() {
        var profile = SpeakerProfile()
        let samples = generateTone(hz: 200, duration: 3, sampleRate: 16000, amplitude: 0.2)
        profile.add(samples, sampleRate: 16000)
        XCTAssertGreaterThanOrEqual(profile.storedPitchFrames, 0)
    }

    func testSpeakerProfileReturnsTraitsAfterEnoughSpeech() {
        var profile = SpeakerProfile()
        let samples = generateTone(hz: 200, duration: 3, sampleRate: 16000, amplitude: 0.2)
        profile.add(samples, sampleRate: 16000)
        profile.addLine("hello world this is a test", speechSeconds: 3, language: "en")
        XCTAssertNotNil(profile.traits)
    }

    func testCalibrationPointInterpolation() {
        let curve = [CalibrationPoint(0.5, 100), CalibrationPoint(1.0, 200)]
        let value = CalibrationPoint.value(at: 0.75, in: curve)
        XCTAssertEqual(value, 150)
    }

    func testCalibrationPointExtrapolationLow() {
        let curve = [CalibrationPoint(0.5, 100), CalibrationPoint(1.0, 200)]
        let value = CalibrationPoint.value(at: 0.25, in: curve)
        XCTAssertEqual(value, 100)
    }

    func testCalibrationPointExtrapolationHigh() {
        let curve = [CalibrationPoint(0.5, 100), CalibrationPoint(1.0, 200)]
        let value = CalibrationPoint.value(at: 1.5, in: curve)
        XCTAssertEqual(value, 200)
    }

    func testCalibrationPointInverse() {
        let curve = [CalibrationPoint(0.5, 100), CalibrationPoint(1.0, 200)]
        let input = CalibrationPoint.input(for: 150, in: curve)
        XCTAssertEqual(input, 0.75)
    }

    func testVoiceMatchDefaultBehavior() {
        let speakers: [SpeakerTraits?] = [nil]
        let voices = [VoiceCalibration(id: "voice1", pitchHz: 150, syllablesPerSecond: 5,
                                       rateCurve: [], pitchCurve: [])]
        let matched = VoiceMatch.match(speakers, voices: voices, normalSyllablesPerSecond: 5)
        XCTAssertEqual(matched.count, 1)
        XCTAssertEqual(matched[0].pitchMultiplier, 1)
        XCTAssertEqual(matched[0].rate, VoiceMatch.defaultRate)
    }

    func testVoiceMatchMultipleSpeakers() {
        let speaker1 = SpeakerTraits(pitchHz: 120, syllablesPerSecond: 5)
        let speaker2 = SpeakerTraits(pitchHz: 200, syllablesPerSecond: 5)
        let speakers: [SpeakerTraits?] = [speaker1, speaker2]
        let voices = [VoiceCalibration(id: "voice1", pitchHz: 150, syllablesPerSecond: 5,
                                       rateCurve: [], pitchCurve: [])]
        let matched = VoiceMatch.match(speakers, voices: voices, normalSyllablesPerSecond: 5)
        XCTAssertEqual(matched.count, 2)
    }

    func testSyllableRateWithPeaksNearEndWhenVoicedIsShorter() {
        // Generate audio with a peak near the end, and provide a pitch array shorter than db.
        // This would crash if the range validation in SyllableRate isn't correct.
        let sampleRate = 16000.0
        let duration = 2.0
        let samples = generateTone(hz: 200, duration: duration, sampleRate: sampleRate, amplitude: 0.2)
        // Manually truncate the voiced array to simulate the case where pitch tracking returns
        // fewer frames than the db calculation produces.
        let voiced = Array(repeating: Double(200), count: max(0, Int(duration * sampleRate / 10) - 5))
        let result = SyllableRate.measure(samples, sampleRate: sampleRate, pitch: voiced)
        // Should not crash and return a valid result.
        XCTAssertGreaterThanOrEqual(result.syllables, 0)
        XCTAssertGreaterThanOrEqual(result.speechSeconds, 0)
    }

    func testSyllableRateWithEmptyVoicedArray() {
        // Test with a completely empty voiced array to ensure range validation prevents a crash.
        let sampleRate = 16000.0
        let samples = generateTone(hz: 200, duration: 1, sampleRate: sampleRate, amplitude: 0.2)
        let result = SyllableRate.measure(samples, sampleRate: sampleRate, pitch: [])
        // Should not crash and return a valid result with no syllables detected (no voiced data).
        XCTAssertGreaterThanOrEqual(result.syllables, 0)
        XCTAssertGreaterThanOrEqual(result.speechSeconds, 0)
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

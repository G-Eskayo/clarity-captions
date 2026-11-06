import CaptionCore
import XCTest

private func tone(_ f0: Double, seconds: Double, rate: Double = 16000, level: Float = 0.3) -> [Float] {
    (0..<Int(seconds * rate)).map { i in
        let t = Double(i) / rate
        let s = (1...5).reduce(0.0) { $0 + sin(2 * .pi * f0 * Double($1) * t) / Double($1) }
        return Float(s / 2.3) * level
    }
}

private func syllables(perSecond: Double, seconds: Double, f0: Double = 140, rate: Double = 16000) -> [Float] {
    let carrier = tone(f0, seconds: seconds, rate: rate)
    return carrier.enumerated().map { i, s in
        let phase = (Double(i) / rate * perSecond).truncatingRemainder(dividingBy: 1)
        let shape = phase < 0.6 ? 0.5 - 0.5 * cos(2 * .pi * phase / 0.6) : 0.02
        return s * Float(shape)
    }
}

private func silence(_ seconds: Double, rate: Double = 16000) -> [Float] {
    [Float](repeating: 0, count: Int(seconds * rate))
}

private func noise(_ seconds: Double, level: Float = 0.2, rate: Double = 16000) -> [Float] {
    var state: UInt64 = 247
    return (0..<Int(seconds * rate)).map { _ in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (Float(state >> 40) / Float(1 << 24) * 2 - 1) * level
    }
}

private func median(_ v: [Double]) -> Double {
    let s = v.sorted()
    return s[s.count / 2]
}

class SpeakerVoiceTests: XCTestCase {
    func testPitchTrackerFindsFundamental() {
        for f0 in [85.0, 120.0, 180.0, 230.0, 320.0] {
            let frames = PitchTracker.track(tone(f0, seconds: 1), sampleRate: 16000).compactMap { $0 }
            XCTAssert(frames.count > 80, "Not enough voiced frames for \(f0)")
            XCTAssert(abs(median(frames) - f0) / f0 < 0.02, "Median pitch off by \((abs(median(frames) - f0) / f0 * 100).rounded())% for \(f0)")
        }
    }

    func testPitchTrackerOtherSampleRates() {
        for rate in [8000.0, 22050, 48000] {
            let frames = PitchTracker.track(tone(150, seconds: 0.5, rate: rate), sampleRate: rate).compactMap { $0 }
            XCTAssertFalse(frames.isEmpty, "No voiced frames at \(rate)")
            XCTAssert(abs(median(frames) - 150) < 3, "Median pitch off for \(rate)")
        }
    }

    func testPitchTrackerSilenceAndNoiseAreUnvoiced() {
        XCTAssert(PitchTracker.track(silence(1), sampleRate: 16000).allSatisfy { $0 == nil })
        let voicedInNoise = PitchTracker.track(noise(1), sampleRate: 16000).compactMap { $0 }.count
        XCTAssert(voicedInNoise < 10)
    }

    func testPitchTrackerOutOfRangeIsNotReported() {
        let low = PitchTracker.track(tone(30, seconds: 0.5), sampleRate: 16000).compactMap { $0 }
        XCTAssert(low.allSatisfy { $0 >= PitchTracker.minimumHz && $0 <= PitchTracker.maximumHz })
        let high = PitchTracker.track(tone(1000, seconds: 0.5), sampleRate: 16000).compactMap { $0 }
        XCTAssert(high.count < 5)
    }

    func testPitchTrackerEmptyShortAndBrokenInput() {
        XCTAssert(PitchTracker.track([], sampleRate: 16000).isEmpty)
        XCTAssert(PitchTracker.track([0.1, 0.2], sampleRate: 16000).isEmpty)
        XCTAssert(PitchTracker.track(tone(150, seconds: 0.2), sampleRate: 0).isEmpty)
        var broken = tone(150, seconds: 0.5)
        broken[100] = .nan
        broken[2000] = .infinity
        let frames = PitchTracker.track(broken, sampleRate: 16000)
        XCTAssert(frames.compactMap { $0 }.allSatisfy { $0.isFinite })
    }

    func testPitchTrackerClippedLoudSpeechStillTracks() {
        let loud = tone(200, seconds: 0.5, level: 3).map { max(-1, min(1, $0)) }
        let frames = PitchTracker.track(loud, sampleRate: 16000).compactMap { $0 }
        XCTAssert(abs(median(frames) - 200) < 4)
    }

    func testSyllableRateCountsBursts() {
        for perSecond in [3.0, 4.5, 6.0] {
            let r = SyllableRate.measure(syllables(perSecond: perSecond, seconds: 4), sampleRate: 16000)
            XCTAssert(abs(Double(r.syllables) - perSecond * 4) <= 2, "Syllable count off for \(perSecond)")
            if let rate = r.perSecond {
                XCTAssert(abs(rate - perSecond) / perSecond < 0.15, "Syllable rate off for \(perSecond)")
            } else {
                XCTFail("No syllable rate for \(perSecond)")
            }
        }
    }

    func testSyllableRatePausesDontSlowItDown() {
        let s = syllables(perSecond: 5, seconds: 2) + silence(2) + syllables(perSecond: 5, seconds: 2)
        let r = SyllableRate.measure(s, sampleRate: 16000)
        XCTAssert(r.speechSeconds < 4.6)
        if let rate = r.perSecond {
            XCTAssert(abs(rate - 5) < 1)
        } else {
            XCTFail("No syllable rate")
        }
    }

    func testSyllableRateNothingToMeasure() {
        XCTAssertNil(SyllableRate.measure([], sampleRate: 16000).perSecond)
        XCTAssertNil(SyllableRate.measure(silence(2), sampleRate: 16000).perSecond)
        XCTAssertNil(SyllableRate.measure(tone(140, seconds: 1), sampleRate: 0).perSecond)
    }

    func testSyllableRateSteadyHumIsNotSyllables() {
        let r = SyllableRate.measure(tone(140, seconds: 2), sampleRate: 16000)
        XCTAssert(r.syllables <= 1)
    }

    func testSpeakerProfileSettlesAfterEnoughSpeech() {
        var p = SpeakerProfile()
        XCTAssertNil(p.traits)
        p.add(syllables(perSecond: 5, seconds: 1, f0: 110), sampleRate: 16000)
        XCTAssertNil(p.traits)
        p.add(syllables(perSecond: 5, seconds: 2, f0: 110), sampleRate: 16000)
        let t = p.traits
        XCTAssertNotNil(t)
        XCTAssert(abs(t!.pitchHz - 110) < 3)
        XCTAssert(abs(t!.syllablesPerSecond - 5) < 1)
    }

    func testSpeakerProfileChunkedEqualsWhole() {
        let audio = syllables(perSecond: 4, seconds: 4, f0: 210)
        var whole = SpeakerProfile()
        whole.add(audio, sampleRate: 16000)
        var chunked = SpeakerProfile()
        stride(from: 0, to: audio.count, by: 1365).forEach { i in
            chunked.add(Array(audio[i..<min(audio.count, i + 1365)]), sampleRate: 16000)
        }
        let a = whole.traits
        let b = chunked.traits
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssert(abs(a!.pitchHz - b!.pitchHz) < 2)
        XCTAssert(abs(a!.syllablesPerSecond - b!.syllablesPerSecond) < 0.6)
    }

    func testSpeakerProfileSilenceAndNoiseNeverSettleIt() {
        var p = SpeakerProfile()
        p.add(silence(5), sampleRate: 16000)
        p.add(noise(5), sampleRate: 16000)
        XCTAssertNil(p.traits)
    }

    func testSpeakerProfileMemoryStaysBounded() {
        var p = SpeakerProfile()
        for _ in 0..<40 {
            p.add(syllables(perSecond: 5, seconds: 3, f0: 130), sampleRate: 16000)
        }
        XCTAssert(p.storedPitchFrames <= SpeakerProfile.maximumPitchFrames)
        let t = p.traits
        XCTAssertNotNil(t)
        XCTAssert(abs(t!.pitchHz - 130) < 3)
    }

    func testSpeakerProfileALaughDoesntMoveTheMedian() {
        var p = SpeakerProfile()
        p.add(syllables(perSecond: 5, seconds: 4, f0: 120), sampleRate: 16000)
        p.add(syllables(perSecond: 8, seconds: 0.7, f0: 330), sampleRate: 16000)
        let t = p.traits
        XCTAssertNotNil(t)
        XCTAssert(abs(t!.pitchHz - 120) < 8)
    }

    // Two voices measured at setup: a low one and a high one
    private let low = VoiceCalibration(
        id: "low", pitchHz: 110, syllablesPerSecond: 5,
        rateCurve: [.init(0.4, 3.8), .init(0.5, 5), .init(0.6, 6.4)],
        pitchCurve: [.init(0.75, 85), .init(1, 110), .init(1.5, 160)]
    )
    private let high = VoiceCalibration(
        id: "high", pitchHz: 210, syllablesPerSecond: 5.2,
        rateCurve: [.init(0.4, 4), .init(0.5, 5.2), .init(0.6, 6.6)],
        pitchCurve: [.init(0.75, 160), .init(1, 210), .init(1.5, 300)]
    )
    private let normal = 5.0

    func testVoiceMatchLowSpeakerGetsTheLowVoiceHighGetsHigh() {
        let m = VoiceMatch.match(
            [.init(pitchHz: 105, syllablesPerSecond: 5), .init(pitchHz: 220, syllablesPerSecond: 5)],
            voices: [high, low], normalSyllablesPerSecond: normal
        )
        XCTAssertEqual(m.map { $0.voiceID }, ["low", "high"])
    }

    func testVoiceMatchPitchMovesTowardTheSpeaker() {
        let m = VoiceMatch.match(
            [.init(pitchHz: 130, syllablesPerSecond: 5)],
            voices: [low], normalSyllablesPerSecond: normal
        )[0]
        XCTAssert(m.pitchMultiplier > 1 && m.pitchMultiplier < 1.5)

        let far = VoiceMatch.match(
            [.init(pitchHz: 400, syllablesPerSecond: 5), .init(pitchHz: 60, syllablesPerSecond: 5)],
            voices: [low], normalSyllablesPerSecond: normal
        )
        for f in far {
            XCTAssert(f.pitchMultiplier <= VoiceMatch.pitchMultiplierRange.upperBound)
            XCTAssert(f.pitchMultiplier >= VoiceMatch.pitchMultiplierRange.lowerBound)
        }
    }

    func testVoiceMatchFastSpeakerFastVoiceSlowSpeakerSlowVoice() {
        let m = VoiceMatch.match(
            [.init(pitchHz: 110, syllablesPerSecond: 6.5), .init(pitchHz: 112, syllablesPerSecond: 3.5)],
            voices: [low], normalSyllablesPerSecond: normal
        )
        XCTAssert(m[0].rate > VoiceMatch.defaultRate)
        XCTAssert(m[1].rate < VoiceMatch.defaultRate)
        for x in m {
            XCTAssert(VoiceMatch.rateRange.contains(x.rate))
        }

        let normalPace = VoiceMatch.match(
            [.init(pitchHz: 110, syllablesPerSecond: normal)],
            voices: [low], normalSyllablesPerSecond: normal
        )[0]
        XCTAssert(abs(normalPace.rate - VoiceMatch.defaultRate) < 0.01)
    }

    func testVoiceMatchTwoSimilarSpeakersStillSoundDifferent() {
        let pair: [SpeakerTraits] = [
            .init(pitchHz: 200, syllablesPerSecond: 5),
            .init(pitchHz: 204, syllablesPerSecond: 5)
        ]
        let high2 = VoiceCalibration(
            id: "high2", pitchHz: 190, syllablesPerSecond: 5,
            rateCurve: high.rateCurve,
            pitchCurve: [.init(0.75, 145), .init(1, 190), .init(1.5, 270)]
        )
        let two = VoiceMatch.match(pair, voices: [low, high, high2], normalSyllablesPerSecond: normal)
        XCTAssertNotEqual(two[0].voiceID, two[1].voiceID)
    }

    func testTextSyllablesCountsVowelGroupsInEnglish() {
        XCTAssertEqual(TextSyllables.count("hello", language: "en"), 2)
        XCTAssertEqual(TextSyllables.count("water", language: "en"), 2)
        XCTAssertEqual(TextSyllables.count("beautiful", language: "en"), 3)
    }

    func testVoiceCalibrationTableSpanishReturnsCalibrations() {
        let calibs = VoiceCalibrationTable.calibrations(for: "es")
        XCTAssertEqual(calibs.count, 9, "Spanish should have 9 voice calibrations")
        XCTAssert(calibs.allSatisfy { $0.pitchHz > 0 })
        XCTAssert(calibs.allSatisfy { $0.syllablesPerSecond > 0 })
    }

    func testVoiceCalibrationTableUnmeasuredLanguageReturnsEmpty() {
        let calibs = VoiceCalibrationTable.calibrations(for: "fr")
        XCTAssertEqual(calibs.count, 0)
    }

    func testSyllableRateDoesNotCrashWithPeakNearEnd() {
        // Regression test for range bounds issue: PitchTracker returns fewer frames than db,
        // so when a prominent peak occurs near the end of the audio, the range check must not trap.
        let s = syllables(perSecond: 5, seconds: 2, f0: 150)
        // Should not crash regardless of where peaks occur
        let r = SyllableRate.measure(s, sampleRate: 16000)
        XCTAssertGreaterThan(r.syllables, 0)
        // The test passes if no trap occurred; the actual syllable count is just verification
        XCTAssertGreaterThan(r.speechSeconds, 0)
    }
}

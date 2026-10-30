import EarSpikeKit
import Foundation
import Testing

// #247 part 1: the voice in your ear set to each speaker's pitch and pace.

/// A voiced-sounding tone: `f0` plus four harmonics, at `level` peak.
private func tone(_ f0: Double, seconds: Double, rate: Double = 16000, level: Float = 0.3) -> [Float] {
    (0..<Int(seconds * rate)).map { i in
        let t = Double(i) / rate
        let s = (1...5).reduce(0.0) { $0 + sin(2 * .pi * f0 * Double($1) * t) / Double($1) }
        return Float(s / 2.3) * level
    }
}

/// `count` syllable-like bursts per second: the tone, shaped by a raised cosine, with a quiet gap between.
private func syllables(perSecond: Double, seconds: Double, f0: Double = 140, rate: Double = 16000) -> [Float] {
    let carrier = tone(f0, seconds: seconds, rate: rate)
    return carrier.enumerated().map { i, s in
        let phase = (Double(i) / rate * perSecond).truncatingRemainder(dividingBy: 1)
        let shape = phase < 0.6 ? 0.5 - 0.5 * cos(2 * .pi * phase / 0.6) : 0.02
        return s * Float(shape)
    }
}

private func silence(_ seconds: Double, rate: Double = 16000) -> [Float] { [Float](repeating: 0, count: Int(seconds * rate)) }

private func noise(_ seconds: Double, level: Float = 0.2, rate: Double = 16000) -> [Float] {
    var state: UInt64 = 247
    return (0..<Int(seconds * rate)).map { _ in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (Float(state >> 40) / Float(1 << 24) * 2 - 1) * level
    }
}

private func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }

@Suite struct PitchTrackerTests {
    @Test(arguments: [85.0, 120.0, 180.0, 230.0, 320.0])
    func findsTheFundamental(f0: Double) {
        let frames = PitchTracker.track(tone(f0, seconds: 1), sampleRate: 16000).compactMap { $0 }
        #expect(frames.count > 80)
        #expect(abs(median(frames) - f0) / f0 < 0.02)
    }

    @Test func otherSampleRates() {
        for rate in [8000.0, 22050, 48000] {
            let frames = PitchTracker.track(tone(150, seconds: 0.5, rate: rate), sampleRate: rate).compactMap { $0 }
            #expect(!frames.isEmpty)
            #expect(abs(median(frames) - 150) < 3, "\(rate)")
        }
    }

    @Test func silenceAndNoiseAreUnvoiced() {
        #expect(PitchTracker.track(silence(1), sampleRate: 16000).allSatisfy { $0 == nil })
        let voicedInNoise = PitchTracker.track(noise(1), sampleRate: 16000).compactMap { $0 }.count
        #expect(voicedInNoise < 10)
    }

    @Test func outOfRangeIsNotReported() {
        // A 30 Hz hum and a 1 kHz whistle aren't a voice.
        #expect(PitchTracker.track(tone(30, seconds: 0.5), sampleRate: 16000).compactMap { $0 }
            .allSatisfy { $0 >= PitchTracker.minimumHz && $0 <= PitchTracker.maximumHz })
        #expect(PitchTracker.track(tone(1000, seconds: 0.5), sampleRate: 16000).compactMap { $0 }.count < 5)
    }

    @Test func emptyShortAndBrokenInput() {
        #expect(PitchTracker.track([], sampleRate: 16000).isEmpty)
        #expect(PitchTracker.track([0.1, 0.2], sampleRate: 16000).isEmpty)
        #expect(PitchTracker.track(tone(150, seconds: 0.2), sampleRate: 0).isEmpty)
        var broken = tone(150, seconds: 0.5)
        broken[100] = .nan; broken[2000] = .infinity
        let frames = PitchTracker.track(broken, sampleRate: 16000)
        #expect(frames.compactMap { $0 }.allSatisfy { $0.isFinite })
    }

    @Test func clippedLoudSpeechStillTracks() {
        let loud = tone(200, seconds: 0.5, level: 3).map { max(-1, min(1, $0)) }
        let frames = PitchTracker.track(loud, sampleRate: 16000).compactMap { $0 }
        #expect(abs(median(frames) - 200) < 4)
    }
}

@Suite struct SyllableRateTests {
    @Test(arguments: [3.0, 4.5, 6.0])
    func countsBursts(perSecond: Double) {
        let r = SyllableRate.measure(syllables(perSecond: perSecond, seconds: 4), sampleRate: 16000)
        #expect(abs(Double(r.syllables) - perSecond * 4) <= 2)
        #expect(abs(r.perSecond! - perSecond) / perSecond < 0.15)
    }

    @Test func pausesDontSlowItDown() {
        // Two seconds of talk, a two-second pause, two more: the pace while talking, not over the whole clip.
        let s = syllables(perSecond: 5, seconds: 2) + silence(2) + syllables(perSecond: 5, seconds: 2)
        let r = SyllableRate.measure(s, sampleRate: 16000)
        #expect(r.speechSeconds < 4.6)
        #expect(abs(r.perSecond! - 5) < 1)
    }

    @Test func nothingToMeasure() {
        #expect(SyllableRate.measure([], sampleRate: 16000).perSecond == nil)
        #expect(SyllableRate.measure(silence(2), sampleRate: 16000).perSecond == nil)
        #expect(SyllableRate.measure(tone(140, seconds: 1), sampleRate: 0).perSecond == nil)
    }

    @Test func steadyHumIsNotSyllables() {
        // A flat, unchanging sound (a fan, a fridge) has no syllable peaks.
        #expect(SyllableRate.measure(tone(140, seconds: 2), sampleRate: 16000).syllables <= 1)
    }
}

@Suite struct SpeakerProfileTests {
    @Test func settlesAfterEnoughSpeech() {
        var p = SpeakerProfile()
        #expect(p.traits == nil)
        p.add(syllables(perSecond: 5, seconds: 1, f0: 110), sampleRate: 16000)
        #expect(p.traits == nil, "one second is not enough to judge a voice")
        p.add(syllables(perSecond: 5, seconds: 2, f0: 110), sampleRate: 16000)
        let t = try! #require(p.traits)
        #expect(abs(t.pitchHz - 110) < 3)
        #expect(abs(t.syllablesPerSecond - 5) < 1)
    }

    @Test func chunkedEqualsWhole() {
        let audio = syllables(perSecond: 4, seconds: 4, f0: 210)
        var whole = SpeakerProfile(); whole.add(audio, sampleRate: 16000)
        var chunked = SpeakerProfile()
        stride(from: 0, to: audio.count, by: 1365).forEach { chunked.add(Array(audio[$0..<min(audio.count, $0 + 1365)]), sampleRate: 16000) }
        let a = try! #require(whole.traits), b = try! #require(chunked.traits)
        #expect(abs(a.pitchHz - b.pitchHz) < 2)
        #expect(abs(a.syllablesPerSecond - b.syllablesPerSecond) < 0.6)
    }

    @Test func silenceAndNoiseNeverSettleIt() {
        var p = SpeakerProfile()
        p.add(silence(5), sampleRate: 16000)
        p.add(noise(5), sampleRate: 16000)
        #expect(p.traits == nil)
    }

    @Test func memoryStaysBounded() {
        var p = SpeakerProfile()
        for _ in 0..<40 { p.add(syllables(perSecond: 5, seconds: 3, f0: 130), sampleRate: 16000) }
        #expect(p.storedPitchFrames <= SpeakerProfile.maximumPitchFrames)
        #expect(abs(p.traits!.pitchHz - 130) < 3)
    }

    @Test func aLaughDoesntMoveTheMedian() {
        var p = SpeakerProfile()
        p.add(syllables(perSecond: 5, seconds: 4, f0: 120), sampleRate: 16000)
        p.add(syllables(perSecond: 8, seconds: 0.7, f0: 330), sampleRate: 16000)
        #expect(abs(p.traits!.pitchHz - 120) < 8)
    }
}

/// Two voices measured at setup: a low one and a high one, with how their pitch and pace move.
private let low = VoiceCalibration(id: "low", pitchHz: 110, syllablesPerSecond: 5,
                                   rateCurve: [.init(0.4, 3.8), .init(0.5, 5), .init(0.6, 6.4)],
                                   pitchCurve: [.init(0.75, 85), .init(1, 110), .init(1.5, 160)])
private let high = VoiceCalibration(id: "high", pitchHz: 210, syllablesPerSecond: 5.2,
                                    rateCurve: [.init(0.4, 4), .init(0.5, 5.2), .init(0.6, 6.6)],
                                    pitchCurve: [.init(0.75, 160), .init(1, 210), .init(1.5, 300)])
private let normal = 5.0

@Suite struct VoiceMatchTests {
    @Test func lowSpeakerGetsTheLowVoiceHighGetsHigh() {
        let m = VoiceMatch.match([.init(pitchHz: 105, syllablesPerSecond: 5), .init(pitchHz: 220, syllablesPerSecond: 5)],
                                 voices: [high, low], normalSyllablesPerSecond: normal)
        #expect(m.map(\.voiceID) == ["low", "high"])
    }

    @Test func pitchMovesTowardTheSpeakerWithinLimits() {
        let m = VoiceMatch.match([.init(pitchHz: 130, syllablesPerSecond: 5)], voices: [low], normalSyllablesPerSecond: normal)[0]
        #expect(m.pitchMultiplier > 1 && m.pitchMultiplier < 1.5)
        // A child's or a very deep voice: shifted only so far, so the voice stays clear.
        let far = VoiceMatch.match([.init(pitchHz: 400, syllablesPerSecond: 5), .init(pitchHz: 60, syllablesPerSecond: 5)],
                                   voices: [low], normalSyllablesPerSecond: normal)
        for f in far {
            #expect(f.pitchMultiplier <= VoiceMatch.pitchMultiplierRange.upperBound)
            #expect(f.pitchMultiplier >= VoiceMatch.pitchMultiplierRange.lowerBound)
        }
    }

    @Test func fastSpeakerFastVoiceSlowSpeakerSlowVoice() {
        let m = VoiceMatch.match([.init(pitchHz: 110, syllablesPerSecond: 6.5), .init(pitchHz: 112, syllablesPerSecond: 3.5)],
                                 voices: [low], normalSyllablesPerSecond: normal)
        #expect(m[0].rate > VoiceMatch.defaultRate && m[1].rate < VoiceMatch.defaultRate)
        for x in m { #expect(VoiceMatch.rateRange.contains(x.rate)) }
        let normalPace = VoiceMatch.match([.init(pitchHz: 110, syllablesPerSecond: normal)], voices: [low],
                                          normalSyllablesPerSecond: normal)[0]
        #expect(abs(normalPace.rate - VoiceMatch.defaultRate) < 0.01)
    }

    @Test func twoSimilarSpeakersStillSoundDifferent() {
        // Two people with nearly the same voice: a second voice close to theirs if there is one...
        let pair: [SpeakerTraits] = [.init(pitchHz: 200, syllablesPerSecond: 5), .init(pitchHz: 204, syllablesPerSecond: 5)]
        let high2 = VoiceCalibration(id: "high2", pitchHz: 190, syllablesPerSecond: 5, rateCurve: high.rateCurve,
                                     pitchCurve: [.init(0.75, 145), .init(1, 190), .init(1.5, 270)])
        let two = VoiceMatch.match(pair, voices: [low, high, high2], normalSyllablesPerSecond: normal)
        #expect(two[0].voiceID != two[1].voiceID)
        #expect(Set(two.compactMap(\.voiceID)) == ["high", "high2"], "never a man's voice for a woman just to differ")
        // ...else the same voice, pitched at least two semitones apart.
        for voices in [[high], [low, high]] {
            let one = VoiceMatch.match(pair, voices: voices, normalSyllablesPerSecond: normal)
            #expect(one[0].voiceID == "high" && one[1].voiceID == "high")
            let hz = one.map { CalibrationPoint.value(at: Double($0.pitchMultiplier), in: high.pitchCurve)! }
            #expect(12 * log2(hz[1] / hz[0]) >= VoiceMatch.minimumSemitonesApart - 0.01)
        }
    }

    @Test func unknownSpeakerKeepsTheDefault() {
        // Not enough speech yet (nil traits): the voice speaks as it does today.
        let m = VoiceMatch.match([nil, .init(pitchHz: 220, syllablesPerSecond: 5)], voices: [low, high],
                                 normalSyllablesPerSecond: normal, defaultVoiceID: "low")
        #expect(m[0] == MatchedVoice(voiceID: "low", pitchMultiplier: 1, rate: VoiceMatch.defaultRate))
        #expect(m[1].voiceID == "high")
    }

    @Test func noVoicesOrBrokenNumbers() {
        #expect(VoiceMatch.match([.init(pitchHz: 120, syllablesPerSecond: 5)], voices: [], normalSyllablesPerSecond: normal)
            .allSatisfy { $0.voiceID == nil })
        let bad = VoiceMatch.match([.init(pitchHz: .nan, syllablesPerSecond: .infinity), .init(pitchHz: 0, syllablesPerSecond: -2)],
                                   voices: [low], normalSyllablesPerSecond: 0)
        for b in bad {
            #expect(b.pitchMultiplier.isFinite && b.rate.isFinite)
            #expect(VoiceMatch.rateRange.contains(b.rate))
            #expect(VoiceMatch.pitchMultiplierRange.contains(b.pitchMultiplier))
        }
    }

    @Test func moreSpeakersThanVoicesReusesThem() {
        let many = (0..<6).map { SpeakerTraits(pitchHz: 100 + Double($0) * 25, syllablesPerSecond: 5) }
        let m = VoiceMatch.match(many, voices: [low, high], normalSyllablesPerSecond: normal)
        #expect(m.count == 6)
        #expect(Set(m.compactMap(\.voiceID)) == ["low", "high"])
    }

    @Test func catchUpStillWorksOnTopOfAFastSpeaker() {
        // EarPace's catch-up (up to 1.3x, #238) multiplies the matched rate, still capped.
        let fast = MatchedVoice(voiceID: "low", pitchMultiplier: 1, rate: VoiceMatch.rateRange.upperBound)
        #expect(fast.rate(catchUp: 1.3) <= VoiceMatch.maximumRateWithCatchUp)
        #expect(MatchedVoice(voiceID: nil, pitchMultiplier: 1, rate: VoiceMatch.defaultRate).rate(catchUp: 1) == VoiceMatch.defaultRate)
    }
}

@Suite struct CalibrationCurveTests {
    @Test func interpolatesAndInverts() {
        let c = [CalibrationPoint(0.4, 4), .init(0.5, 5), .init(0.6, 6.5)]
        #expect(abs(CalibrationPoint.value(at: 0.45, in: c)! - 4.5) < 1e-9)
        #expect(abs(CalibrationPoint.input(for: 5.75, in: c)! - 0.55) < 1e-9)
        #expect(CalibrationPoint.input(for: 99, in: c) == 0.6, "clamped to the measured range")
        #expect(CalibrationPoint.value(at: 0.5, in: []) == nil)
        #expect(CalibrationPoint.input(for: 1, in: [.init(0.5, 5)]) == 0.5)
    }
}

@Suite struct TextSyllablesTests {
    /// Within one of how it's said: a rule of thumb, not a dictionary.
    private func near(_ text: String, _ truth: Int, _ language: String? = nil) -> Bool {
        guard let n = TextSyllables.count(text, language: language) else { return false }
        return abs(n - truth) <= 1
    }

    @Test func english() {
        #expect(TextSyllables.count("Where is the train station?", language: "en") == 6)
        #expect(near("I'm sorry, I didn't catch your name.", 9, "en"))
        #expect(near("The museum opens at nine tomorrow morning.", 13, "en"))
        #expect(near("Can we get the bill, please?", 6, "en"))
    }

    @Test func spanishAndOtherLatinScripts() {
        // No silent e in Spanish: "Dónde" is two.
        #expect(TextSyllables.count("¿Dónde está la estación de tren?", language: "es") == 10)
        #expect(TextSyllables.count("Muchísimas gracias", language: "es") == 6)
        #expect(near("Mi hija viene a visitarnos la semana que viene.", 16, "es"))
        #expect(TextSyllables.count("Où est la gare ?", language: "fr")! >= 4)
    }

    @Test func notLatinOrNothing() {
        #expect(TextSyllables.count("駅はどこですか") == 7, "one per character for kana and kanji")
        #expect(near("Где находится вокзал?", 7))
        #expect(TextSyllables.count("") == nil)
        #expect(TextSyllables.count("  ...?! 123 ") == nil)
        #expect(TextSyllables.count("איפה תחנת הרכבת") == nil, "no written vowels: say so, don't guess")
    }
}

@Suite struct TextPaceTests {
    @Test func linesSetThePaceOverTheAcousticGuess() {
        var p = SpeakerProfile()
        p.add(syllables(perSecond: 5, seconds: 3, f0: 120), sampleRate: 16000)
        p.addLine("Where is the train station?", speechSeconds: 1.75, language: "en") // 6 syllables
        p.addLine("Can we get the bill, please?", speechSeconds: 1.5, language: "en")  // 6
        #expect(abs(p.traits!.syllablesPerSecond - 12 / 3.25) < 0.01)
    }

    @Test func badLinesAreIgnored() {
        var p = SpeakerProfile()
        p.add(syllables(perSecond: 5, seconds: 3, f0: 120), sampleRate: 16000)
        let acoustic = p.traits!.syllablesPerSecond
        p.addLine("", speechSeconds: 2)
        p.addLine("Hello there", speechSeconds: 0)
        p.addLine("Hello there", speechSeconds: .nan)
        p.addLine("Hello there", speechSeconds: 0.05) // 40 syllables a second isn't a person
        p.addLine("איפה תחנת הרכבת", speechSeconds: 1)
        #expect(p.traits!.syllablesPerSecond == acoustic)
    }

    @Test func textPaceAloneDoesntSettleIt() {
        // Pitch still needs audio.
        var p = SpeakerProfile()
        p.addLine("Where is the train station?", speechSeconds: 1.75)
        #expect(p.traits == nil)
    }
}

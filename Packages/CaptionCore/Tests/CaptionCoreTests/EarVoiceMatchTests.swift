import CaptionCore
import XCTest

/// "Sound like the speaker" (#247, the owner's answers on PR #254: "wire" A, "setting" B): each speaker's pitch and
/// pace learned from the audio of their finished lines, the shipped calibration table, and a voice per speaker that
/// doesn't jump once it's chosen. Built to be broken: bad times, repeats, overlaps, unknown speakers, broken tables.

/// A voiced tone at `f0` with harmonics, as 16 kHz samples.
private func voice(_ f0: Double, seconds: Double, level: Float = 0.3) -> [Float] {
    let rate = 16000.0
    return (0..<Int(seconds * rate)).map { i in
        let t = Double(i) / rate
        // Syllable-like: 5 bursts a second, so there's speech and pauses to count.
        let envelope = 0.5 - 0.5 * cos(2 * .pi * (t * 5).truncatingRemainder(dividingBy: 1))
        let s = (1...5).reduce(0.0) { $0 + sin(2 * .pi * f0 * Double($1) * t) / Double($1) }
        return Float(s / 2.3 * envelope) * level
    }
}

private func calibration(_ id: String, hz: Double, pace: Double = 6) -> VoiceCalibration {
    VoiceCalibration(id: id, pitchHz: hz, syllablesPerSecond: pace,
                     rateCurve: [.init(0.4, pace * 0.75), .init(0.5, pace), .init(0.6, pace * 1.4)],
                     pitchCurve: [.init(0.8, hz * 0.8), .init(1, hz), .init(1.25, hz * 1.25)])
}

final class SpeakerVoiceRecorderTests: XCTestCase {
    private func recorder() -> SpeakerVoiceRecorder {
        let r = SpeakerVoiceRecorder()
        r.isRecording = true
        r.begin(language: "en-US")
        return r
    }

    /// Feeds `audio` in the app's ~85 ms buffers from `start` on the session clock.
    private func feed(_ r: SpeakerVoiceRecorder, _ audio: [Float], from start: Double) {
        var i = 0
        while i < audio.count {
            let n = min(1360, audio.count - i)
            r.feed(Array(audio[i..<(i + n)]), at: start + Double(i) / 16000)
            i += n
        }
    }

    func testLearnsEachSpeakersPitchFromTheirOwnLines() throws {
        let r = recorder()
        feed(r, voice(120, seconds: 3) + voice(220, seconds: 3), from: 0)
        r.lineFinished(speaker: 0, text: "where is the train station", start: 0, end: 3)
        r.lineFinished(speaker: 1, text: "can we get the bill please", start: 3, end: 6)
        let low = try XCTUnwrap(r.traits(for: 0)), high = try XCTUnwrap(r.traits(for: 1))
        XCTAssertEqual(low.pitchHz, 120, accuracy: 4)
        XCTAssertEqual(high.pitchHz, 220, accuracy: 6)
        XCTAssertGreaterThan(low.syllablesPerSecond, 0)
    }

    func testNotEnoughSpeechYetGivesNothing() {
        let r = recorder()
        feed(r, voice(150, seconds: 1), from: 0)
        r.lineFinished(speaker: 0, text: "hi there", start: 0, end: 1)
        XCTAssertNil(r.traits(for: 0))
    }

    func testOffRecordsNothingAndCostsNothing() {
        let r = SpeakerVoiceRecorder()
        r.begin(language: "en")
        feed(r, voice(150, seconds: 3), from: 0)
        r.lineFinished(speaker: 0, text: "where is the train station", start: 0, end: 3)
        XCTAssertNil(r.traits(for: 0))
        XCTAssertEqual(r.storedSamples, 0)
    }

    func testBrokenLinesAreIgnored() {
        let r = recorder()
        feed(r, voice(150, seconds: 4), from: 0)
        r.lineFinished(speaker: nil, text: "no speaker", start: 0, end: 3)
        r.lineFinished(speaker: -1, text: "negative", start: 0, end: 3)
        r.lineFinished(speaker: 0, text: "no times", start: nil, end: nil)
        r.lineFinished(speaker: 0, text: "backwards", start: 3, end: 1)
        r.lineFinished(speaker: 0, text: "nan", start: .nan, end: 3)
        r.lineFinished(speaker: 0, text: "infinite", start: 0, end: .infinity)
        r.lineFinished(speaker: 0, text: "   ", start: 0, end: 3)
        r.lineFinished(speaker: 0, text: "in the future", start: 50, end: 60)
        XCTAssertNil(r.traits(for: 0))
    }

    func testTheSameAudioIsNeverCountedTwice() throws {
        // Parakeet widens a piece's start over the tail it replaces; a repeat must not double the speaker's audio.
        let once = recorder(), twice = recorder()
        let audio = voice(140, seconds: 4)
        feed(once, audio, from: 0); feed(twice, audio, from: 0)
        once.lineFinished(speaker: 0, text: "where is the train station please", start: 0, end: 4)
        for _ in 0..<5 { twice.lineFinished(speaker: 0, text: "where is the train station please", start: 0, end: 4) }
        twice.lineFinished(speaker: 0, text: "station please", start: 2, end: 4)
        XCTAssertEqual(try XCTUnwrap(once.traits(for: 0)), try XCTUnwrap(twice.traits(for: 0)))
        // And overlapping audio goes to the first speaker it was given to, not to both.
        twice.lineFinished(speaker: 1, text: "where is the train station please", start: 0, end: 4)
        XCTAssertNil(twice.traits(for: 1))
    }

    func testMemoryStaysBoundedInALongConversation() {
        let r = recorder()
        let minute = voice(150, seconds: 6)
        for k in 0..<20 { feed(r, minute, from: Double(k) * 6) }
        XCTAssertLessThanOrEqual(r.storedSamples, Int(SpeakerVoiceRecorder.keptSeconds * 16000))
        // A line older than what's kept is skipped, not read from the wrong place.
        r.lineFinished(speaker: 0, text: "long ago", start: 0, end: 3)
        XCTAssertNil(r.traits(for: 0))
        // The latest audio is still there.
        r.lineFinished(speaker: 0, text: "where is the train station", start: 114, end: 120)
        XCTAssertEqual(r.traits(for: 0)?.pitchHz ?? 0, 150, accuracy: 5)
    }

    func testOnlySoManySpeakersAreKept() {
        let r = recorder()
        let n = SpeakerVoiceRecorder.maximumSpeakers + 3
        let line = voice(150, seconds: 2.5)
        for s in 0..<n {
            feed(r, line, from: Double(s) * 2.5)
            r.lineFinished(speaker: s, text: "where is the train station", start: Double(s) * 2.5, end: Double(s + 1) * 2.5)
        }
        XCTAssertNotNil(r.traits(for: 0))
        XCTAssertNil(r.traits(for: n - 1))
    }

    func testANewSessionForgetsEveryone() {
        let r = recorder()
        feed(r, voice(150, seconds: 3), from: 0)
        r.lineFinished(speaker: 0, text: "where is the train station", start: 0, end: 3)
        XCTAssertNotNil(r.traits(for: 0))
        let before = r.session
        r.begin(language: "es-ES")
        XCTAssertNil(r.traits(for: 0))
        XCTAssertEqual(r.storedSamples, 0)
        XCTAssertEqual(r.language, "es-ES")
        XCTAssertGreaterThan(r.session, before)
    }

    func testAGapInTheAudioStartsTheBufferAgain() {
        let r = recorder()
        feed(r, voice(150, seconds: 3), from: 0)
        // The clock jumps (a restart): what came before can't be lined up with times any more.
        feed(r, voice(150, seconds: 1), from: 30)
        r.lineFinished(speaker: 0, text: "where is the train station", start: 0, end: 3)
        XCTAssertNil(r.traits(for: 0))
    }

    func testBrokenSamplesDoNotCrashOrCount() {
        let r = recorder()
        r.feed([], at: 0)
        r.feed([.nan, .infinity, -.infinity], at: .nan)
        feed(r, [Float](repeating: .nan, count: 48000), from: 0)
        r.lineFinished(speaker: 0, text: "where is the train station", start: 0, end: 3)
        XCTAssertNil(r.traits(for: 0))
    }
}

final class EarVoiceChooserTests: XCTestCase {
    private let voices = [calibration("man", hz: 120), calibration("woman", hz: 210), calibration("deep", hz: 90)]
    private let low = SpeakerTraits(pitchHz: 118, syllablesPerSecond: 4.5)
    private let high = SpeakerTraits(pitchHz: 215, syllablesPerSecond: 4.5)

    func testEachSpeakerGetsTheNearestVoice() {
        var c = EarVoiceChooser(voices: voices, normalSyllablesPerSecond: 4.5, defaultVoiceID: "default")
        XCTAssertEqual(c.voice(for: 0, traits: low).voiceID, "man")
        XCTAssertEqual(c.voice(for: 1, traits: high).voiceID, "woman")
    }

    func testNoTraitsYetIsTheUsualVoice() {
        var c = EarVoiceChooser(voices: voices, normalSyllablesPerSecond: 4.5, defaultVoiceID: "default")
        let v = c.voice(for: 0, traits: nil)
        XCTAssertEqual(v, MatchedVoice(voiceID: "default", pitchMultiplier: 1, rate: VoiceMatch.defaultRate))
        XCTAssertEqual(c.voice(for: nil, traits: low), v)
    }

    func testAVoiceNeverJumpsOnceChosen() {
        var c = EarVoiceChooser(voices: voices, normalSyllablesPerSecond: 4.5, defaultVoiceID: "default")
        let first = c.voice(for: 0, traits: low)
        // The profile keeps learning and drifts toward the other voice: the speaker keeps the one they were given.
        XCTAssertEqual(c.voice(for: 0, traits: high), first)
        XCTAssertEqual(c.voice(for: 0, traits: nil), first)
        // A later speaker doesn't change an earlier one.
        _ = c.voice(for: 1, traits: low)
        XCTAssertEqual(c.voice(for: 0, traits: low), first)
    }

    func testTwoSimilarSpeakersStillSoundDifferent() {
        var c = EarVoiceChooser(voices: [calibration("only", hz: 150)], normalSyllablesPerSecond: 4.5, defaultVoiceID: "only")
        let a = c.voice(for: 0, traits: SpeakerTraits(pitchHz: 150, syllablesPerSecond: 4.5))
        let b = c.voice(for: 1, traits: SpeakerTraits(pitchHz: 151, syllablesPerSecond: 4.5))
        XCTAssertNotEqual(a.pitchMultiplier, b.pitchMultiplier)
    }

    func testNoCalibratedVoicesMeansTheUsualVoiceForEveryone() {
        var c = EarVoiceChooser(voices: [], normalSyllablesPerSecond: 4.5, defaultVoiceID: "default")
        XCTAssertFalse(c.canMatch)
        XCTAssertEqual(c.voice(for: 0, traits: low).voiceID, "default")
        XCTAssertEqual(c.voice(for: 0, traits: low).pitchMultiplier, 1)
    }

    func testUnknownNormalPaceKeepsApplesRateButStillMatchesPitch() {
        var c = EarVoiceChooser(voices: voices, normalSyllablesPerSecond: nil, defaultVoiceID: "default")
        let v = c.voice(for: 0, traits: low)
        XCTAssertEqual(v.voiceID, "man")
        XCTAssertEqual(v.rate, VoiceMatch.defaultRate)
        var broken = EarVoiceChooser(voices: voices, normalSyllablesPerSecond: .nan, defaultVoiceID: "default")
        XCTAssertEqual(broken.voice(for: 0, traits: low).rate, VoiceMatch.defaultRate)
    }

    func testBrokenTraitsAreTheUsualVoice() {
        var c = EarVoiceChooser(voices: voices, normalSyllablesPerSecond: 4.5, defaultVoiceID: "default")
        XCTAssertEqual(c.voice(for: 0, traits: SpeakerTraits(pitchHz: .nan, syllablesPerSecond: 4)).voiceID, "default")
        // ...and that speaker can still be matched once real traits arrive.
        XCTAssertEqual(c.voice(for: 0, traits: low).voiceID, "man")
    }

    func testCatchUpStaysUnderTheCap() {
        var c = EarVoiceChooser(voices: voices, normalSyllablesPerSecond: 4.5, defaultVoiceID: "default")
        let v = c.voice(for: 0, traits: SpeakerTraits(pitchHz: 118, syllablesPerSecond: 9))
        XCTAssertLessThanOrEqual(v.rate(catchUp: EarPace.speed(waiting: 50)), VoiceMatch.maximumRateWithCatchUp)
        XCTAssertGreaterThanOrEqual(v.rate(catchUp: .nan), v.rate)
    }
}

final class VoiceCalibrationTableTests: XCTestCase {
    private let json = """
    {"measuredOn":"test","date":"2026-11-09","languages":{
      "es-ES":{"normalSyllablesPerSecond":6.2,"voices":[
        {"id":"es.a","pitchHz":120,"syllablesPerSecond":6,"rateCurve":[{"input":0.5,"value":6}],"pitchCurve":[{"input":1,"value":120}]},
        {"id":"es.broken","pitchHz":0,"syllablesPerSecond":6,"rateCurve":[],"pitchCurve":[]}]},
      "en-US":{"normalSyllablesPerSecond":4.6,"voices":[]},
      "en-GB":{"normalSyllablesPerSecond":4.4,"voices":[]}}}
    """

    func testOnlyInstalledUsableVoicesOfTheSameLocale() throws {
        let t = try VoiceCalibrationTable(json: Data(json.utf8))
        XCTAssertEqual(t.voices(for: "es-ES", installed: ["es.a", "es.broken"]).map(\.id), ["es.a"])
        XCTAssertEqual(t.voices(for: "es-ES", installed: []).map(\.id), [])
        XCTAssertEqual(t.voices(for: "es-MX", installed: ["es.a"]).map(\.id), [])
    }

    func testNormalPaceForTheCaptionLanguage() throws {
        let t = try VoiceCalibrationTable(json: Data(json.utf8))
        XCTAssertEqual(t.normalPace(for: "en-GB"), 4.4)
        // A language without its region: the same language's first region, the same answer every time.
        XCTAssertEqual(t.normalPace(for: "en"), 4.4)
        XCTAssertEqual(t.normalPace(for: "en_US"), 4.6)
        XCTAssertNil(t.normalPace(for: "he"))
        XCTAssertNil(t.normalPace(for: nil))
        XCTAssertNil(t.normalPace(for: ""))
    }

    func testABrokenTableIsAnError() {
        XCTAssertThrowsError(try VoiceCalibrationTable(json: Data("not json".utf8)))
        XCTAssertThrowsError(try VoiceCalibrationTable(json: Data()))
    }

    func testTheShippedTableLoadsAndCoversSpanish() {
        let t = VoiceCalibrationTable.shipped
        XCTAssertFalse(t.languages.isEmpty, "the shipped table didn't decode")
        let spanish = t.languages["es-ES"]?.voices ?? []
        XCTAssertGreaterThanOrEqual(spanish.count, 2)
        for language in t.languages.values {
            XCTAssertTrue(language.normalSyllablesPerSecond.isFinite)
            for v in language.voices {
                XCTAssertGreaterThan(v.pitchHz, 50, v.id)
                XCTAssertLessThan(v.pitchHz, 450, v.id)
                XCTAssertFalse(v.pitchCurve.isEmpty, v.id)
            }
        }
        XCTAssertNotNil(t.normalPace(for: "en-US"))
    }
}

final class EarMatchStateTests: XCTestCase {
    func testStates() {
        XCTAssertEqual(EarMatchState(on: false, voices: 3), .off)
        XCTAssertEqual(EarMatchState(on: true, voices: 0), .oneVoice)
        XCTAssertEqual(EarMatchState(on: true, voices: 1), .matching)
        XCTAssertEqual(EarMatchState(on: true, voices: -1), .oneVoice)
    }
}

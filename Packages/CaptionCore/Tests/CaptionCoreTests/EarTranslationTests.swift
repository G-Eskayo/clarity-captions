import CaptionCore
import XCTest

/// #233 Live Translation in your ear, the owner's answers on #238: what gets spoken and when (the first phrase sooner,
/// once its words stop changing, the rest when finished), speaking a little faster to catch up and never skipping,
/// any headphones but never the iPhone's speaker, "captions only" when the language has no voice, and the iPhone's
/// own mic listening while the headphones only play.
final class EarPhrasesTests: XCTestCase {
    private var stream = CaptionStream()
    private var phrases = EarPhrases()

    /// `from`: where the engine's segment starts; a revision of words still changing starts where they did.
    private func say(_ text: String, final: Bool, at t: Double, from: Double? = nil) -> [EarPhrases.Phrase] {
        stream.apply(text: text, isFinal: final, speaker: 0, range: (from ?? t)...(t + 0.5))
        return phrases.take(from: stream.lines, now: t)
    }

    func testAFinishedLineIsSpokenOnce() {
        let out = say("¿Dónde está la estación?", final: true, at: 0)
        XCTAssertEqual(out.map(\.text), ["¿Dónde está la estación?"])
        XCTAssertEqual(out.first?.early, false)
        XCTAssertTrue(phrases.take(from: stream.lines, now: 1).isEmpty, "never twice")
    }

    func testOnlyTheNewWordsOfAGrowingLineAreSpoken() {
        _ = say("Buenos días", final: true, at: 0)
        let out = say("¿cómo estás?", final: true, at: 0.8)
        XCTAssertEqual(stream.lines.count, 1, "one line, grown")
        XCTAssertEqual(out.map(\.text), ["¿cómo estás?"])
        XCTAssertEqual(out.first?.words, 2..<4)
    }

    func testWordsStillChangingWaitUntilTheyHoldStill() {
        XCTAssertTrue(say("la estación de", final: false, at: 0).isEmpty)
        XCTAssertTrue(phrases.take(from: stream.lines, now: EarPhrases.defaultHold - 0.1).isEmpty)
        XCTAssertEqual(phrases.nextCheck, EarPhrases.defaultHold, "the app looks again when they've held still long enough")
    }

    func testTheFirstPhraseIsSpokenOnceItsWordsHoldStill() {
        _ = say("la estación de", final: false, at: 0)
        _ = say("la estación de tren", final: false, at: 0.3, from: 0)
        let out = phrases.take(from: stream.lines, now: EarPhrases.defaultHold + 0.05)
        XCTAssertEqual(out.map(\.text), ["la estación de"], "the steady words only; 'tren' arrived later")
        XCTAssertEqual(out.first?.early, true)
    }

    func testAChangedWordRestartsTheWait() {
        _ = say("la estación del", final: false, at: 0)
        _ = say("la estación de tren", final: false, at: 0.5, from: 0)
        XCTAssertTrue(phrases.take(from: stream.lines, now: EarPhrases.defaultHold + 0.1).isEmpty,
                      "only 2 words held still; a phrase needs \(EarPhrases.minimumEarlyWords)")
        XCTAssertEqual(phrases.take(from: stream.lines, now: 0.5 + EarPhrases.defaultHold).map(\.text), ["la estación de tren"])
    }

    func testFewerThanThreeSteadyWordsWaitForTheFinish() {
        _ = say("Gracias", final: false, at: 0)
        XCTAssertTrue(phrases.take(from: stream.lines, now: 5).isEmpty)
        XCTAssertNil(phrases.nextCheck)
        XCTAssertEqual(say("Gracias", final: true, at: 5.1, from: 0).map(\.text), ["Gracias"])
    }

    func testAfterTheEarlyPhraseTheRestComesWhenTheLineIsFinished() {
        _ = say("la estación de tren", final: false, at: 0)
        XCTAssertEqual(phrases.take(from: stream.lines, now: 1).map(\.text), ["la estación de tren"])
        // Only the first phrase goes early: the rest waits for the finish, so a sentence isn't cut into scraps.
        _ = say("la estación de tren está cerca", final: false, at: 1.2, from: 0)
        XCTAssertTrue(phrases.take(from: stream.lines, now: 3).isEmpty)
        let out = say("la estación de tren está muy cerca", final: true, at: 3.1, from: 0)
        XCTAssertEqual(out.map(\.text), ["está muy cerca"])
        XCTAssertEqual(out.first?.early, false)
        XCTAssertEqual(out.first?.words, 4..<7)
    }

    func testAnEarlyPhraseThatTurnsOutWrongIsNotSpokenAgain() {
        // It can't be taken back (the option the owner chose says so); the finish speaks only what's past it.
        _ = say("la estación del tren", final: false, at: 0)
        _ = phrases.take(from: stream.lines, now: 1)
        XCTAssertEqual(say("las estaciones de tren", final: true, at: 1.1, from: 0).map(\.text), [])
    }

    func testEarlyCanBeTurnedOff() {
        var finishedOnly = EarPhrases(speaksEarly: false)
        stream.apply(text: "la estación de tren", isFinal: false, speaker: 0, range: 0...0.5)
        XCTAssertTrue(finishedOnly.take(from: stream.lines, now: 10).isEmpty)
        XCTAssertNil(finishedOnly.nextCheck)
    }

    func testSoundLabelsAndFaceToFaceLinesAreNeverSpoken() {
        var s = CaptionStream()
        s.apply(text: "hola amigo mío", isFinal: true, speaker: 0, range: 0...1, lane: .partner)
        XCTAssertTrue(phrases.take(from: s.lines, now: 1).isEmpty, "face to face has its own screen; the ear is one-way")
    }

    func testTurningItOnMidConversationSpeaksOnlyWhatComesNext() {
        stream.apply(text: "Esto ya se dijo", isFinal: true, speaker: 0, range: 0...1)
        phrases.skip(stream.lines)
        XCTAssertTrue(phrases.take(from: stream.lines, now: 2).isEmpty)
        XCTAssertEqual(say("y esto es nuevo", final: true, at: 1.1).map(\.text), ["y esto es nuevo"])
    }

    func testANewConversationStartsClean() {
        _ = say("Hola", final: true, at: 0)
        phrases.reset()
        stream = CaptionStream()
        XCTAssertEqual(say("Hola", final: true, at: 0).map(\.text), ["Hola"])
    }
}

final class EarPaceTests: XCTestCase {
    func testNormalSpeedWhenNothingIsWaiting() {
        XCTAssertEqual(EarPace.speed(waiting: 0), 1.0)
    }

    func testALittleFasterTheFurtherBehindCappedSoItStaysClear() {
        XCTAssertGreaterThan(EarPace.speed(waiting: 1), 1.0)
        XCTAssertGreaterThan(EarPace.speed(waiting: 2), EarPace.speed(waiting: 1))
        XCTAssertEqual(EarPace.speed(waiting: 50), EarPace.maximumSpeed)
        XCTAssertLessThanOrEqual(EarPace.maximumSpeed, 1.3)
    }
}

final class EarRouteTests: XCTestCase {
    func testAnyHeadphonesBluetoothOrWired() {
        for port in ["Headphones", "BluetoothA2DPOutput", "BluetoothLE", "BluetoothHFP", "USBAudio"] {
            XCTAssertTrue(EarRoute.canSpeak(outputs: [port]), port)
        }
    }

    func testNeverTheIPhonesSpeakerOrAnythingTheRoomHears() {
        for port in ["Speaker", "Receiver", "AirPlay", "HDMI", "CarAudio", "LineOut"] {
            XCTAssertFalse(EarRoute.canSpeak(outputs: [port]), port)
        }
        XCTAssertFalse(EarRoute.canSpeak(outputs: []))
        XCTAssertFalse(EarRoute.canSpeak(outputs: ["Speaker", "Headphones"]), "if any of it reaches the room, no")
    }
}

final class EarStateTests: XCTestCase {
    func testOffIsOff() {
        XCTAssertEqual(EarState(on: false, hasVoice: false, headphones: false), .off)
    }

    func testNoVoiceMeansCaptionsOnlyWhateverIsConnected() {
        XCTAssertEqual(EarState(on: true, hasVoice: false, headphones: true), .noVoice)
    }

    func testOnWithoutHeadphonesWaitsForThem() {
        XCTAssertEqual(EarState(on: true, hasVoice: true, headphones: false), .noHeadphones)
        XCTAssertFalse(EarState.noHeadphones.speaks)
    }

    func testOnWithAVoiceAndHeadphonesSpeaks() {
        XCTAssertEqual(EarState(on: true, hasVoice: true, headphones: true), .speaking)
        XCTAssertTrue(EarState.speaking.speaks)
    }
}

final class EarProgressTests: XCTestCase {
    func testTheShownTranslationFirmsUpAsTheLineIsSaid() {
        // 8 words said, the first 4 already spoken, half of the next 4 under way: 6 of 8, so 3 of 4 shown words.
        XCTAssertEqual(EarProgress.firmWords(shown: 4, lineWords: 8, phrase: 4..<8, share: 0.5), 3)
    }

    func testNothingFirmBeforeItStartsAndAllWhenDone() {
        XCTAssertEqual(EarProgress.firmWords(shown: 5, lineWords: 5, phrase: 0..<5, share: 0), 0)
        XCTAssertEqual(EarProgress.firmWords(shown: 5, lineWords: 5, phrase: 0..<5, share: 1), 5)
    }

    func testOddInputsStayInRange() {
        XCTAssertEqual(EarProgress.firmWords(shown: 3, lineWords: 0, phrase: 0..<0, share: 2), 3)
        XCTAssertEqual(EarProgress.firmWords(shown: 3, lineWords: 4, phrase: 2..<9, share: -1), 2, "half the line said before it")
    }
}

/// ADR 0021 and the owner's mic answer (C): the iPhone's own mic listens, the headphones only play. A2DP, never the
/// Bluetooth call profile, never the iPhone's speaker. With the ear off, nothing changes from before.
final class MicSessionSetupTests: XCTestCase {
    func testEarOffIsWhatItAlwaysWas() {
        XCTAssertEqual(MicSessionSetup(micMode: .standard, speaksIntoEar: false),
                       MicSessionSetup(category: .record, mode: .default, defaultToSpeaker: false, allowsBluetoothA2DP: false, prefersBuiltInMic: false))
        XCTAssertEqual(MicSessionSetup(micMode: .raw, speaksIntoEar: false).category, .record)
        XCTAssertEqual(MicSessionSetup(micMode: .raw, speaksIntoEar: false).mode, .measurement)
        XCTAssertEqual(MicSessionSetup(micMode: .voiceProcessing, speaksIntoEar: false),
                       MicSessionSetup(category: .playAndRecord, mode: .default, defaultToSpeaker: true, allowsBluetoothA2DP: false, prefersBuiltInMic: false))
    }

    func testEarOnPlaysIntoHeadphonesAndKeepsTheIPhonesMic() {
        for mode in MicMode.allCases {
            let setup = MicSessionSetup(micMode: mode, speaksIntoEar: true)
            XCTAssertEqual(setup.category, .playAndRecord, "\(mode)")
            XCTAssertTrue(setup.allowsBluetoothA2DP, "\(mode)")
            XCTAssertFalse(setup.defaultToSpeaker, "never the speaker, \(mode)")
            XCTAssertTrue(setup.prefersBuiltInMic, "a wired headset's mic doesn't take over, \(mode)")
        }
        XCTAssertEqual(MicSessionSetup(micMode: .raw, speaksIntoEar: true).mode, .measurement, "the mic mode's own mode stays")
    }
}

import CaptionCore
import XCTest

/// Owner's note on PR #231 (2026-10-30): "a Spanish speaker sitting next to an English speaker, and they're calling a
/// French speaker, and the English speaker is trying to understand everything", and "people with multiple different
/// languages on the same call". Each finished line is translated from the language its words are in, among the
/// languages already set up for this conversation (Room, Calls), when that side's engine hears several (Parakeet).
/// A line in her language is left alone, wherever it came from. A line sure to be in a language nobody set up is shown
/// as said: nothing downloads mid-call (owner's rule).
final class MacTranslationLanguagesTests: XCTestCase {
    private let en = Locale(identifier: "en-US")
    private let es = Locale(identifier: "es-MX")
    private let fr = Locale(identifier: "fr-FR")
    private let de = Locale(identifier: "de-DE")
    private let ja = Locale(identifier: "ja-JP")

    /// A finished line per (text, speaker).
    private func lines(_ said: [(String, Int?)]) -> [CaptionLine] {
        var s = CaptionStream()
        for (text, speaker) in said {
            s.apply(text: text, isFinal: true, speaker: speaker)
            s.breakLine()
        }
        return s.lines
    }

    private func line(_ text: String, speaker: Int? = 0) -> CaptionLine { lines([(text, speaker)])[0] }

    /// A fake detector: the language named after "lang:" in the text, sure; anything else unsure.
    private static func fake(_ text: String) -> (code: String, probability: Double)? {
        guard let r = text.range(of: "lang:") else { return nil }
        let code = text[r.upperBound...].prefix { $0.isLetter }
        return (String(code), 1.0)
    }

    private func router(room: Locale, call: Locale, into: Locale,
                        guess: @escaping MacTranslationRouter.Guess = MacTranslationLanguagesTests.fake) -> MacTranslationRouter {
        MacTranslationRouter(MacTranslation(room: room, call: call, into: into), guess: guess)
    }

    private func pair(_ from: Locale, _ into: Locale) -> MacTranslation.Pair { .init(from: from, into: into) }

    // MARK: the owner's scenario

    func testTheOwnersScenarioSpanishBesideHerFrenchOnTheCallSheReadsEnglish() {
        var r = router(room: es, call: fr, into: en, guess: MacTranslationRouter.naturalLanguage)
        let neighbour = line("Creo que deberíamos preguntarle por el contrato nuevo.", speaker: 0)
        let her = line("Yes, I think we should ask her about the new contract.", speaker: 1)
        let dana = line("Bonjour, je vous entends très bien, on peut commencer la réunion.", speaker: 0)
        // No headphones: the Mac's mic hears her and the Spanish speaker beside her.
        let mic = MacAudioSide(source: .microphone, onCall: true, mic: .room)
        XCTAssertEqual(r.pair(for: neighbour, side: mic), pair(es, en))
        XCTAssertNil(r.pair(for: her, side: mic), "her own words are in her language: never translated")
        XCTAssertEqual(r.pair(for: dana, side: .theirs), pair(fr, en))
    }

    func testWithAHeadsetHerWordsAreNeverTranslatedEvenInAnotherLanguage() {
        var r = router(room: es, call: fr, into: en)
        let side = MacAudioSide(source: .microphone, onCall: true, mic: .headset)
        XCTAssertNil(r.pair(for: line("Hola lang:es", speaker: 0), side: side))
    }

    // MARK: several languages on one call

    func testACallerSpeakingTheRoomsLanguageIsTranslatedFromIt() {
        // A French call, but one caller speaks Spanish, the room's language: already set up, so it's translated.
        var r = router(room: es, call: fr, into: en)
        XCTAssertEqual(r.pair(for: line("¿Y tú, qué opinas ahora? lang:es", speaker: 2), side: .theirs), pair(es, en))
        XCTAssertEqual(r.pair(for: line("Et toi, tu en penses quoi? lang:fr", speaker: 1), side: .theirs), pair(fr, en))
    }

    func testDetectedLanguageKeepsTheSetRegionSoOneTranslatorServesIt() {
        var r = router(room: es, call: fr, into: en)
        XCTAssertEqual(r.pair(for: line("Vale, nos vemos luego entonces lang:es"), side: .theirs)?.from.identifier(.bcp47), "es-MX")
    }

    func testALanguageNobodySetUpIsShownAsSaidNeverDownloaded() {
        var r = router(room: es, call: fr, into: en)
        XCTAssertNil(r.pair(for: line("Guten Tag, wie geht es euch? lang:de", speaker: 3), side: .theirs),
                     "German isn't set up: no translator, and nothing downloads mid-call")
    }

    func testAShortLineFollowsItsVoicesLastSureLanguage() {
        var r = router(room: es, call: fr, into: en)
        _ = r.pair(for: line("Una frase larga en español lang:es", speaker: 2), side: .theirs)
        XCTAssertEqual(r.pair(for: line("Sí.", speaker: 2), side: .theirs), pair(es, en), "too short to tell: the voice's language")
        XCTAssertEqual(r.pair(for: line("Oui.", speaker: 1), side: .theirs), pair(fr, en), "an unheard voice: the side's language")
    }

    func testAVoiceSureToSpeakAnUnsetLanguageStaysUntranslatedOnShortLines() {
        var r = router(room: es, call: fr, into: en)
        _ = r.pair(for: line("Guten Tag, wie geht es euch? lang:de", speaker: 3), side: .theirs)
        XCTAssertNil(r.pair(for: line("Ja.", speaker: 3), side: .theirs))
    }

    func testVoicesOnDifferentStreamsDontShareMemory() {
        // Each stream has its own speaker model, so speaker 0 on the call and speaker 0 in the room are different people.
        var r = router(room: es, call: fr, into: en)
        _ = r.pair(for: line("Guten Tag, wie geht es euch? lang:de", speaker: 0), side: .theirs)
        XCTAssertEqual(r.pair(for: line("Sí.", speaker: 0), side: .room), pair(es, en))
    }

    func testAVoiceThatChangesLanguageIsFollowed() {
        var r = router(room: es, call: fr, into: en)
        _ = r.pair(for: line("Primero hablo en español aquí lang:es", speaker: 1), side: .theirs)
        _ = r.pair(for: line("Puis je parle en français ici lang:fr", speaker: 1), side: .theirs)
        XCTAssertEqual(r.pair(for: line("Oui.", speaker: 1), side: .theirs), pair(fr, en))
    }

    func testAVoiceThatSwitchesToHerLanguageIsLeftAloneOnShortLinesToo() {
        var r = router(room: es, call: fr, into: en)
        _ = r.pair(for: line("Thanks so much, everyone here lang:en", speaker: 1), side: .theirs)
        XCTAssertNil(r.pair(for: line("OK.", speaker: 1), side: .theirs))
    }

    // MARK: an engine that hears one language

    func testAnEngineThatHearsOneLanguageNeverSwitchesToAnotherSidesLanguage() {
        // Apple's Japanese engine writes Japanese whatever is said (E27): a French verdict on its words is noise.
        var r = router(room: ja, call: fr, into: en)
        XCTAssertNil(r.pair(for: line("some noise words heard here lang:fr"), side: .room), "sure of a language it can't hear: shown as said")
        XCTAssertEqual(r.pair(for: line("こんにちは、今日はいい天気ですね、本当に lang:ja"), side: .room), pair(ja, en))
        XCTAssertNil(r.pair(for: line("Hello there, how are you all lang:en"), side: .room), "her language is still left alone")
    }

    func testTheRoomInHerLanguageStillTranslatesASpeakerOfTheCallsLanguageBesideHer() {
        // Room English (her language) on Parakeet, call French: a French speaker in the room is caught too.
        var r = router(room: en, call: fr, into: en)
        XCTAssertEqual(r.pair(for: line("Bonjour à tous, ça va bien lang:fr"), side: .room), pair(fr, en))
        XCTAssertNil(r.pair(for: line("Hi everyone, good morning to you lang:en"), side: .room))
        XCTAssertNil(r.pair(for: line("Hi."), side: .room), "unsure, and the room is her language: left alone")
    }

    func testPairsCoverEveryLanguageALineCanBeTranslatedFrom() {
        XCTAssertEqual(MacTranslation(room: en, call: fr, into: en).pairs, [pair(fr, en)])
        XCTAssertEqual(MacTranslation(room: ja, call: fr, into: en).pairs, [pair(ja, en), pair(fr, en)])
        XCTAssertEqual(MacTranslation(room: es, call: fr, into: en).pairs, [pair(es, en), pair(fr, en)])
    }

    // MARK: bad input

    func testUnfinishedLinesWaitAndAreNotRemembered() {
        var s = CaptionStream()
        s.apply(text: "Bonjour lang:de", isFinal: false, speaker: 0)
        var r = router(room: es, call: fr, into: en)
        XCTAssertNil(r.pair(for: s.lines[0], side: .theirs), "translated once finished, as on the iPhone")
        XCTAssertEqual(r.pair(for: line("Oui.", speaker: 0), side: .theirs), pair(fr, en), "the grey words taught nothing")
    }

    func testEmptyAndPunctuationOnlyLinesAreNotTranslated() {
        var r = router(room: es, call: fr, into: en)
        var checked = 0
        for text in ["   ", "...", "?!", "—", "123 456 789 000"] {
            // The stream drops a blank line itself; whatever it keeps has no letters to translate.
            for l in lines([(text, 0)]) {
                XCTAssertNil(r.pair(for: l, side: .theirs), "'\(text)'")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testSoundLabelsAreNotTranslated() throws {
        var s = CaptionStream()
        s.insertSoundLabel(.laughter)
        var r = router(room: es, call: fr, into: en)
        let label = try XCTUnwrap(s.lines.first(where: \.isSoundLabel))
        XCTAssertNil(r.pair(for: label, side: .theirs))
    }

    func testAnUnsureOrBrokenGuessFallsBackToTheSidesLanguage() {
        for bad: (String, Double)? in [nil, ("fr", 0.5), ("es", .nan), ("es", -1), ("", 1), ("zz", 1.0)] {
            var r = router(room: es, call: fr, into: en, guess: { _ in bad })
            let p = r.pair(for: line("Quelque chose de long à dire ici", speaker: 1), side: .theirs)
            if bad?.0 == "zz" {
                XCTAssertNil(p, "sure of an unknown code: shown as said")
            } else {
                XCTAssertEqual(p, pair(fr, en), "\(String(describing: bad))")
            }
        }
    }

    func testASureGuessOnFewerThanFourWordsIsNotTrusted() {
        // The face-to-face measurements (#60, #208): 4+ words and 99% sure before a language is trusted.
        var r = router(room: es, call: fr, into: en, guess: { _ in ("es", 1) })
        XCTAssertEqual(r.pair(for: line("Sí, claro.", speaker: 4), side: .theirs), pair(fr, en))
        XCTAssertEqual(r.pair(for: line("Ah.", speaker: 4), side: .theirs), pair(fr, en), "and nothing was remembered for the voice")
    }

    func testAGuessAboveOneIsNotTrustedAsSure() {
        var r = router(room: es, call: fr, into: en, guess: { _ in ("es", 7) })
        XCTAssertEqual(r.pair(for: line("Quelque chose de long à dire ici"), side: .theirs), pair(fr, en))
    }

    func testYoursAndUnknownSidesAreNeverTranslatedWhateverTheWords() {
        var r = router(room: es, call: fr, into: en)
        XCTAssertNil(r.pair(for: line("Hola lang:es"), side: .yours))
        XCTAssertTrue(r.lines([line("Hola lang:es")], for: pair(es, en)) { _ in nil }.isEmpty)
    }

    // MARK: repeats

    func testAFinishedLineIsDecidedOnceAndGuessedOnce() {
        var calls = 0
        var r = router(room: es, call: fr, into: en, guess: { text in calls += 1; return MacTranslationLanguagesTests.fake(text) })
        let l = line("Hola amigos, buenos días a todos lang:es", speaker: 1)
        for _ in 0..<5 { XCTAssertEqual(r.pair(for: l, side: .theirs), pair(es, en)) }
        XCTAssertEqual(calls, 1, "the translate loop asks again on every update: the language is worked out once")
    }

    func testARevisedLineIsDecidedAgain() {
        var r = router(room: es, call: fr, into: en)
        var s = CaptionStream()
        s.apply(text: "Hola amigos, buenos días a todos lang:es", isFinal: true, speaker: 1)
        XCTAssertEqual(r.pair(for: s.lines[0], side: .theirs), pair(es, en))
        var revised = CaptionStream()
        revised.apply(text: "Bonjour mes amis, comment ça va lang:fr", isFinal: true, speaker: 1)
        XCTAssertEqual(revised.lines[0].id, s.lines[0].id)
        XCTAssertEqual(r.pair(for: revised.lines[0], side: .theirs), pair(fr, en))
    }

    func testLinesForAPairKeepTheirOrderAcrossManyCalls() {
        let said = lines([("Uno dos tres cuatro lang:es", 1), ("Un deux trois quatre lang:fr", 2), ("Cinco seis siete ocho lang:es", 1),
                          ("Hello there, how are you all lang:en", 3)])
        var r = router(room: es, call: fr, into: en)
        for _ in 0..<3 {
            XCTAssertEqual(r.lines(said, for: pair(es, en)) { _ in .theirs }.map(\.text), ["Uno dos tres cuatro lang:es", "Cinco seis siete ocho lang:es"])
            XCTAssertEqual(r.lines(said, for: pair(fr, en)) { _ in .theirs }.map(\.text), ["Un deux trois quatre lang:fr"])
        }
    }

    // MARK: Apple's NaturalLanguage, on the device (nothing downloads)

    func testTheDeviceDetectorIsSureOfFullSentencesAndNotOfOneWord() {
        let guess = MacTranslationRouter.naturalLanguage
        XCTAssertEqual(guess("Je pense que nous devrions commencer la réunion maintenant.")?.code, "fr")
        XCTAssertEqual(guess("Creo que deberíamos empezar la reunión ahora mismo.")?.code, "es")
        XCTAssertEqual(guess("I think we should start the meeting right now.")?.code, "en")
        XCTAssertNil(guess(""))
    }
}

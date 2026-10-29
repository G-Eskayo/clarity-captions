import CaptionCore
import XCTest

/// #208, items 1–2 wired (the owner's answers on PR #216, 2026-10-29): each half picks its language and starts on the
/// tap; once both have picked, voices are matched between those two languages only; one half picked captions
/// everything on it, untranslated; Stop is there from the start; captions that stop on their own leave the split
/// paused, and Start carries on with both languages. Tap a half's language name to pick again.
final class FaceToFaceSplitTests: XCTestCase {
    private let en = Locale(identifier: "en-US")
    private let es = Locale(identifier: "es-ES")
    private let fr = Locale(identifier: "fr-FR")
    private let downloaded = ["en-US", "es-ES", "fr-FR"].map(Locale.init(identifier:))
    private func name(_ l: Locale) -> String {
        ["en": "English", "es": "Español", "fr": "Français"][l.language.languageCode?.identifier ?? ""] ?? l.identifier
    }
    private func ids(_ ls: [Locale]) -> [String] { ls.map(\.identifier) }
    private func choices(_ split: FaceToFaceSplit, _ half: FaceToFaceHalf) -> [String] {
        ids(split.choices(for: half, downloaded: downloaded, name: name))
    }

    /// Lines the way engines write them: one-way (no lane) while one half has picked, per lane once both have.
    private func say(_ s: inout CaptionStream, _ text: String, speaker: Int, lane: FaceToFaceHalf? = nil, at t: Double) {
        s.apply(text: text, isFinal: true, speaker: speaker, range: t...(t + 2), lane: lane)
    }

    /// A voice matched the way the engine matches it: four sure words of `half`'s language.
    private func matched(_ speaker: Int, to half: FaceToFaceHalf, in languages: inout SpeakerLanguages) {
        let words = (0..<4).map { TimedWord(text: "w\($0)", start: Double($0), end: Double($0) + 0.3) }
        languages.heard(speaker: speaker, lane: half, words: words, isFinal: true) { _ in [half: 1, half.other: 0] }
    }

    // MARK: nothing picked

    func testTheSplitOpensWithBothListsAndNoCaptions() {
        let split = FaceToFaceSplit()
        XCTAssertTrue(split.showsList(.owner))
        XCTAssertTrue(split.showsList(.partner))
        XCTAssertNil(split.captions)
        XCTAssertNil(split.languagePair)
        XCTAssertEqual(choices(split, .owner), ["en-US", "es-ES", "fr-FR"])
        XCTAssertEqual(choices(split, .partner), ["en-US", "es-ES", "fr-FR"])
    }

    func testStopIsInTheOwnersHalfBeforeAnyonePicks() {
        XCTAssertEqual(FaceToFaceSplit().control, .stop)
    }

    func testLinesFromBeforeTheSplitShowAsSaidOnBothHalves() {
        var s = CaptionStream()
        say(&s, "Hello there, nice to meet you", speaker: 0, at: 0)
        let split = FaceToFaceSplit(opening: s.lines)
        XCTAssertNil(split.half(of: s.lines[0], languages: SpeakerLanguages()))
        XCTAssertEqual(split.shown(s.lines, languages: SpeakerLanguages()).count, 1)
    }

    // MARK: one half picked

    func testATapStartsThatHalfAloneInItsLanguage() {
        var split = FaceToFaceSplit()
        XCTAssertTrue(split.pick(en, for: .owner), "the tap starts captions")
        XCTAssertEqual(split.captions, .one(.owner, en))
        XCTAssertFalse(split.showsList(.owner))
        XCTAssertTrue(split.showsList(.partner))
        XCTAssertEqual(split.language(of: .owner), en)
        XCTAssertNil(split.language(of: .partner))
    }

    func testTheOtherPersonsListLeavesOutTheLanguageTaken() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        XCTAssertEqual(choices(split, .partner), ["es-ES", "fr-FR"])
        // The other way round too: the person across picks first.
        var other = FaceToFaceSplit()
        other.pick(es, for: .partner)
        XCTAssertEqual(other.captions, .one(.partner, es))
        XCTAssertEqual(choices(other, .owner), ["en-US", "fr-FR"])
    }

    func testWithOneHalfPickedEverythingIsCaptionedOnItAsSaidAndNothingIsTranslated() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.sessionStarted()
        var s = CaptionStream()
        say(&s, "So where are you from", speaker: 0, at: 0)
        say(&s, "Soy de Madrid pero vivo aquí", speaker: 1, at: 3)   // the other person, written by the English engine
        let languages = SpeakerLanguages()
        XCTAssertEqual(s.lines.map { split.half(of: $0, languages: languages) }, [.owner, .owner])
        XCTAssertEqual(split.shown(s.lines, languages: languages).count, 2)
        XCTAssertNil(split.languagePair, "nothing is translated until the other half picks")
    }

    func testASoundLabelBelongsToNeitherHalf() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.sessionStarted()
        var s = CaptionStream()
        s.insertSoundLabel(.laughter)
        XCTAssertNil(split.half(of: s.lines[0], languages: SpeakerLanguages()))
    }

    // MARK: both picked

    func testTheSecondPickRestartsCaptionsInBothLanguages() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        XCTAssertTrue(split.pick(es, for: .partner))
        XCTAssertEqual(split.captions, .both(owner: en, partner: es))
        XCTAssertEqual(split.languagePair?.owner, en)
        XCTAssertEqual(split.languagePair?.partner, es)
        XCTAssertFalse(split.showsList(.owner))
        XCTAssertFalse(split.showsList(.partner))
    }

    func testVoicesAreMatchedOnlyBetweenTheTwoPickedLanguages() {
        var split = FaceToFaceSplit()
        split.pick(fr, for: .owner)
        split.pick(es, for: .partner)
        // Not the caption language or the Into language from Settings: the two the halves picked.
        let pair = split.languagePair
        XCTAssertEqual(pair?.owner, fr)
        XCTAssertEqual(pair?.partner, es)
        let p = pair?.probabilities("¿Dónde está la estación de tren, por favor?") ?? [:]
        XCTAssertGreaterThan(p[.partner] ?? 0, 0.9)
    }

    func testOnceBothHavePickedEachVoicesHalfComesFromItsLanguage() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.pick(es, for: .partner)
        split.sessionStarted()
        var s = CaptionStream()
        say(&s, "Where is the station please", speaker: 0, lane: .owner, at: 0)
        say(&s, "La estación está muy cerca", speaker: 1, lane: .partner, at: 3)
        var languages = SpeakerLanguages()
        XCTAssertEqual(s.lines.map { split.half(of: $0, languages: languages) }, [nil, nil], "nobody is matched yet")
        matched(0, to: .owner, in: &languages)
        matched(1, to: .partner, in: &languages)
        XCTAssertEqual(s.lines.map { split.half(of: $0, languages: languages) }, [.owner, .partner])
    }

    func testLinesCaptionedWhileOneHalfHadPickedStayOnItAfterTheSecondPick() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.sessionStarted()
        var s = CaptionStream()
        say(&s, "Hi, I'm Gil, take a seat", speaker: 0, at: 0)
        split.pick(es, for: .partner)
        // The one-language session ends before the two-language one starts.
        XCTAssertTrue(split.sessionEnded(s.lines, languages: SpeakerLanguages()).isEmpty)
        split.sessionStarted()
        // The new session numbers voices afresh: its speaker 0 is the other person, matched to Spanish.
        var languages = SpeakerLanguages()
        matched(0, to: .partner, in: &languages)
        XCTAssertEqual(split.half(of: s.lines[0], languages: languages), .owner)
        XCTAssertEqual(split.shown(s.lines, languages: languages).map(\.id), [s.lines[0].id])
        // Now that both halves have picked, those lines are translated like the rest of her half's lines.
        XCTAssertNotNil(split.languagePair)
    }

    func testTheOtherEnginesTryAtTheSameWordsGoesWhenASessionEnds() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.pick(es, for: .partner)
        split.sessionStarted()
        var s = CaptionStream()
        say(&s, "Where is the station please", speaker: 0, lane: .owner, at: 0)
        say(&s, "Wear is the stay shun", speaker: 0, lane: .partner, at: 0.1)
        var languages = SpeakerLanguages()
        matched(0, to: .owner, in: &languages)
        let gone = split.sessionEnded(s.lines, languages: languages)
        XCTAssertEqual(gone, [s.lines[1].id])
        XCTAssertNil(split.running)
        // Settled: a later session's numbering can't hide or move the kept line.
        var later = SpeakerLanguages()
        matched(0, to: .partner, in: &later)
        XCTAssertEqual(split.half(of: s.lines[0], languages: later), .owner)
        XCTAssertTrue(split.isShown(s.lines[0], languages: later))
    }

    func testAKeptLineStaysShownWhenTheNextSessionNumbersItsVoiceForTheOtherLanguage() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.pick(es, for: .partner)
        split.sessionStarted()
        var s = CaptionStream()
        say(&s, "Where is the station please", speaker: 0, lane: .owner, at: 0)
        var languages = SpeakerLanguages()
        matched(0, to: .owner, in: &languages)
        split.sessionEnded(s.lines, languages: languages)
        // Start again: in the new session, voice 0 is the other person, matched to Spanish. Her old line is in the
        // English engine's lane, which that voice no longer shows; it was settled, so it stays.
        split.stoppedOnTheirOwn()
        XCTAssertTrue(split.resume())
        split.sessionStarted()
        var next = SpeakerLanguages()
        matched(0, to: .partner, in: &next)
        XCTAssertTrue(split.isShown(s.lines[0], languages: next))
        XCTAssertEqual(split.half(of: s.lines[0], languages: next), .owner)
    }

    // MARK: picking again

    func testTappingTheLanguageNameOpensTheListWithoutStoppingAnything() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.pick(es, for: .partner)
        split.sessionStarted()
        split.openList(.owner)
        XCTAssertTrue(split.showsList(.owner))
        XCTAssertFalse(split.showsList(.partner))
        XCTAssertEqual(split.captions, .both(owner: en, partner: es), "captions carry on while she looks")
        // Her own language stays in her list (tapping it again changes nothing); the other half's is left out.
        XCTAssertEqual(choices(split, .owner), ["en-US", "fr-FR"])
    }

    func testPickingTheSameLanguageAgainJustClosesTheList() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.pick(es, for: .partner)
        split.openList(.partner)
        XCTAssertFalse(split.pick(es, for: .partner), "no restart")
        XCTAssertFalse(split.showsList(.partner))
        XCTAssertEqual(split.captions, .both(owner: en, partner: es))
    }

    func testPickingAnotherLanguageRestartsInTheNewPair() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.pick(es, for: .partner)
        split.openList(.partner)
        XCTAssertTrue(split.pick(fr, for: .partner))
        XCTAssertEqual(split.captions, .both(owner: en, partner: fr))
        XCTAssertEqual(choices(split, .owner), ["en-US", "es-ES"], "now French is the one left out")
    }

    func testRepickingWhileOnlyOneHalfHasPicked() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.openList(.owner)
        XCTAssertEqual(choices(split, .owner), ["en-US", "es-ES", "fr-FR"])
        XCTAssertTrue(split.pick(fr, for: .owner))
        XCTAssertEqual(split.captions, .one(.owner, fr))
    }

    func testAHalfWithNoLanguageHasNoNameToTap() {
        var split = FaceToFaceSplit()
        split.openList(.partner)
        XCTAssertNil(split.language(of: .partner))
        XCTAssertTrue(split.showsList(.partner))
        XCTAssertNil(split.captions)
    }

    // MARK: pause and resume

    func testCaptionsThatStopOnTheirOwnLeaveTheSplitPausedWithStart() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.pick(es, for: .partner)
        split.sessionStarted()
        var s = CaptionStream()
        say(&s, "Where is the station please", speaker: 0, lane: .owner, at: 0)
        var languages = SpeakerLanguages()
        matched(0, to: .owner, in: &languages)
        split.sessionEnded(s.lines, languages: languages)
        split.stoppedOnTheirOwn()
        XCTAssertTrue(split.isPaused)
        XCTAssertEqual(split.control, .start)
        XCTAssertFalse(split.showsList(.owner), "the lines stay")
        XCTAssertFalse(split.showsList(.partner))
        XCTAssertEqual(split.half(of: s.lines[0], languages: SpeakerLanguages()), .owner)
    }

    func testStartCarriesOnWithBothHalvesLanguages() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.pick(es, for: .partner)
        split.stoppedOnTheirOwn()
        XCTAssertTrue(split.resume())
        XCTAssertFalse(split.isPaused)
        XCTAssertEqual(split.control, .stop)
        XCTAssertEqual(split.captions, .both(owner: en, partner: es))
    }

    func testAPausedSplitWithOneHalfPickedResumesInThatLanguage() {
        var split = FaceToFaceSplit()
        split.pick(es, for: .partner)
        split.stoppedOnTheirOwn()
        XCTAssertTrue(split.resume())
        XCTAssertEqual(split.captions, .one(.partner, es))
    }

    func testAPickWhilePausedStartsCaptionsToo() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.stoppedOnTheirOwn()
        XCTAssertTrue(split.pick(es, for: .partner))
        XCTAssertFalse(split.isPaused)
        XCTAssertEqual(split.control, .stop)
        // And picking the same language again while paused starts them as well: the tap always starts its half.
        split.stoppedOnTheirOwn()
        split.openList(.partner)
        XCTAssertTrue(split.pick(es, for: .partner))
        XCTAssertFalse(split.isPaused)
    }

    func testNothingToPauseBeforeAnyonePicks() {
        var split = FaceToFaceSplit()
        split.stoppedOnTheirOwn()
        XCTAssertFalse(split.isPaused)
        XCTAssertEqual(split.control, .stop)
        XCTAssertFalse(split.resume())
    }

    func testResumeOnlyFromPaused() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        XCTAssertFalse(split.resume(), "already captioning")
    }

    func testEndingASessionTwiceIsHarmless() {
        var split = FaceToFaceSplit()
        split.pick(en, for: .owner)
        split.sessionStarted()
        var s = CaptionStream()
        say(&s, "Hello", speaker: 0, at: 0)
        split.sessionEnded(s.lines, languages: SpeakerLanguages())
        split.pick(es, for: .partner)
        // A second end (the state change after an explicit one) mustn't re-settle under the new pair.
        XCTAssertTrue(split.sessionEnded(s.lines, languages: SpeakerLanguages()).isEmpty)
        XCTAssertEqual(split.half(of: s.lines[0], languages: SpeakerLanguages()), .owner)
    }
}

/// #208: what each half's list offers on a real device, until Seal keeps its own list of languages (#200): Apple can't
/// say which translation languages are downloaded, only whether a pair is.
final class FaceToFaceOfferedLanguagesTests: XCTestCase {
    private func ids(_ ls: [Locale]) -> [String] { ls.map(\.identifier) }

    func testTheCaptionAndIntoLanguagesAreAlwaysOffered() {
        let offered = FaceToFace.offered(captionLanguage: Locale(identifier: "es-ES"), into: Locale(identifier: "en-US"),
                                         speechInstalled: [], translatable: [])
        XCTAssertEqual(ids(offered), ["es-ES", "en-US"])
    }

    func testInstalledSpeechLanguagesAppleCanTranslateAreOffered() {
        let installed = ["fr-FR", "de-DE", "yue-CN"].map(Locale.init(identifier:))
        let offered = FaceToFace.offered(captionLanguage: Locale(identifier: "en-US"), into: Locale(identifier: "es-ES"),
                                         speechInstalled: installed, translatable: ["en", "es", "fr", "de"])
        XCTAssertEqual(ids(offered), ["en-US", "es-ES", "fr-FR", "de-DE"], "Cantonese can't be translated, so it isn't offered")
    }

    func testNoIntoLanguageStillOffersTheCaptionLanguage() {
        let offered = FaceToFace.offered(captionLanguage: Locale(identifier: "en-US"), into: nil,
                                         speechInstalled: [Locale(identifier: "en-GB")], translatable: ["en"])
        XCTAssertEqual(ids(offered), ["en-US", "en-GB"], "one language twice is folded into one row by the list itself")
        XCTAssertEqual(FaceToFace.choices(downloaded: offered, takenByOtherHalf: nil, name: { $0.identifier }).count, 1)
    }
}

/// #208: her half's one control in the split, as the screen draws it.
final class FaceToFaceSplitControlTests: XCTestCase {
    func testStopIsTheSmallCircleThatLeaves() {
        let c = PrimaryControl.inSplit(.stop)
        XCTAssertEqual(c.action, .stop)
        XCTAssertEqual(c.presentation, .compact)
        XCTAssertTrue(c.isEnabled, "even while the engines get ready: Stop always leaves")
    }

    func testThePausedSplitShowsStartCaptions() {
        let c = PrimaryControl.inSplit(.start)
        XCTAssertEqual(c.action, .start)
        XCTAssertEqual(c.title, PrimaryControl.for(.idle).title)
        XCTAssertEqual(c.presentation, .large)
    }
}

@testable import CaptionCore
import XCTest

/// #60 wiring, the owner's "voice first" (2026-10-29): the diarizer tells the people apart, each voice is matched to
/// one of the two languages from the words its first lines are in, and from then on only that language's engine hears
/// it. Lock early when sure; stay correctable when later lines say the language was wrong. These try to break it.
final class FaceToFaceWiringTests: XCTestCase {
    // The two halves' languages in these tests: the partner speaks Spanish (From), the owner reads English (Into).
    private static let spanish: [FaceToFaceHalf: Double] = [.partner: 0.99, .owner: 0.01]
    private static let english: [FaceToFaceHalf: Double] = [.owner: 0.99, .partner: 0.01]
    private static let unsure: [FaceToFaceHalf: Double] = [.owner: 0.6, .partner: 0.4]

    /// Words at 0.4 s apart from `start`, as an engine reports them.
    private func words(_ text: String, at start: Double) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { i, w in
            TimedWord(text: String(w), start: start + Double(i) * 0.4, end: start + Double(i) * 0.4 + 0.3)
        }
    }

    /// A classifier that answers by a marker word, so tests say what language a line "is" without NaturalLanguage.
    private func classify(_ text: String) -> [FaceToFaceHalf: Double] {
        if text.contains("es:") { return Self.spanish }
        if text.contains("en:") { return Self.english }
        return Self.unsure
    }

    @discardableResult
    private func hear(_ l: inout SpeakerLanguages, _ speaker: Int, _ lane: FaceToFaceHalf, _ text: String,
                      at start: Double, final: Bool = true) -> SpeakerLanguages.Change? {
        l.heard(speaker: speaker, lane: lane, words: words(text, at: start), isFinal: final, classify: classify)
    }

    // MARK: nobody matched yet

    func testBeforeAnyoneSpeaksBothEnginesListenAndNobodyHasAHalf() {
        let l = SpeakerLanguages()
        XCTAssertEqual(l.lanes(for: nil), [.owner, .partner])
        XCTAssertEqual(l.lanes(for: 0), [.owner, .partner])
        XCTAssertNil(l.state(of: 0))
        XCTAssertNil(l.sides.half(ofSpeaker: 0))
    }

    func testOneSureWordIsNotEnoughToLock() {
        var l = SpeakerLanguages()
        XCTAssertNil(hear(&l, 0, .partner, "es:Hola", at: 0))
        XCTAssertEqual(l.state(of: 0), .matching)
        XCTAssertEqual(l.lanes(for: 0), [.owner, .partner], "still both engines")
    }

    func testFourSureWordsLockRightAwayOnTheFirstLine() {
        var l = SpeakerLanguages()
        let change = hear(&l, 0, .partner, "es:Buenos días, ¿cómo está?", at: 0, final: false)
        XCTAssertEqual(change, .locked(speaker: 0, .partner), "a volatile line is enough: lock early")
        XCTAssertEqual(l.lanes(for: 0), [.partner], "from now on only the Spanish engine hears them")
        XCTAssertEqual(l.sides.half(ofSpeaker: 0), .partner)
    }

    func testTheSameWordsFromBothEnginesCountOnceNotTwice() {
        var l = SpeakerLanguages()
        // Both engines heard the same two words: that's two words, not four.
        hear(&l, 0, .partner, "es:Hola amigo", at: 0)
        hear(&l, 0, .owner, "es:Ola amigo", at: 0)
        XCTAssertEqual(l.state(of: 0), .matching)
    }

    func testAVolatileWordRevisedInPlaceIsNotCountedAgain() {
        var l = SpeakerLanguages()
        hear(&l, 0, .partner, "es:Hola", at: 0, final: false)
        hear(&l, 0, .partner, "es:Hola", at: 0, final: false)
        hear(&l, 0, .partner, "es:Hola", at: 0, final: true)
        hear(&l, 0, .partner, "es:Hola", at: 0.01, final: true)  // a frame of drift is the same word
        XCTAssertEqual(l.state(of: 0), .matching)
    }

    func testUnsureWordsNeverLockEarlyButEventuallyGoToTheLikelierLanguage() {
        var l = SpeakerLanguages()
        let policy = l.policy
        var t = 0.0
        while (l.state(of: 0) == .matching || l.state(of: 0) == nil) && t < 200 {
            hear(&l, 0, .partner, "uno dos tres cuatro cinco", at: t)
            t += 2
        }
        // 5 words per line: it gives up waiting at the first line that reaches `giveUpWords`.
        let lines = (policy.giveUpWords + 4) / 5
        XCTAssertEqual(t, Double(lines) * 2, "doesn't run both engines for ever")
        XCTAssertEqual(l.state(of: 0), .locked(.owner), "0.6 vs 0.4: the likelier language")
    }

    func testWhatShowsBeforeAMatchIsTheEngineTheWordsLeanTowardOrTheCaptionLanguage() {
        var l = SpeakerLanguages()
        XCTAssertEqual(l.shownLane(for: 0, at: 0), .partner, "no words yet: the caption language's engine, as one-way shows")
        XCTAssertEqual(l.shownLane(for: nil, at: 0), .partner)
        hear(&l, 0, .owner, "en:Hi", at: 0)
        XCTAssertEqual(l.state(of: 0), .matching)
        XCTAssertEqual(l.shownLane(for: 0, at: 0), .owner, "leaning English: show the English engine's words")
    }

    func testTheLockCoversTheLinesSpokenWhileMatching() {
        var l = SpeakerLanguages()
        hear(&l, 0, .owner, "en:Hi", at: 0)
        hear(&l, 0, .owner, "en:I would like a ticket", at: 2)
        XCTAssertEqual(l.state(of: 0), .locked(.owner))
        XCTAssertEqual(l.shownLane(for: 0, at: 0), .owner, "the first line too")
        XCTAssertEqual(l.shownLane(for: 0, at: -100), .owner)
    }

    // MARK: staying correctable

    private func lockedSpanish() -> SpeakerLanguages {
        var l = SpeakerLanguages()
        hear(&l, 0, .partner, "es:Buenos días, ¿cómo está?", at: 0)
        XCTAssertEqual(l.state(of: 0), .locked(.partner))
        return l
    }

    func testOneGarbledLineDoesNotMoveASpeaker() {
        var l = lockedSpanish()
        XCTAssertNil(hear(&l, 0, .partner, "en:that must be wrong somehow", at: 5))
        XCTAssertEqual(l.state(of: 0), .locked(.partner))
        XCTAssertEqual(l.lanes(for: 0), [.partner])
    }

    func testTwoLinesInARowInTheOtherLanguageMoveTheSpeakerAndTheirEngine() {
        var l = lockedSpanish()
        hear(&l, 0, .partner, "en:I am actually speaking English", at: 5)
        let change = hear(&l, 0, .partner, "en:yes really English here", at: 10)
        XCTAssertEqual(change, .rematched(speaker: 0, from: .partner, to: .owner))
        XCTAssertEqual(l.lanes(for: 0), [.owner])
        XCTAssertEqual(l.sides.half(ofSpeaker: 0), .owner, "their lines move to the other half")
        // The lines already shown came only from the Spanish engine: they stay (the best there is), just moved.
        XCTAssertEqual(l.shownLane(for: 0, at: 0), .partner)
        XCTAssertEqual(l.shownLane(for: 0, at: 10), .partner, "the deciding line itself was the Spanish engine's")
        XCTAssertEqual(l.shownLane(for: 0, at: 20), .owner)
    }

    func testAConfirmingLineBetweenTwoOddOnesResetsTheCount() {
        var l = lockedSpanish()
        hear(&l, 0, .partner, "en:I am actually speaking English", at: 5)
        hear(&l, 0, .partner, "es:no, hablo español de verdad", at: 10)
        XCTAssertNil(hear(&l, 0, .partner, "en:I am actually speaking English", at: 15))
        XCTAssertEqual(l.state(of: 0), .locked(.partner))
    }

    func testShortLinesNeitherConfirmNorDoubt() {
        var l = lockedSpanish()
        hear(&l, 0, .partner, "en:I am actually speaking English", at: 5)
        hear(&l, 0, .partner, "sí", at: 8)
        hear(&l, 0, .partner, "ok", at: 9)
        XCTAssertEqual(l.state(of: 0), .locked(.partner))
        let change = hear(&l, 0, .partner, "en:yes really English here", at: 10)
        XCTAssertEqual(change, .rematched(speaker: 0, from: .partner, to: .owner), "the short ones didn't break the run")
    }

    func testTheOtherEnginesWordsAtATurnEdgeAreNotEvidence() {
        var l = lockedSpanish()
        // The English engine was still listening for a moment when this Spanish speaker started: ignored.
        hear(&l, 0, .owner, "en:garbled english from the wrong engine", at: 5)
        hear(&l, 0, .owner, "en:garbled english from the wrong engine", at: 8)
        XCTAssertEqual(l.state(of: 0), .locked(.partner))
    }

    func testVolatileLinesNeverMoveALockedSpeaker() {
        var l = lockedSpanish()
        hear(&l, 0, .partner, "en:I am actually speaking English", at: 5, final: false)
        hear(&l, 0, .partner, "en:I am actually speaking English now", at: 5, final: false)
        XCTAssertEqual(l.state(of: 0), .locked(.partner), "only finished lines count once locked")
    }

    func testTwoUnclearLinesBringTheOtherEngineBackToCheck() {
        var l = lockedSpanish()
        hear(&l, 0, .partner, "mumble mumble mumble mumble", at: 5)
        let change = hear(&l, 0, .partner, "mumble mumble mumble mumble", at: 10)
        XCTAssertEqual(change, .checking(speaker: 0))
        XCTAssertEqual(l.state(of: 0), .checking(.partner))
        XCTAssertEqual(l.lanes(for: 0), [.owner, .partner], "both engines again while checking")
        XCTAssertEqual(l.sides.half(ofSpeaker: 0), .partner, "they keep their half while being checked")
    }

    func testACheckThatAgreesKeepsTheSpeakerWhereTheyWere() {
        var l = lockedSpanish()
        hear(&l, 0, .partner, "mumble mumble mumble mumble", at: 5)
        hear(&l, 0, .partner, "mumble mumble mumble mumble", at: 10)
        let change = hear(&l, 0, .owner, "es:pues sí hablo español", at: 15)
        XCTAssertEqual(change, .kept(speaker: 0, .partner))
        XCTAssertEqual(l.state(of: 0), .locked(.partner))
        XCTAssertEqual(l.lanes(for: 0), [.partner])
    }

    func testACheckThatDisagreesMovesThemAndShowsTheRightEngineFromTheCheckOn() {
        var l = lockedSpanish()
        hear(&l, 0, .partner, "mumble mumble mumble mumble", at: 5)
        hear(&l, 0, .partner, "mumble mumble mumble mumble", at: 10)
        let checkStart = 10 + 3 * 0.4 + 0.3
        let change = hear(&l, 0, .owner, "en:it is English after all", at: 15)
        XCTAssertEqual(change, .rematched(speaker: 0, from: .partner, to: .owner))
        XCTAssertEqual(l.lanes(for: 0), [.owner])
        XCTAssertEqual(l.shownLane(for: 0, at: checkStart - 0.1), .partner, "before the check: the only engine that ran")
        XCTAssertEqual(l.shownLane(for: 0, at: checkStart + 0.1), .owner, "both ran during the check: the right one")
    }

    func testWordsFromBeforeTheCheckDontDecideIt() {
        var l = lockedSpanish()
        hear(&l, 0, .partner, "mumble mumble mumble mumble", at: 5)
        hear(&l, 0, .partner, "mumble mumble mumble mumble", at: 10)
        // A late final for audio before the check started: not evidence for the check.
        XCTAssertNil(hear(&l, 0, .owner, "en:it is English after all", at: 1))
        XCTAssertEqual(l.state(of: 0), .checking(.partner))
    }

    func testACheckThatNeverGetsSureGoesBackToTheLock() {
        var l = lockedSpanish()
        hear(&l, 0, .partner, "mumble mumble mumble mumble", at: 5)
        hear(&l, 0, .partner, "mumble mumble mumble mumble", at: 10)
        var t = 20.0
        var change: SpeakerLanguages.Change?
        while l.state(of: 0) == .checking(.partner) && t < 500 {
            change = hear(&l, 0, .partner, "mumble mumble mumble mumble mumble", at: t)
            t += 3
        }
        XCTAssertEqual(change, .kept(speaker: 0, .partner))
        XCTAssertLessThan(t, 500)
    }

    // MARK: more than two voices

    func testANewVoiceIsMatchedOnItsOwnAndTheOthersKeepTheirEngines() {
        var l = lockedSpanish()
        hear(&l, 1, .owner, "en:Good morning, a ticket please", at: 5)
        XCTAssertEqual(l.state(of: 1), .locked(.owner))
        // A third person walks up.
        XCTAssertEqual(l.lanes(for: 2), [.owner, .partner])
        hear(&l, 2, .partner, "es:yo también quiero uno", at: 10)
        XCTAssertEqual(l.state(of: 2), .locked(.partner), "they join the half of the language they speak")
        XCTAssertEqual(l.lanes(for: 0), [.partner])
        XCTAssertEqual(l.lanes(for: 1), [.owner])
    }

    func testOneSpeakersWordsNeverDecideAnother() {
        var l = SpeakerLanguages()
        hear(&l, 0, .partner, "es:Hola", at: 0)
        hear(&l, 1, .partner, "es:Hola amigo mío", at: 1)
        XCTAssertEqual(l.state(of: 0), .matching)
        XCTAssertEqual(l.state(of: 1), .matching, "3 words of their own")
    }

    // MARK: routing the audio by voice

    func testUntilTheDiarizerHasAnythingBothEnginesListen() {
        var r = VoiceRouter()
        let refeed = r.route(now: 1, segments: [], number: { $0 }, languages: SpeakerLanguages())
        XCTAssertEqual(r.active, [.owner, .partner])
        XCTAssertEqual(refeed, [:])
    }

    func testALockedSpeakerTalkingFeedsOnlyTheirEngine() {
        var r = VoiceRouter()
        let l = lockedSpanish()
        r.route(now: 3, segments: [SpeakerSegment(speaker: 0, start: 0, end: 2.5)], number: { $0 }, languages: l)
        XCTAssertEqual(r.active, [.partner])
    }

    func testATurnChangeWakesTheOtherEngineFromJustBeforeTheTurnStarted() {
        var r = VoiceRouter()
        var l = lockedSpanish()
        hear(&l, 1, .owner, "en:Good morning, a ticket please", at: 5)
        r.route(now: 3, segments: [SpeakerSegment(speaker: 0, start: 0, end: 2.5)], number: { $0 }, languages: l)
        let refeed = r.route(now: 4, segments: [SpeakerSegment(speaker: 0, start: 0, end: 2.5),
                                                SpeakerSegment(speaker: 1, start: 3.0, end: 3.6)],
                             number: { $0 }, languages: l)
        XCTAssertEqual(r.active, [.owner])
        XCTAssertEqual(refeed[.owner]!, 3.0 - r.leadSeconds, accuracy: 1e-9)
        XCTAssertNil(refeed[.partner], "the engine that goes quiet needs nothing re-fed")
    }

    func testAnUnmatchedVoiceWakesBothEnginesFromTheirTurnStart() {
        var r = VoiceRouter()
        let l = lockedSpanish()
        r.route(now: 3, segments: [SpeakerSegment(speaker: 0, start: 0, end: 2.5)], number: { $0 }, languages: l)
        let refeed = r.route(now: 5, segments: [SpeakerSegment(speaker: 0, start: 0, end: 2.5),
                                                SpeakerSegment(speaker: 1, start: 4.0, end: 4.6)],
                             number: { $0 }, languages: l)
        XCTAssertEqual(r.active, [.owner, .partner])
        XCTAssertEqual(Set(refeed.keys), [.owner], "the Spanish engine was already listening")
    }

    func testSilenceKeepsTheEngineThatWasListening() {
        var r = VoiceRouter()
        let l = lockedSpanish()
        r.route(now: 3, segments: [SpeakerSegment(speaker: 0, start: 0, end: 2.5)], number: { $0 }, languages: l)
        r.route(now: 30, segments: [SpeakerSegment(speaker: 0, start: 0, end: 2.5)], number: { $0 }, languages: l)
        XCTAssertEqual(r.active, [.partner])
    }

    func testAScrapOfAnotherVoiceDoesNotSwitchEngines() {
        var r = VoiceRouter()
        var l = lockedSpanish()
        hear(&l, 1, .owner, "en:Good morning, a ticket please", at: 5)
        r.route(now: 3, segments: [SpeakerSegment(speaker: 0, start: 0, end: 2.5)], number: { $0 }, languages: l)
        r.route(now: 3.2, segments: [SpeakerSegment(speaker: 0, start: 0, end: 2.5), SpeakerSegment(speaker: 1, start: 2.6, end: 2.7)],
                number: { $0 }, languages: l)
        XCTAssertEqual(r.active, [.partner], "0.1 s of the other slot is a flicker, not a turn")
    }

    func testASlotWithNoNumberYetCountsAsAnUnmatchedVoice() {
        var r = VoiceRouter()
        let l = lockedSpanish()
        r.route(now: 3, segments: [SpeakerSegment(speaker: 0, start: 0, end: 2.5)], number: { $0 }, languages: l)
        r.route(now: 5, segments: [SpeakerSegment(speaker: 3, start: 3.5, end: 4.6)], number: { $0 == 3 ? nil : $0 }, languages: l)
        XCTAssertEqual(r.active, [.owner, .partner])
    }

    // MARK: feeding an engine that only hears part of the conversation

    func testAnEngineThatMissedAStretchIsToldToSkipAheadThenFed() {
        var f = LaneClock()
        XCTAssertEqual(f.plan(start: 0, count: 1600), .init(skipTo: nil, dropFirst: 0))
        XCTAssertEqual(f.fedUntil, 0.1, accuracy: 1e-9)
        let p = f.plan(start: 5, count: 1600)
        XCTAssertEqual(p.skipTo!, 5, accuracy: 1e-9)
        XCTAssertEqual(p.dropFirst, 0)
        XCTAssertEqual(f.fedUntil, 5.1, accuracy: 1e-9)
    }

    func testAudioAnEngineAlreadyHadIsNotFedTwice() {
        var f = LaneClock()
        _ = f.plan(start: 0, count: 16000)            // 0...1 s
        let p = f.plan(start: 0.5, count: 16000)      // re-fed from 0.5: the first half is old
        XCTAssertNil(p.skipTo)
        XCTAssertEqual(p.dropFirst, 8000)
        XCTAssertEqual(f.fedUntil, 1.5, accuracy: 1e-9)
        let all = f.plan(start: 0.2, count: 1600)     // entirely old
        XCTAssertEqual(all.dropFirst, 1600)
        XCTAssertEqual(f.fedUntil, 1.5, accuracy: 1e-9)
    }

    func testTheShortBufferGivesBackTheTurnSoFar() {
        var ring = AudioRing(seconds: 2)
        ring.append([Float](repeating: 1, count: 16000), at: 0)       // 0...1
        ring.append([Float](repeating: 2, count: 16000), at: 1)       // 1...2
        ring.append([Float](repeating: 3, count: 16000), at: 2)       // 2...3; 0...1 falls off
        let (from, samples) = ring.samples(from: 0.5, to: 3)
        XCTAssertEqual(from, 1, accuracy: 1e-9, "only what's still kept")
        XCTAssertEqual(samples.count, 32000)
        XCTAssertEqual(samples.first, 2)
        let (mid, part) = ring.samples(from: 2.5, to: 2.75)
        XCTAssertEqual(mid, 2.5, accuracy: 1e-9)
        XCTAssertEqual(part.count, 4000)
        XCTAssertTrue(ring.samples(from: 4, to: 5).samples.isEmpty)
    }

    func testParakeetsWindowStaysOnTheSessionClockAcrossASkip() {
        var w = SampleWindow(maxSeconds: 20)
        w.append([Float](repeating: 0.5, count: 16000), level: -20)
        w.skip(to: 3)
        XCTAssertEqual(w.endTime, 3, accuracy: 1e-9)
        w.append([Float](repeating: 0.5, count: 16000), level: -20)
        XCTAssertEqual(w.endTime, 4, accuracy: 1e-9)
        w.skip(to: 60)   // longer than the window: starts afresh at the new time
        XCTAssertEqual(w.endTime, 60, accuracy: 1e-9)
        XCTAssertEqual(w.startTime, 60, accuracy: 1e-9)
        w.skip(to: 59)   // never backwards
        XCTAssertEqual(w.endTime, 60, accuracy: 1e-9)
    }

    // MARK: captions from two engines at once

    func testTwoEnginesTailsDontOverwriteEachOther() {
        var s = CaptionStream()
        s.apply(text: "Buenos", isFinal: false, speaker: 0, range: 0...0.5, lane: .partner)
        s.apply(text: "Bonus", isFinal: false, speaker: 0, range: 0...0.5, lane: .owner)
        s.apply(text: "Buenos días", isFinal: false, speaker: 0, range: 0...1, lane: .partner)
        XCTAssertEqual(s.lines.count, 2)
        XCTAssertEqual(s.lines.map(\.text), ["Buenos días", "Bonus"])
        XCTAssertEqual(s.lines.map(\.lane), [.partner, .owner])
        s.apply(text: "Buenos días.", isFinal: true, speaker: 0, range: 0...1, lane: .partner)
        XCTAssertTrue(s.lines[0].isFinal)
        XCTAssertFalse(s.lines[1].isFinal, "the other engine's tail is untouched")
    }

    func testAnEngineContinuesItsOwnLineEvenAfterTheOtherAddedOne() {
        var s = CaptionStream()
        s.apply(text: "Good", isFinal: false, speaker: 1, range: 3...3.5, lane: .owner)
        s.apply(text: "Gud", isFinal: false, speaker: 1, range: 3...3.5, lane: .partner)
        s.apply(text: "Good morning", isFinal: true, speaker: 1, range: 3...4, lane: .owner)
        s.apply(text: "to you", isFinal: true, speaker: 1, range: 4.2...4.8, lane: .owner)
        XCTAssertEqual(s.lines.filter { $0.lane == .owner }.map(\.text), ["Good morning to you"])
    }

    func testOneWayCaptionsHaveNoLane() {
        var s = CaptionStream()
        s.apply(text: "Hello", isFinal: true, speaker: 0, range: 0...1)
        XCTAssertNil(s.lines[0].lane)
    }

    func testLeavingTheSplitKeepsOnlyTheLinesThatWereShown() {
        var s = CaptionStream()
        s.apply(text: "Before the split.", isFinal: true, speaker: 0, range: 0...1)
        s.apply(text: "Buenos días señor", isFinal: true, speaker: 0, range: 2...3, lane: .partner)
        s.apply(text: "When are you see nor", isFinal: true, speaker: 0, range: 2...3, lane: .owner)
        let ids = s.lines.map(\.id)
        s.removeLines { $0.lane == .owner }
        XCTAssertEqual(s.lines.map(\.text), ["Before the split.", "Buenos días señor"])
        XCTAssertEqual(s.lines.map(\.id), [ids[0], ids[1]], "ids stay, so translations stay attached")
        s.apply(text: "next", isFinal: true, speaker: 0, range: 9...10)
        XCTAssertFalse(Set(ids).contains(s.lines.last!.id), "a removed id is never reused")
    }

    // MARK: what each half shows

    private func conversation() -> (lines: [CaptionLine], languages: SpeakerLanguages) {
        var l = SpeakerLanguages()
        var s = CaptionStream()
        // The partner's first line: both engines heard it while matching.
        s.apply(text: "Buenos días, ¿cómo está?", isFinal: true, speaker: 0, range: 0...2, lane: .partner)
        s.apply(text: "When is DS como está", isFinal: true, speaker: 0, range: 0...2, lane: .owner)
        hear(&l, 0, .partner, "es:Buenos días, ¿cómo está?", at: 0)
        // The owner's first line.
        s.apply(text: "Good morning, a ticket please.", isFinal: true, speaker: 1, range: 3...5, lane: .owner)
        s.apply(text: "Gud mornin, a tiket plis.", isFinal: true, speaker: 1, range: 3...5, lane: .partner)
        hear(&l, 1, .owner, "en:Good morning, a ticket please.", at: 3)
        return (s.lines, l)
    }

    func testAfterTheMatchOnlyEachVoicesOwnEngineShows() {
        let (lines, l) = conversation()
        let shown = FaceToFace.shown(lines, languages: l).map(\.text)
        XCTAssertEqual(shown, ["Buenos días, ¿cómo está?", "Good morning, a ticket please."])
    }

    func testEachHalfShowsItsOwnSpeakerAsSaidAndTheOtherTranslated() {
        let (lines, l) = conversation()
        let shown = FaceToFace.shown(lines, languages: l)
        let into: (CaptionLine, FaceToFaceHalf) -> String? = { line, half in
            half == .owner ? "[en] " + line.text : "[es] " + line.text
        }
        let owner = FaceToFace.entries(for: .owner, lines: shown, half: { l.half(of: $0) }, translation: into)
        XCTAssertEqual(owner.map(\.text), ["[en] Buenos días, ¿cómo está?", "Good morning, a ticket please."])
        XCTAssertEqual(owner.map(\.from), [.partner, .owner])
        let partner = FaceToFace.entries(for: .partner, lines: shown, half: { l.half(of: $0) }, translation: into)
        XCTAssertEqual(partner.map(\.text), ["Buenos días, ¿cómo está?", "[es] Good morning, a ticket please."])
    }

    func testBeforeAMatchOneEnginesWordsShowAsSaidOnBothHalves() {
        var s = CaptionStream()
        s.apply(text: "Hola", isFinal: false, speaker: 0, range: 0...0.5, lane: .partner)
        s.apply(text: "Ola", isFinal: false, speaker: 0, range: 0...0.5, lane: .owner)
        let l = SpeakerLanguages()
        let shown = FaceToFace.shown(s.lines, languages: l)
        XCTAssertEqual(shown.map(\.text), ["Hola"], "one engine's words, not both")
        for half in [FaceToFaceHalf.owner, .partner] {
            let e = FaceToFace.entries(for: half, lines: shown, half: { l.half(of: $0) }, translation: { _, _ in "never" })
            XCTAssertEqual(e.map(\.text), ["Hola"])
            XCTAssertNil(e[0].from)
        }
    }

    func testLinesFromBeforeTheSplitShowAsSaidOnBothHalves() {
        var s = CaptionStream()
        s.apply(text: "Said before the split.", isFinal: true, speaker: 0, range: 0...1)
        var l = SpeakerLanguages()
        hear(&l, 0, .partner, "es:Buenos días, ¿cómo está?", at: 5)
        XCTAssertNil(l.half(of: s.lines[0]), "speaker numbers restart each session: an old line has no half")
        XCTAssertEqual(FaceToFace.shown(s.lines, languages: l).count, 1)
    }

    func testAMovedSpeakersEarlierLinesMoveHalvesToo() {
        var l = lockedSpanish()
        var s = CaptionStream()
        s.apply(text: "Buenos días, ¿cómo está?", isFinal: true, speaker: 0, range: 0...2, lane: .partner)
        s.apply(text: "Ai em spiking inglish", isFinal: true, speaker: 0, range: 5...7, lane: .partner)
        hear(&l, 0, .partner, "en:I am actually speaking English", at: 5)
        hear(&l, 0, .partner, "en:yes really English here", at: 10)
        s.apply(text: "Yes, really English here.", isFinal: true, speaker: 0, range: 20...22, lane: .owner)
        let shown = FaceToFace.shown(s.lines, languages: l)
        XCTAssertEqual(shown.count, 3, "nothing lost")
        XCTAssertEqual(Set(shown.map { l.half(of: $0) }), [.owner])
    }

    // MARK: which lines go to which translator

    func testThePartnersLinesGoIntoTheOwnersLanguageAndTheOwnersIntoThePartners() {
        let (lines, l) = conversation()
        let shown = FaceToFace.shown(lines, languages: l)
        XCTAssertEqual(FaceToFace.lines(saidOn: .partner, in: shown, half: { l.half(of: $0) }).map(\.text),
                       ["Buenos días, ¿cómo está?"])
        XCTAssertEqual(FaceToFace.lines(saidOn: .owner, in: shown, half: { l.half(of: $0) }).map(\.text),
                       ["Good morning, a ticket please."])
    }

    // MARK: the language of the words (NaturalLanguage, on the device)

    func testRealSentencesAreRecognisedInTheirLanguage() {
        let pair = LanguagePair(owner: Locale(identifier: "en-US"), partner: Locale(identifier: "es-MX"))
        XCTAssertGreaterThanOrEqual(pair.probabilities("Quisiera comprar un billete a Madrid, por favor.")[.partner] ?? 0, 0.95)
        XCTAssertGreaterThanOrEqual(pair.probabilities("I would like to buy a ticket to Madrid, please.")[.owner] ?? 0, 0.95)
    }

    func testTheSameLanguageOnBothSidesNeverDecides() {
        let pair = LanguagePair(owner: Locale(identifier: "en-US"), partner: Locale(identifier: "en-GB"))
        let p = pair.probabilities("I would like to buy a ticket to Madrid, please.")
        XCTAssertEqual(p[.owner], p[.partner])
    }

    func testNoWordsMeansNoEvidence() {
        let pair = LanguagePair(owner: Locale(identifier: "en-US"), partner: Locale(identifier: "es-MX"))
        XCTAssertEqual(pair.probabilities("   ")[.owner] ?? 0, 0.5, accuracy: 1e-9)
    }

    // MARK: speaker numbers shared by both engines

    func testBothEnginesGiveTheSameVoiceTheSameNumber() {
        var numbering: [Int: Int] = [:]
        var a = SpeakerLabelSmoother(), b = SpeakerLabelSmoother()
        let segs = [SpeakerSegment(speaker: 2, start: 0, end: 3), SpeakerSegment(speaker: 0, start: 3, end: 6)]
        XCTAssertEqual(b.label(start: 3.5, end: 5, segments: segs, isFinal: true, numbering: &numbering), 0)
        XCTAssertEqual(a.label(start: 0.5, end: 2, segments: segs, isFinal: true, numbering: &numbering), 1)
        XCTAssertEqual(a.label(start: 3.5, end: 5, segments: segs, isFinal: true, numbering: &numbering), 0)
        XCTAssertEqual(numbering, [0: 0, 2: 1])
    }
}

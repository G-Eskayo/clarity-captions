@testable import CaptionCore
import XCTest

/// #208 item 3, the owner's note on #199: people practise the other language or throw in words they're learning
/// ("Spanglish"). Confidence in a voice's language builds over the conversation, so a few minutes in mixed lines and
/// practice lines don't move anyone, while a wrong lock early on is still fixed fast. These try to break it.
final class FaceToFaceCodeSwitchingTests: XCTestCase {
    private static let spanish: [FaceToFaceHalf: Double] = [.partner: 0.99, .owner: 0.01]
    private static let english: [FaceToFaceHalf: Double] = [.owner: 0.99, .partner: 0.01]
    private static let mixed: [FaceToFaceHalf: Double] = [.owner: 0.55, .partner: 0.45]

    private func words(_ text: String, at start: Double) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { i, w in
            TimedWord(text: String(w), start: start + Double(i) * 0.4, end: start + Double(i) * 0.4 + 0.3)
        }
    }

    private func classify(_ text: String) -> [FaceToFaceHalf: Double] {
        if text.contains("es:") { return Self.spanish }
        if text.contains("en:") { return Self.english }
        return Self.mixed
    }

    /// Lines 5 s apart, like a slow conversation; `t` moves on with each.
    private var t = 0.0

    @discardableResult
    private func say(_ l: inout SpeakerLanguages, _ text: String, speaker: Int = 0, lane: FaceToFaceHalf = .partner,
                     final: Bool = true) -> SpeakerLanguages.Change? {
        defer { t += 5 }
        return l.heard(speaker: speaker, lane: lane, words: words(text, at: t), isFinal: final, classify: classify)
    }

    /// A Spanish speaker, locked, then `lines` more sure Spanish lines.
    private func spanishSpeaker(after lines: Int, policy: LanguageMatchPolicy = LanguageMatchPolicy()) -> SpeakerLanguages {
        var l = SpeakerLanguages(policy: policy)
        say(&l, "es:Buenos días, ¿cómo está usted?")
        XCTAssertEqual(l.state(of: 0), .locked(.partner))
        for _ in 0..<lines { say(&l, "es:sí, claro, el tren sale a las cuatro") }
        return l
    }

    private func englishLinesToMove(_ l: inout SpeakerLanguages) -> Int {
        var n = 0
        while l.state(of: 0) != .locked(.owner) && n < 1000 {
            // In a check both engines hear them; the English engine's copy is the one that's sure.
            let lane: FaceToFaceHalf = l.lanes(for: 0).contains(.partner) ? .partner : .owner
            if case .checking = l.state(of: 0) { say(&l, "en:I really am speaking English now", lane: .owner) }
            else { say(&l, "en:I really am speaking English now", lane: lane) }
            n += 1
        }
        return n
    }

    // MARK: early on, still correctable

    func testRightAfterTheLockTwoLinesInTheOtherLanguageStillMoveThem() {
        var l = spanishSpeaker(after: 0)
        say(&l, "en:I am actually speaking English")
        XCTAssertEqual(say(&l, "en:yes really English here"), .rematched(speaker: 0, from: .partner, to: .owner))
    }

    // MARK: a few minutes in, practice lines don't move them

    func testAfterAFewMinutesOfSpanishTwoEnglishPracticeLinesDontMoveThem() {
        var l = spanishSpeaker(after: 20)   // about two minutes
        say(&l, "en:thank you very much my friend")
        say(&l, "en:I am practising my English today")
        XCTAssertEqual(l.state(of: 0), .locked(.partner))
        XCTAssertEqual(l.lanes(for: 0), [.partner], "not even a check: they're well known by now")
    }

    func testBackAndForthBetweenTheLanguagesNeverAddsUp() {
        var l = spanishSpeaker(after: 10)
        for i in 0..<200 {
            if i.isMultiple(of: 2) { say(&l, "es:bueno, como te decía antes") }
            else { say(&l, "en:okay so what I wanted to say") }
            XCTAssertEqual(l.sides.half(ofSpeaker: 0), .partner, "line \(i): a practice line for every Spanish one never moves them")
        }
        XCTAssertEqual(l.lanes(for: 0), [.partner])
    }

    func testSpanglishLinesNeverMoveAnyoneAndDontWearDownTheConfidence() {
        var l = spanishSpeaker(after: 10)
        for i in 0..<300 {
            say(&l, "pero I don't know si vamos mañana or not")
            XCTAssertEqual(l.sides.half(ofSpeaker: 0), .partner, "line \(i)")
        }
        // Mixed lines are neither for nor against: the confidence built before is all still there.
        var fresh = spanishSpeaker(after: 10)
        say(&fresh, "es:bueno, como te decía antes")
        say(&l, "es:bueno, como te decía antes")
        var worn = l
        XCTAssertGreaterThanOrEqual(englishLinesToMove(&worn), englishLinesToMove(&fresh))
    }

    func testMixedLinesWakeTheCheckLaterTheBetterAVoiceIsKnown() {
        func linesToCheck(after built: Int) -> Int {
            var l = spanishSpeaker(after: built)
            var n = 0
            while l.state(of: 0) == .locked(.partner) && n < 100 { say(&l, "pero I don't know si vamos"); n += 1 }
            return n
        }
        XCTAssertEqual(linesToCheck(after: 0), 2, "a new lock: as before, two unclear lines")
        XCTAssertGreaterThan(linesToCheck(after: 5), linesToCheck(after: 0))
        XCTAssertGreaterThan(linesToCheck(after: 20), linesToCheck(after: 5) - 1)
    }

    func testAWellKnownVoiceInACheckIsNotMovedByOneEnglishVerdict() {
        var l = spanishSpeaker(after: 20)
        while l.state(of: 0) == .locked(.partner) { say(&l, "pero I don't know si vamos") }
        XCTAssertEqual(l.state(of: 0), .checking(.partner))
        XCTAssertNil(say(&l, "en:okay okay I understand you", lane: .owner))
        XCTAssertEqual(l.sides.half(ofSpeaker: 0), .partner)
        XCTAssertEqual(say(&l, "es:pues eso, mañana a las cuatro", lane: .partner), .kept(speaker: 0, .partner))
        XCTAssertEqual(l.lanes(for: 0), [.partner])
    }

    // MARK: a real change is still followed, in bounded time

    func testTheMoreSpanishHeardTheMoreEnglishItTakesToMoveThem() {
        var a = spanishSpeaker(after: 0), b = spanishSpeaker(after: 3), c = spanishSpeaker(after: 6)
        let (na, nb, nc) = (englishLinesToMove(&a), englishLinesToMove(&b), englishLinesToMove(&c))
        XCTAssertEqual(na, 2)
        XCTAssertGreaterThan(nb, na)
        XCTAssertGreaterThan(nc, nb)
    }

    func testConfidenceIsCappedSoAVoiceThatReallyChangesIsAlwaysFollowed() {
        // The diarizer can hand one person's slot to the other person; that must still be fixed.
        let policy = LanguageMatchPolicy()
        var capped = spanishSpeaker(after: 40), forever = spanishSpeaker(after: 400)
        let n = englishLinesToMove(&capped)
        XCTAssertEqual(englishLinesToMove(&forever), n, "an hour of Spanish doesn't make them unmovable")
        XCTAssertLessThan(n, 1000)
        if case .confidence(let cap, let moveBelow) = policy.correction {
            XCTAssertLessThanOrEqual(n, cap + moveBelow + 1, "bounded by the cap")
        } else { XCTFail("the shipping rule is the growing confidence") }
    }

    func testShortLinesAndTheOtherEnginesWordsBuildNoConfidence() {
        var l = spanishSpeaker(after: 0)
        for _ in 0..<30 { say(&l, "es:sí sí") }                                       // too short to count
        for _ in 0..<30 { say(&l, "es:sí, claro, el tren sale", lane: .owner) }      // not its own engine
        for _ in 0..<30 { say(&l, "es:sí, claro, el tren sale", final: false) }      // never finished
        XCTAssertEqual(englishLinesToMove(&l), 2, "only finished 4+ word lines from its own engine count")
    }

    func testEachVoiceBuildsItsOwnConfidence() {
        var l = spanishSpeaker(after: 20)
        say(&l, "en:Good morning, a ticket please", speaker: 1, lane: .owner)
        XCTAssertEqual(l.state(of: 1), .locked(.owner))
        // Speaker 1 is new: a wrong lock on them is still fixed in two lines, whatever is known about speaker 0.
        say(&l, "es:no, perdón, hablo español", speaker: 1, lane: .owner)
        XCTAssertEqual(say(&l, "es:de verdad hablo español", speaker: 1, lane: .owner),
                       .rematched(speaker: 1, from: .owner, to: .partner))
    }

    func testAMoveStartsTheConfidenceOverInTheNewLanguage() {
        var l = spanishSpeaker(after: 0)
        say(&l, "en:I am actually speaking English")
        say(&l, "en:yes really English here")
        XCTAssertEqual(l.state(of: 0), .locked(.owner))
        say(&l, "es:bueno pues hablo español", lane: .owner)
        XCTAssertEqual(say(&l, "es:sí, hablo español otra vez", lane: .owner), .rematched(speaker: 0, from: .owner, to: .partner),
                       "nothing carried over from before the move")
    }

    // MARK: #199's rule, still available for the comparison

    func testTheStreakRuleStillMovesAfterTwoLinesHoweverLongTheyHaveSpoken() {
        var policy = LanguageMatchPolicy()
        policy.correction = .streak(2)
        var l = spanishSpeaker(after: 50, policy: policy)
        say(&l, "en:thank you very much my friend")
        XCTAssertEqual(say(&l, "en:I am practising my English today"), .rematched(speaker: 0, from: .partner, to: .owner))
    }

    // MARK: real words through Apple's NaturalLanguage

    func testRealSpanglishLinesDontMoveAKnownSpanishSpeaker() {
        let pair = LanguagePair(owner: Locale(identifier: "en-US"), partner: Locale(identifier: "es-ES"))
        var l = SpeakerLanguages()
        var t = 0.0
        func line(_ text: String) {
            l.heard(speaker: 0, lane: l.lanes(for: 0).count == 1 ? l.lanes(for: 0).first! : .partner,
                    words: words(text, at: t), isFinal: true, classify: pair.probabilities)
            t += 5
        }
        let spanish = ["Buenos días, ¿en qué le puedo ayudar hoy?", "El tren al aeropuerto sale cada veinte minutos.",
                       "Tiene que comprar el billete en la máquina.", "Sí, acepta tarjeta y también efectivo.",
                       "El andén cuatro está al fondo, a la derecha.", "Mi hermana vive en Madrid desde hace años."]
        for _ in 0..<3 { spanish.forEach(line) }
        XCTAssertEqual(l.state(of: 0), .locked(.partner))
        let spanglish = ["Okay, pero I don't know si vamos mañana.", "Thank you, my friend, muchas gracias.",
                         "I'm learning English, it's very difficult.", "Sorry, my English is not very good.",
                         "Entonces we go to the airport juntos, okay?", "Yes, yes, I understand, no problem."]
        for text in spanglish { line(text); XCTAssertEqual(l.sides.half(ofSpeaker: 0), .partner, text) }
    }
}

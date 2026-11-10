import XCTest
@testable import CaptionCore

/// #91: one person talking alone was shown as Speaker 1, then 2, then sometimes 3. These pin down what the
/// smoother must hold steady (blips, a short pitch change mid-sentence) and what it must still let through at once
/// (real turns, short real replies, interruptions, someone new after a silence).
final class SpeakerLabelSmootherTests: XCTestCase {
    private func seg(_ speaker: Int, _ start: Double, _ end: Double) -> SpeakerSegment {
        SpeakerSegment(speaker: speaker, start: start, end: end)
    }

    func testNoSegmentsMeansNoLabelYet() {
        var s = SpeakerLabelSmoother()
        XCTAssertNil(s.label(start: 0, end: 2, segments: [], isFinal: false))
    }

    func testOneVoiceStaysOneSpeaker() {
        var s = SpeakerLabelSmoother()
        let segs = [seg(0, 0, 4), seg(0, 4.3, 9)]
        XCTAssertEqual(s.label(start: 0, end: 2, segments: segs, isFinal: false), 0)
        XCTAssertEqual(s.label(start: 0, end: 4, segments: segs, isFinal: true), 0)
        XCTAssertEqual(s.label(start: 4.3, end: 9, segments: segs, isFinal: true), 0)
    }

    func testALaughLengthBlipOfAnotherSlotDoesNotChangeTheSpeaker() {
        var s = SpeakerLabelSmoother()
        let segs = [seg(0, 0, 2.0), seg(1, 2.0, 2.3), seg(0, 2.3, 6)]
        XCTAssertEqual(s.label(start: 0, end: 1.8, segments: segs, isFinal: false), 0)
        XCTAssertEqual(s.label(start: 1.9, end: 2.4, segments: segs, isFinal: false), 0, "a 0.3 s blip must not flip the line")
        XCTAssertEqual(s.label(start: 0, end: 6, segments: segs, isFinal: true), 0)
    }

    func testAShortPitchChangeMidSentenceKeepsTheCurrentSpeakerWhileLive() {
        var s = SpeakerLabelSmoother()
        XCTAssertEqual(s.label(start: 0, end: 3, segments: [seg(0, 0, 3)], isFinal: true), 0)
        XCTAssertEqual(s.label(start: 3.4, end: 4.0, segments: [seg(0, 0, 3), seg(0, 3.4, 4.0)], isFinal: false), 0)
        // Still the same sentence; the model briefly puts the same person in slot 1 for 0.7 s.
        let segs = [seg(0, 0, 3), seg(0, 3.4, 4.0), seg(1, 4.0, 4.7)]
        XCTAssertEqual(s.label(start: 3.4, end: 4.7, segments: segs, isFinal: false), 0)
    }

    /// Two people are already known, so these test the rules on voices the session has already shown.
    private func knownPair() -> (SpeakerLabelSmoother, [SpeakerSegment]) {
        var s = SpeakerLabelSmoother()
        let history = [seg(0, 0, 3), seg(1, 3.5, 6.5)]
        _ = s.label(start: 0, end: 3, segments: history, isFinal: true)
        _ = s.label(start: 3.5, end: 6.5, segments: history, isFinal: true)
        _ = s.label(start: 7, end: 9, segments: history + [seg(0, 7, 9)], isFinal: true)
        return (s, history + [seg(0, 7, 9)])
    }

    func testABlipOfAKnownVoiceDoesNotTakeAShortCaption() {
        var (s, history) = knownPair()
        let segs = history + [seg(0, 9.3, 10.0), seg(1, 10.0, 10.3), seg(0, 10.3, 14)]
        XCTAssertEqual(s.label(start: 10.0, end: 10.4, segments: segs, isFinal: true), 0,
                       "0.3 s of the other person's slot inside a long stretch of mine is a blip")
    }

    func testALiveResultNeedsASecondOfTheOtherVoiceBeforeSwitching() {
        var (s, history) = knownPair()
        XCTAssertEqual(s.label(start: 9.3, end: 9.9, segments: history + [seg(0, 9.3, 9.9)], isFinal: false), 0)
        let segs = history + [seg(0, 9.3, 9.9), seg(1, 9.9, 10.6)]
        XCTAssertEqual(s.label(start: 9.3, end: 10.6, segments: segs, isFinal: false), 0, "same utterance, 0.7 s of the other voice")
        let more = history + [seg(0, 9.3, 9.9), seg(1, 9.9, 11.2)]
        XCTAssertEqual(s.label(start: 9.3, end: 11.2, segments: more, isFinal: false), 1)
    }

    /// A new utterance is judged on its own: holding the last speaker would merge the next person's first words
    /// into the previous person's line.
    func testANewUtteranceOfAKnownVoiceIsLabeledAtOnce() {
        var (s, history) = knownPair()
        let segs = history + [seg(1, 9.6, 10.3)]
        XCTAssertEqual(s.label(start: 9.6, end: 10.3, segments: segs, isFinal: false), 1)
    }

    func testARealTurnIsShownAndNumberedInOrderOfAppearance() {
        var s = SpeakerLabelSmoother()
        // Raw slots 2 then 0: the screen should still say Speaker 1 then Speaker 2.
        let segs = [seg(2, 0, 4), seg(0, 4.5, 8.5)]
        XCTAssertEqual(s.label(start: 0, end: 4, segments: segs, isFinal: true), 0)
        XCTAssertEqual(s.label(start: 4.5, end: 8.5, segments: segs, isFinal: true), 1)
        XCTAssertEqual(s.label(start: 9, end: 10, segments: segs + [seg(2, 9, 10.5)], isFinal: true), 0, "the first person keeps their number")
    }

    func testRapidBackAndForthStillAlternates() {
        var s = SpeakerLabelSmoother()
        var segs: [SpeakerSegment] = []
        var shown: [Int?] = []
        for i in 0..<6 {
            let start = Double(i) * 1.7
            segs.append(seg(i % 2 == 0 ? 0 : 1, start, start + 1.5))
            shown.append(s.label(start: start, end: start + 1.5, segments: segs, isFinal: true))
        }
        XCTAssertEqual(shown, [0, 1, 0, 1, 0, 1])
    }

    func testAShortRealReplyIsStillItsOwnSpeaker() {
        var s = SpeakerLabelSmoother()
        let segs = [seg(0, 0, 4), seg(1, 4.6, 5.0), seg(0, 5.4, 9)]
        XCTAssertEqual(s.label(start: 0, end: 4, segments: segs, isFinal: true), 0)
        // Speaker B's reply already had its own slot earlier in the conversation.
        var withHistory = SpeakerLabelSmoother()
        let earlier = [seg(1, 0, 3), seg(0, 3.5, 7), seg(1, 7.6, 8.0)]
        XCTAssertEqual(withHistory.label(start: 0, end: 3, segments: earlier, isFinal: true), 0)
        XCTAssertEqual(withHistory.label(start: 3.5, end: 7, segments: earlier, isFinal: true), 1)
        XCTAssertEqual(withHistory.label(start: 7.6, end: 8.0, segments: earlier, isFinal: true), 0, "a known voice's 0.4 s reply keeps its label")
    }

    func testAnInterruptionGoesToWhoeverSaysMostOfTheCaption() {
        var s = SpeakerLabelSmoother()
        XCTAssertEqual(s.label(start: 0, end: 3, segments: [seg(0, 0, 3), seg(1, 10, 12)], isFinal: true), 0)
        let segs = [seg(0, 0, 3), seg(1, 10, 12), seg(0, 12.5, 13.5), seg(1, 13.5, 16)]
        XCTAssertEqual(s.label(start: 12.5, end: 16, segments: segs, isFinal: true), 1)
    }

    /// Measured: making a never-seen slot "prove itself" merged the next person's first words into the previous
    /// person's line, so a new voice's first utterance is labeled as soon as it holds most of the caption.
    func testANewPersonsFirstShortUtteranceIsTheirsAtOnce() {
        var s = SpeakerLabelSmoother()
        XCTAssertEqual(s.label(start: 0, end: 4, segments: [seg(0, 0, 4)], isFinal: true), 0)
        let segs = [seg(0, 0, 4), seg(2, 4.5, 5.3)]
        XCTAssertEqual(s.label(start: 4.5, end: 5.3, segments: segs, isFinal: false), 1)
    }

    /// Measured: a 0.16 s scrap of an unused slot at the start of the second person's turn took "Speaker 2", so
    /// the second person became Speaker 3. A live scrap can't create a person; a final result can.
    func testALiveScrapOfAnUnseenSlotDoesNotTakeANumber() {
        var s = SpeakerLabelSmoother()
        XCTAssertEqual(s.label(start: 0, end: 3, segments: [seg(0, 0, 3)], isFinal: true), 0)
        let scrap = [seg(0, 0, 3), seg(1, 3.2, 3.36)]
        XCTAssertNil(s.label(start: 3.2, end: 3.4, segments: scrap, isFinal: false))
        let turn = scrap + [seg(2, 3.36, 6.4)]
        XCTAssertEqual(s.label(start: 3.2, end: 6.4, segments: turn, isFinal: false), 1, "the real second person is Speaker 2")
        var finals = SpeakerLabelSmoother()
        XCTAssertEqual(finals.label(start: 0, end: 3, segments: [seg(0, 0, 3)], isFinal: true), 0)
        XCTAssertEqual(finals.label(start: 3.2, end: 3.4, segments: scrap, isFinal: true), 1, "a final short utterance still gets its own speaker")
    }

    func testANewVoiceAfterALongSilenceIsANewSpeaker() {
        var s = SpeakerLabelSmoother()
        let segs = [seg(0, 0, 5), seg(1, 30, 34)]
        XCTAssertEqual(s.label(start: 0, end: 5, segments: segs, isFinal: true), 0)
        XCTAssertEqual(s.label(start: 30, end: 34, segments: segs, isFinal: true), 1)
    }

    func testTheFirstCaptionOfASessionTakesWhateverSlotItHas() {
        var s = SpeakerLabelSmoother()
        XCTAssertEqual(s.label(start: 0, end: 0.6, segments: [seg(3, 0, 0.6)], isFinal: false), 0)
    }

    func testAZeroLengthCaptionUsesTheSegmentContainingIt() {
        var s = SpeakerLabelSmoother()
        XCTAssertEqual(s.label(start: 2, end: 2, segments: [seg(1, 0, 5)], isFinal: false), 0)
    }

    func testTiedOverlapPrefersCurrent() {
        var s = SpeakerLabelSmoother()
        // Set current to slot 0 by labeling it first.
        XCTAssertEqual(s.label(start: 0, end: 2, segments: [seg(0, 0, 2)], isFinal: true), 0)
        // Now both slot 0 and slot 1 have 1.0s of overlap. Should stay with current (0).
        let segs = [seg(0, 0, 2), seg(1, 2, 3), seg(0, 2, 3)]
        XCTAssertEqual(s.label(start: 2, end: 3, segments: segs, isFinal: true), 0)
    }

    func testTiedOverlapPrefersLowestDisplayNumber() {
        var s = SpeakerLabelSmoother()
        var numbering: [Int: Int] = [:]
        // Establish slots 1, 0, 2 with display numbers 0, 1, 2.
        XCTAssertEqual(s.label(start: 0, end: 1, segments: [seg(1, 0, 1)], isFinal: true, numbering: &numbering), 0)
        XCTAssertEqual(s.label(start: 1, end: 2, segments: [seg(1, 0, 1), seg(0, 1, 2)], isFinal: true, numbering: &numbering), 1)
        XCTAssertEqual(s.label(start: 2, end: 3, segments: [seg(1, 0, 1), seg(0, 1, 2), seg(2, 2, 3)], isFinal: true, numbering: &numbering), 2)
        // Current is now 2. Create a tie between slots 0 and 1 (neither is current).
        // Both have 1.0s of overlap. Slot 0 has display 1, slot 1 has display 0.
        // Should pick slot 1 (display 0, lower than slot 0's display 1).
        let segs = [seg(0, 3, 4), seg(1, 3, 4)]
        XCTAssertEqual(s.label(start: 3, end: 4, segments: segs, isFinal: true, numbering: &numbering), 0)
    }

    func testTiedOverlapWithNoCurrentOrNumberPrefersLowestSlot() {
        var s = SpeakerLabelSmoother()
        // Create equal overlap between slots 3 and 1, neither seen before.
        // Slot 1 (lower index) should win and get display 0.
        let segs = [seg(3, 0, 1), seg(1, 0, 1)]
        XCTAssertEqual(s.label(start: 0, end: 1, segments: segs, isFinal: true), 0)
        // Now label a caption that spans only slot 1 to confirm it got display 0.
        // If slot 3 had won instead, slot 1 would get display 1 here.
        let segs2 = [seg(1, 1, 2)]
        XCTAssertEqual(s.label(start: 1, end: 2, segments: segs2, isFinal: true), 0)
    }

    func testTiedOverlapInThreeWayTiePicksCurrent() {
        var s = SpeakerLabelSmoother()
        // Set current to slot 1.
        XCTAssertEqual(s.label(start: 0, end: 1, segments: [seg(1, 0, 1)], isFinal: true), 0)
        // Three-way tie: slots 0, 1, 2 each have 0.5s. Should pick slot 1 (current).
        let segs = [seg(0, 1, 1.5), seg(1, 1, 1.5), seg(2, 1, 1.5)]
        XCTAssertEqual(s.label(start: 1, end: 1.5, segments: segs, isFinal: true), 0)
    }

    func testDeterministicNumberingWithTiedSlots() {
        var s = SpeakerLabelSmoother()
        // Slots 2 and 0 have equal overlap, neither seen; slot 0 (lower index) should win.
        let segs = [seg(2, 0, 1), seg(0, 0, 1)]
        XCTAssertEqual(s.label(start: 0, end: 1, segments: segs, isFinal: true), 0)
        // Slot 0 got display 0. Now assign display numbers to the others.
        let segs2 = segs + [seg(1, 1, 2)]
        XCTAssertEqual(s.label(start: 1, end: 2, segments: segs2, isFinal: true), 1)
        // Slot 1 got display 1. Now add slot 2, which gets display 2.
        let segs3 = [seg(2, 2, 3)]
        XCTAssertEqual(s.label(start: 2, end: 3, segments: segs3, isFinal: true), 2)
        // Now label slot 1 again (to set current to 1) before the final tie-break test.
        let segs4 = [seg(1, 3, 4)]
        XCTAssertEqual(s.label(start: 3, end: 4, segments: segs4, isFinal: true), 1)
        // Finally, tie between slots 0 (display 0) and 2 (display 2), with current = 1 (not in tie).
        // Should prefer lowest display number: slot 0.
        let segs5 = [seg(0, 4, 5), seg(2, 4, 5)]
        XCTAssertEqual(s.label(start: 4, end: 5, segments: segs5, isFinal: true), 0)
    }

    func testTiedOverlapStayingWithCurrentWhileLive() {
        var s = SpeakerLabelSmoother()
        XCTAssertEqual(s.label(start: 0, end: 2, segments: [seg(0, 0, 2)], isFinal: false), 0)
        // Same utterance with tied overlap: slots 0 and 1 each have 1.5s in [0, 3].
        // Should stick with current (0) even while live.
        let segs = [seg(0, 0, 1.5), seg(1, 1.5, 3)]
        XCTAssertEqual(s.label(start: 0, end: 3, segments: segs, isFinal: false), 0)
    }

    func testTiedOverlapSwitchesOnFinalResultIfMostOfCaption() {
        var s = SpeakerLabelSmoother()
        // Label slot 1 first so it gets display 0.
        XCTAssertEqual(s.label(start: 0, end: 1, segments: [seg(1, 0, 1)], isFinal: true), 0)
        // Label slot 0 second so it gets display 1, and set current = 0.
        XCTAssertEqual(s.label(start: 1, end: 2, segments: [seg(0, 1, 2)], isFinal: true), 1)
        // Label slot 2 third so it gets display 2, and set current = 2.
        XCTAssertEqual(s.label(start: 2, end: 3, segments: [seg(2, 2, 3)], isFinal: true), 2)
        // Create a tie between slots 0 and 1 (current = 2, not in tie).
        // Slot 1 (display 0) should win over slot 0 (display 1) on final result.
        let segs = [seg(0, 3, 3.5), seg(1, 3.5, 4)]
        XCTAssertEqual(s.label(start: 3, end: 4, segments: segs, isFinal: true), 0)
    }
}

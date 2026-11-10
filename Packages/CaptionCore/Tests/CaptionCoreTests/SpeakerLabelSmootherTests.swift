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

    // Tests for deterministic tie-breaking in chooseSlot.
    func testEqualOverlapPrefersCurrent() {
        var s = SpeakerLabelSmoother()
        // Establish speaker 0 as current.
        XCTAssertEqual(s.label(start: 0, end: 2, segments: [seg(0, 0, 2)], isFinal: true), 0)
        // Now equal overlap: slot 0 (current, 1.0s) vs slot 1 (1.0s); both touch the caption 2...3.
        let segs = [seg(0, 2, 3), seg(1, 2, 3)]
        XCTAssertEqual(s.label(start: 2, end: 3, segments: segs, isFinal: false), 0, "current speaker wins on tie")
    }

    func testEqualOverlapPrefersExistingDisplaySlot() {
        var s = SpeakerLabelSmoother()
        // Establish slot 2 as display 0, slot 5 as display 1.
        XCTAssertEqual(s.label(start: 0, end: 2, segments: [seg(2, 0, 2)], isFinal: true), 0)
        XCTAssertEqual(s.label(start: 3, end: 5, segments: [seg(2, 0, 2), seg(5, 3, 5)], isFinal: true), 1)
        // Both slot 2 (has display 0) and slot 7 (no display yet) have 1.0s overlap with caption 5...6.
        // Slot 2 should win because it has an existing display.
        let segs = [seg(2, 0, 2), seg(5, 3, 5), seg(2, 5, 6), seg(7, 5, 6)]
        XCTAssertEqual(s.label(start: 5, end: 6, segments: segs, isFinal: true), 0, "slot with display wins on tie")
    }

    func testEqualOverlapBreaksTieByLowestSlotKey() {
        var s = SpeakerLabelSmoother()
        // Establish: slot 3 → display 0.
        XCTAssertEqual(s.label(start: 0, end: 1, segments: [seg(3, 0, 1)], isFinal: true), 0)
        // Caption 1–2 with two new slots 5 and 11 both having 1.0s overlap.
        // Neither is current (current is slot 3), neither has a display yet.
        // Lowest slot key (5) should win and get display 1.
        let segs = [seg(5, 1, 2), seg(11, 1, 2)]
        XCTAssertEqual(s.label(start: 1, end: 2, segments: segs, isFinal: true), 1, "lower slot key wins on tie")
        // Caption 2–3 with only slot 5: if slot 5 won the tie, it's current and keeps display 1.
        // If slot 11 won incorrectly, slot 5 here gets a new display (2).
        XCTAssertEqual(s.label(start: 2, end: 3, segments: [seg(5, 2, 3)], isFinal: true), 1, "slot 5 must be current (won the tie)")
        // Caption 3–4 with only slot 11: if slot 5 won, slot 11 gets display 2 (new).
        // If slot 11 won the tie, it would be current and stay display 1.
        XCTAssertEqual(s.label(start: 3, end: 4, segments: [seg(11, 3, 4)], isFinal: true), 2, "slot 11 did not win the tie")
    }

    func testComplexTieBreakingRanking() {
        var s = SpeakerLabelSmoother()
        // Establish: slot 10 → display 0, slot 20 → display 1, current is slot 10.
        XCTAssertEqual(s.label(start: 0, end: 1, segments: [seg(10, 0, 1)], isFinal: true), 0)
        XCTAssertEqual(s.label(start: 2, end: 3, segments: [seg(10, 0, 1), seg(20, 2, 3)], isFinal: true), 1)
        // Now: slot 10 (current, has display 0, 1.0s) vs slot 5 (no display, 1.0s) vs slot 30 (no display, 1.0s).
        // Slot 10 should win: current + has display.
        let segs = [seg(10, 0, 1), seg(20, 2, 3), seg(10, 3, 4), seg(5, 3, 4), seg(30, 3, 4)]
        XCTAssertEqual(s.label(start: 3, end: 4, segments: segs, isFinal: true), 0)
    }

    func testTieBreakingWithNoCurrentButDisplayExists() {
        var s = SpeakerLabelSmoother()
        // Establish: slot 7 → display 0, slot 11 → display 1.
        XCTAssertEqual(s.label(start: 0, end: 1, segments: [seg(7, 0, 1)], isFinal: true), 0)
        XCTAssertEqual(s.label(start: 2, end: 3, segments: [seg(7, 0, 1), seg(11, 2, 3)], isFinal: true), 1)
        // Now: slot 7 (has display 0, 0.5s) vs slot 3 (no display, 0.5s).
        // Slot 7 should win because it has an existing display, even without being current.
        let segs = [seg(7, 3.5, 4), seg(3, 3, 3.5), seg(11, 2, 3)]
        XCTAssertEqual(s.label(start: 3, end: 4, segments: segs, isFinal: false), 0)
    }

    func testDeterministicOrderingAcrossMultipleCalls() {
        var s1 = SpeakerLabelSmoother()
        var s2 = SpeakerLabelSmoother()
        // Both smoothers see the same data but possibly in different internal orders.
        // They must produce the same labeling.
        // Caption 1.0–2.0:
        // seg(1, 0.5, 1.5): overlaps 1.0–1.5 = 0.5s
        // seg(3, 1.5, 2.0): overlaps 1.5–2.0 = 0.5s
        // seg(5, 1.25, 1.75): overlaps 1.25–1.75 = 0.5s
        // All three slots have 0.5s overlap; lowest key (1) should always win.
        let segsA = [seg(1, 0.5, 1.5), seg(3, 1.5, 2.0), seg(5, 1.25, 1.75)]
        let segsB = [seg(5, 1.25, 1.75), seg(1, 0.5, 1.5), seg(3, 1.5, 2.0)] // same segments, different order
        XCTAssertEqual(s1.label(start: 1.0, end: 2.0, segments: segsA, isFinal: true), 0)
        XCTAssertEqual(s2.label(start: 1.0, end: 2.0, segments: segsB, isFinal: true), 0)
        // Follow-up caption 2.0–3.0 with only slot 1: both smoothers must show it as display 0 (current).
        // If either smoother incorrectly chose slot 3 or 5 as current, slot 1 would get display 1 here.
        XCTAssertEqual(s1.label(start: 2.0, end: 3.0, segments: [seg(1, 2.0, 3.0)], isFinal: true), 0, "s1: slot 1 must be current (lowest key won)")
        XCTAssertEqual(s2.label(start: 2.0, end: 3.0, segments: [seg(1, 2.0, 3.0)], isFinal: true), 0, "s2: slot 1 must be current (lowest key won)")
    }
}

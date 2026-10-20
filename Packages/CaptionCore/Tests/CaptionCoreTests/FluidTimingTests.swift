import XCTest
@testable import CaptionCore

/// The fluidity pass (owner, 2026-10-20: "I want it all to be more fluid"). Still fades only; one set of timings.
final class FluidTimingTests: XCTestCase {
    func testPageChangesOverlapSoTheScreenNeverGoesBlank() {
        for reduce in [false, true] {
            let t = FluidTiming.page(reduceMotion: reduce)
            XCTAssertLessThan(t.inDelay, t.out, "the next page starts before the last one is gone (reduce \(reduce))")
            XCTAssertGreaterThan(t.inDelay, 0, "but not at the same instant: text over text at full strength")
        }
    }

    func testPageChangesAreNoSlowerThanBefore() {
        // Round 2 was 0.25 out + 0.25 in, one after the other.
        let t = FluidTiming.page(reduceMotion: false)
        XCTAssertLessThanOrEqual(t.inDelay + t.in, 0.5)
        XCTAssertLessThanOrEqual(FluidTiming.page(reduceMotion: true).total, 0.3)
    }

    func testOneFadeAndOneQuickDuration() {
        XCTAssertLessThan(FluidTiming.quick(reduceMotion: false), FluidTiming.fade(reduceMotion: false))
        XCTAssertEqual(FluidTiming.fade(reduceMotion: false), 0.35)
    }

    func testReduceMotionIsShorterEverywhere() {
        XCTAssertLessThan(FluidTiming.fade(reduceMotion: true), FluidTiming.fade(reduceMotion: false))
        XCTAssertLessThan(FluidTiming.quick(reduceMotion: true), FluidTiming.quick(reduceMotion: false))
        XCTAssertLessThan(FluidTiming.page(reduceMotion: true).total, FluidTiming.page(reduceMotion: false).total)
    }

    func testTheSaveMomentIsSlowerThanOtherSmallChanges() {
        // Owner, 2026-10-20: the shrink-and-grow "just needs to be slowed down a smidge".
        XCTAssertGreaterThanOrEqual(FluidTiming.saveMorph(reduceMotion: false), FluidTiming.quick(reduceMotion: false) * 1.6)
        let w = FluidTiming.bracketWordSwap(reduceMotion: false)
        XCTAssertGreaterThanOrEqual(w.inDelay, w.out, "the old word is gone before the new one starts")
        XCTAssertEqual(w.inDelay + w.in, FluidTiming.saveMorph(reduceMotion: false), accuracy: 0.05,
                       "the word lands as the brackets finish")
        XCTAssertGreaterThanOrEqual(FluidTiming.saveMoment, FluidTiming.saveCheckHold + FluidTiming.saveMorph(reduceMotion: false))
        XCTAssertLessThan(FluidTiming.saveMorph(reduceMotion: true), FluidTiming.saveMorph(reduceMotion: false))
    }

    func testSaveMomentHoldsTheCheckLongEnoughToSee() {
        // [ ✔ ] stays readable, then eases into [ Saved ]; the tour waits for the whole moment (#121).
        XCTAssertGreaterThanOrEqual(FluidTiming.saveCheckHold, 0.6)
        XCTAssertGreaterThanOrEqual(FluidTiming.saveMoment, FluidTiming.saveCheckHold + FluidTiming.fade(reduceMotion: false))
    }
}

final class FluidDimTimingTests: XCTestCase {
    func testWordsLeaveBeforeTheDimFinishesAndArriveAfterItStarts() {
        for reduce in [false, true] {
            let d = FluidTiming.dim(reduceMotion: reduce)
            XCTAssertLessThan(d.words, d.dim, "words gone before the dim has lifted")
            XCTAssertGreaterThan(d.dimOutDelay, 0, "the dim waits a moment for the words to start leaving")
            XCTAssertGreaterThan(d.wordsInDelay, 0, "coming back, the dim lands before the words")
            XCTAssertLessThan(d.wordsInDelay + d.words, d.dim + 0.05, "and the whole return is about one dim long")
        }
    }

    func testAWordSwapIsOutThenIn() {
        for reduce in [false, true] {
            let w = FluidTiming.wordSwap(reduceMotion: reduce)
            XCTAssertGreaterThanOrEqual(w.inDelay, w.out * 0.75, "the old word is (nearly) gone before the new one shows")
            XCTAssertLessThanOrEqual(w.inDelay + w.in, 0.3)
        }
    }

    func testThePillLabelWaitsForThePillToGrow() {
        XCTAssertGreaterThanOrEqual(FluidTiming.pillLabelInDelay, 0.3, "0.22 still showed a clipped \"tart captions\" on a recording")
    }
}

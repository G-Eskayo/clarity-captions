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

    func testSaveMomentHoldsTheCheckLongEnoughToSee() {
        // [ ✔ ] stays readable, then eases into [ Saved ]; the tour waits for the whole moment (#121).
        XCTAssertGreaterThanOrEqual(FluidTiming.saveCheckHold, 0.6)
        XCTAssertGreaterThanOrEqual(FluidTiming.saveMoment, FluidTiming.saveCheckHold + FluidTiming.fade(reduceMotion: false))
    }
}

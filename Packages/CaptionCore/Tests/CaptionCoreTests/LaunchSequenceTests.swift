import XCTest
@testable import CaptionCore

/// The launch animation's timing rules (#104, owner's #99 answers): the dance always finishes, the hold is 0.75 s,
/// and the bar only shows when real work outlasts the animation.
final class LaunchSequenceTests: XCTestCase {
    let seq = LaunchSequence(reducedMotion: false)
    var dance: Double { seq.danceEnd }

    /// Phases carry seconds and progress as Doubles: compare them with a tolerance.
    private func assertPhase(_ got: LaunchSequence.Phase, _ want: LaunchSequence.Phase, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        func split(_ p: LaunchSequence.Phase) -> (String, Double) {
            switch p {
            case .dancing(let x): ("dancing", x)
            case .readyBeat(let x): ("readyBeat", x)
            case .handoff(let x): ("handoff", x)
            case .waiting: ("waiting", 0)
            case .holding: ("holding", 0)
            case .finished: ("finished", 0)
            }
        }
        let (a, x) = split(got), (b, y) = split(want)
        XCTAssertEqual(a, b, message, file: file, line: line)
        XCTAssertEqual(x, y, accuracy: 1e-9, message, file: file, line: line)
    }

    func testTheDanceIsBellySlideClapWaveAndSettle() {
        XCTAssertEqual(dance, 1.1 + 1.2 + 1.0 + 0.45, accuracy: 1e-9)
    }

    // MARK: the dance always finishes

    func testReadyImmediatelyStillPlaysTheWholeDance() {
        XCTAssertEqual(seq.beatStart(readyAt: 0), dance)
        assertPhase(seq.phase(at: dance - 0.01, readyAt: 0), .dancing(progress: (dance - 0.01) / dance))
        assertPhase(seq.phase(at: dance + 0.01, readyAt: 0), .readyBeat(progress: 0.01 / 0.55))
    }

    func testTheHoldIsThreeQuartersOfASecondAfterTheReadyBeat() {
        let beatEnd = dance + LaunchSequence.readyBeat
        XCTAssertEqual(seq.handoffStart(readyAt: 0) - beatEnd, 0.75, accuracy: 1e-9)
        XCTAssertEqual(seq.phase(at: beatEnd + 0.7, readyAt: 0), .holding)
        assertPhase(seq.phase(at: beatEnd + 0.76, readyAt: 0), .handoff(seconds: 0.01), "after the hold")
    }

    func testSlowReadinessHoldsThePoseThenBeatsWhenReady() {
        XCTAssertEqual(seq.phase(at: dance + 2, readyAt: nil), .waiting)
        XCTAssertEqual(seq.phase(at: 9.9, readyAt: 10), .waiting)
        XCTAssertEqual(seq.beatStart(readyAt: 10), 10)
        XCTAssertEqual(seq.handoffStart(readyAt: 10), 10 + 0.55 + 0.75, accuracy: 1e-9)
    }

    func testNeverHandsOffWhileNotReady() {
        for t in stride(from: dance, through: 600, by: 37.5) {
            XCTAssertEqual(seq.phase(at: t, readyAt: nil), .waiting)
        }
    }

    func testFinishesExactlyAtTheEnd() {
        let end = seq.end(readyAt: 0)
        XCTAssertEqual(end, dance + 0.55 + 0.75 + 1.9, accuracy: 1e-9)
        assertPhase(seq.phase(at: end - 0.001, readyAt: 0), .handoff(seconds: 1.9 - 0.001))
        XCTAssertEqual(seq.phase(at: end, readyAt: 0), .finished)
    }

    func testANegativeOrZeroTimeIsTheFirstFrame() {
        XCTAssertEqual(seq.phase(at: -1, readyAt: nil), .dancing(progress: 0))
    }

    // MARK: the bar

    func testOrdinaryFastLaunchNeverShowsTheBar() {
        for t in stride(from: 0.0, through: seq.end(readyAt: 0.05), by: 0.05) {
            XCTAssertEqual(seq.barOpacity(at: t, readyAt: 0.05, setupKnown: false), 0, "t=\(t)")
        }
    }

    func testKnownSetupShowsTheBarFromTheStart() {
        XCTAssertEqual(seq.barOpacity(at: 0, readyAt: nil, setupKnown: true), 0)
        XCTAssertEqual(seq.barOpacity(at: LaunchSequence.barFadeIn, readyAt: nil, setupKnown: true), 1)
        XCTAssertEqual(seq.barOpacity(at: 1, readyAt: nil, setupKnown: true), 1)
    }

    func testNotReadyByTheEndOfTheDanceFadesTheBarIn() {
        XCTAssertEqual(seq.barOpacity(at: dance - 0.1, readyAt: nil, setupKnown: false), 0)
        XCTAssertEqual(seq.barOpacity(at: dance + 0.25, readyAt: nil, setupKnown: false), 1)
        // Readiness that arrives later keeps it up until the hand-off.
        XCTAssertEqual(seq.barOpacity(at: 6, readyAt: 5.5, setupKnown: false), 1)
    }

    func testReadyBeforeTheDanceEndsKeepsTheBarHiddenEvenIfReadinessWasSlowish() {
        XCTAssertEqual(seq.barOpacity(at: dance + 0.5, readyAt: dance - 0.2, setupKnown: false), 0)
    }

    func testTheBarFadesOutAtTheHandoff() {
        let handoff = seq.handoffStart(readyAt: 8)
        XCTAssertEqual(seq.barOpacity(at: handoff - 0.01, readyAt: 8, setupKnown: true), 1)
        XCTAssertEqual(seq.barOpacity(at: handoff + 0.1, readyAt: 8, setupKnown: true), 0.5, accuracy: 1e-9)
        XCTAssertEqual(seq.barOpacity(at: handoff + 0.2, readyAt: 8, setupKnown: true), 0, accuracy: 1e-9)
    }

    // MARK: Reduce Motion

    func testReduceMotionFadesInHoldsAndCrossFades() {
        let reduced = LaunchSequence(reducedMotion: true)
        XCTAssertEqual(reduced.danceEnd, 0.3)
        XCTAssertEqual(reduced.beatLength, 0)
        XCTAssertEqual(reduced.handoffStart(readyAt: 0), 0.3 + 0.75, accuracy: 1e-9)
        XCTAssertEqual(reduced.end(readyAt: 0), 0.3 + 0.75 + 0.6, accuracy: 1e-9)
        XCTAssertEqual(reduced.phase(at: 0.5, readyAt: 0), .holding, "no ready beat")
    }

    // MARK: progress comes from the real steps

    func testDownloadFillsThreeQuartersOfTheBarByItsRealPercentage() {
        XCTAssertEqual(LaunchProgress.at(step: .speechModel, downloadProgress: 0.5, includesDownload: true),
                       LaunchProgress(fill: 0.375, pulse: nil))
        XCTAssertEqual(LaunchProgress.at(step: .speechModel, downloadProgress: 7, includesDownload: true).fill, 0.75,
                       "a bad percentage never overfills")
    }

    func testWarmUpHasNoPercentageSoItsPartPulses() {
        XCTAssertEqual(LaunchProgress.at(step: .speakerModel, downloadProgress: 1, includesDownload: true),
                       LaunchProgress(fill: 0.75, pulse: 0.75...1))
        XCTAssertEqual(LaunchProgress.at(step: .speakerModel, downloadProgress: 0, includesDownload: false),
                       LaunchProgress(fill: 0, pulse: 0...1), "after an update only the warm-up runs: it spans the bar")
    }

    func testNothingLeftToDoFillsTheBar() {
        XCTAssertEqual(LaunchProgress.at(step: .done, downloadProgress: 0, includesDownload: false).fill, 1)
    }

    func testOnlyDownloadAndWarmUpAreAutomaticSetup() {
        XCTAssertEqual(FirstRunStep.allCases.filter(\.isAutomaticSetup), [.speechModel, .speakerModel])
    }
}

/// The seal's moves, matching the approved prototype.
final class SealChoreographyTests: XCTestCase {
    func testItStartsOffScreenSlidingInFromTheLeft() {
        let first = SealChoreography.pose(at: 0)
        XCTAssertEqual(first.dx, -460)
        XCTAssertEqual(first.raysOpacity, 0)
        XCTAssertEqual(first.speedLines, 1)
    }

    func testTheDanceEndsInTheIconsPoseAndHoldsIt() {
        for u in [SealChoreography.danceLength, SealChoreography.danceLength + 5] {
            let p = SealChoreography.pose(at: u)
            XCTAssertEqual(p.dx, 0); XCTAssertEqual(p.dy, 0); XCTAssertEqual(p.rotation, 0)
            XCTAssertEqual(p.frontFlipper, 0, accuracy: 1e-9); XCTAssertEqual(p.rays, 1); XCTAssertEqual(p.raysOpacity, 1)
            XCTAssertEqual(p.scaleX, 1); XCTAssertEqual(p.scaleY, 1)
        }
    }

    func testItClapsThenWaves() {
        let clap = SealChoreography.pose(at: SealChoreography.entrance + 0.3)
        XCTAssertLessThan(clap.frontFlipper, 0); XCTAssertGreaterThan(clap.backFlipper, 0)
        let wave = SealChoreography.pose(at: SealChoreography.entrance + SealChoreography.clap + 0.3)
        XCTAssertLessThan(wave.frontFlipper, -30, "flipper raised to wave")
        XCTAssertEqual(wave.backFlipper, 0)
    }

    func testTheReadyBeatStartsAndEndsOnTheFrozenPose() {
        let rest = SealChoreography.pose(at: SealChoreography.danceLength)
        XCTAssertEqual(SealChoreography.readyBeat(rest, progress: 0), rest)
        let end = SealChoreography.readyBeat(rest, progress: 1)
        XCTAssertEqual(end.rotation, 0, accuracy: 1e-9); XCTAssertEqual(end.dy, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(SealChoreography.readyBeat(rest, progress: 0.3).rays, 1, "rays flash mid-beat")
    }

    func testTheGreenClosesBehindTheSealToAPoolThenTheSealDivesIn() {
        let rest = SealPose.rest
        XCTAssertEqual(SealHandoffFrame.at(0, from: rest).irisRadius, SealHandoffFrame.coverRadius)
        XCTAssertEqual(SealHandoffFrame.at(0.5, from: rest).irisRadius, SealHandoffFrame.poolRadius, accuracy: 1e-9)
        XCTAssertEqual(SealHandoffFrame.at(0.5, from: rest).irisClosed, 1)
        let mid = SealHandoffFrame.at(0.66, from: rest)
        XCTAssertLessThan(mid.sealY, SealHandoffFrame.at(0.42, from: rest).sealY, "jumps up in an arc")
        let landed = SealHandoffFrame.at(0.93, from: rest)
        XCTAssertEqual(landed.pose.opacity, 0, accuracy: 1e-9)
        XCTAssertEqual(landed.sealX, SealHandoffFrame.center.x, accuracy: 1e-9)
        XCTAssertEqual(SealHandoffFrame.at(1.2, from: rest).irisRadius, 0, accuracy: 1e-9, "the pool closes")
    }

    func testSplashThenPlainRingsRippleOutAndFade() {
        let rest = SealPose.rest
        XCTAssertNil(SealHandoffFrame.at(0.8, from: rest).splash)
        XCTAssertNotNil(SealHandoffFrame.at(1.0, from: rest).splash)
        XCTAssertTrue(SealHandoffFrame.at(0.85, from: rest).rings.allSatisfy { $0.opacity == 0 })
        let rings = SealHandoffFrame.at(1.2, from: rest).rings
        XCTAssertEqual(rings.count, 3)
        XCTAssertGreaterThan(rings[0].radius, rings[1].radius, "rings follow one another out")
        XCTAssertTrue(SealHandoffFrame.at(1.9, from: rest).rings.allSatisfy { $0.opacity == 0 }, "all gone by the end")
    }
}

/// The splash's colours come from the chosen theme (#105's model), and the pool reads clearly on every dark theme.
final class SealLaunchColorsTests: XCTestCase {
    private func style(_ p: CaptionPreset) -> CaptionStyle { CaptionStyle.standard.applying(p) }

    func testThePoolIsBrightenedOnEveryDarkThemeAndReadsClearly() throws {
        let dark = CaptionPreset.all.filter { $0.background.isDark }
        XCTAssertEqual(dark.map(\.id), ["charcoal", "night", "harbor"])
        for p in dark {
            let colors = SealLaunchColors(theme: style(p))
            let pool = try XCTUnwrap(colors.pool)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(pool, p.background), 3, "\(p.id): the pool must stand out (3:1 for graphics)")
            XCTAssertGreaterThanOrEqual(RGBA.contrast(colors.ripple, p.background), 3, "\(p.id): ripples")
        }
    }

    func testLightThemesKeepTheLaunchGreenAndTheIconTeal() {
        for p in CaptionPreset.all where !p.background.isDark {
            let colors = SealLaunchColors(theme: style(p))
            XCTAssertNil(colors.pool)
            XCTAssertEqual(colors.ripple, SealLaunchColors.brightTeal)
        }
    }
}

import XCTest
@testable import CaptionCore

/// The seal's motion is smooth (#119, owner on #117: "the wave looks like shapes moving on top of each other… more
/// frames would give it a smoother and more dynamic approach"). Sampled at ProMotion's 120 Hz, no part of the pose may
/// jump between two frames: a jump is a part teleporting, which reads as blocky however high the frame rate.
final class SealMotionTests: XCTestCase {
    static let frame = 1.0 / 120

    /// The largest change any channel may make in one 120 Hz frame.
    struct Limits {
        var angle = 12.0, scale = 0.04, level = 0.15, move = 25.0, opacity = 0.15
    }

    private func assertContinuous(_ a: SealPose, _ b: SealPose, at t: Double, _ what: String,
                                  limits: Limits = Limits(), file: StaticString = #filePath, line: UInt = #line) {
        let checks: [(String, Double, Double)] = [
            ("rotation", abs(a.rotation - b.rotation), limits.angle),
            ("frontFlipper", abs(a.frontFlipper - b.frontFlipper), limits.angle),
            ("backFlipper", abs(a.backFlipper - b.backFlipper), limits.angle),
            ("frontFlipperTip", abs(a.frontFlipperTip - b.frontFlipperTip), limits.angle),
            ("backFlipperTip", abs(a.backFlipperTip - b.backFlipperTip), limits.angle),
            ("scaleX", abs(a.scaleX - b.scaleX), limits.scale),
            ("scaleY", abs(a.scaleY - b.scaleY), limits.scale),
            ("mouthOpen", abs(a.mouthOpen - b.mouthOpen), limits.level),
            ("rays", abs(a.rays - b.rays), limits.level),
            ("raysOpacity", abs(a.raysOpacity - b.raysOpacity), limits.level),
            ("whiskerBend", abs(a.whiskerBend - b.whiskerBend), limits.level),
            ("speedLines", abs(a.speedLines - b.speedLines), limits.level),
            ("dx", abs(a.dx - b.dx), limits.move),
            ("dy", abs(a.dy - b.dy), limits.move),
            ("opacity", abs(a.opacity - b.opacity), limits.opacity),
        ]
        for (name, delta, limit) in checks where delta > limit {
            XCTFail("\(what): \(name) jumps \(String(format: "%.3f", delta)) in one frame at t=\(String(format: "%.3f", t)) (limit \(limit))",
                    file: file, line: line)
        }
    }

    // MARK: the dance

    func testNoPartOfTheSealJumpsAnywhereInTheDance() {
        var t = 0.0, previous = SealChoreography.pose(at: 0)
        while t < SealChoreography.danceLength + 0.3 {
            t += Self.frame
            let pose = SealChoreography.pose(at: t)
            assertContinuous(previous, pose, at: t, "dance")
            previous = pose
        }
    }

    /// The seams where one move hands over to the next are where the old version jumped (e.g. the front flipper
    /// snapped from 0° to −62° when the clap became the wave).
    func testTheSeamsBetweenMovesAreSmooth() {
        let seams = [0.85, SealChoreography.entrance, SealChoreography.entrance + SealChoreography.clap,
                     SealChoreography.entrance + SealChoreography.clap + SealChoreography.wave]
        for seam in seams {
            assertContinuous(SealChoreography.pose(at: seam - Self.frame), SealChoreography.pose(at: seam + Self.frame),
                             at: seam, "seam at \(seam)", limits: Limits(angle: 12, scale: 0.04, level: 0.15, move: 25, opacity: 0.15))
        }
    }

    func testTheReadyBeatIsSmoothFromStartToEnd() {
        var k = 0.0, previous = SealChoreography.readyBeat(.rest, progress: 0)
        while k < 1 {
            k += Self.frame / LaunchSequence.readyBeat
            let pose = SealChoreography.readyBeat(.rest, progress: k)
            assertContinuous(previous, pose, at: k, "ready beat")
            previous = pose
        }
        assertContinuous(SealChoreography.pose(at: SealChoreography.danceLength + 1), SealChoreography.readyBeat(.rest, progress: 0),
                         at: 0, "dance end → ready beat")
    }

    // MARK: follow-through (parts move together, not as rigid shapes)

    func testFlipperTipsTrailTheFlipperWhileItMoves() {
        let midWave = SealChoreography.entrance + SealChoreography.clap + SealChoreography.wave * 0.3
        var bends = 0
        var t = midWave
        while t < midWave + 0.5 {
            if abs(SealChoreography.pose(at: t).frontFlipperTip) > 3 { bends += 1 }
            t += Self.frame
        }
        XCTAssertGreaterThan(bends, 10, "the front flipper's tip should bend behind the wave, not stay rigid")
    }

    func testWhiskersBendWithTheBodyAndTheSlide() {
        let slide = SealChoreography.pose(at: 0.4)
        XCTAssertNotEqual(slide.whiskerBend, 0, accuracy: 0.05, "whiskers trail the belly slide")
        let wiggle = (0..<60).map { SealChoreography.pose(at: SealChoreography.entrance + 0.3 + Double($0) * Self.frame).whiskerBend }
        XCTAssertGreaterThan(wiggle.max()! - wiggle.min()!, 0.1, "whiskers sway as the body wiggles during the clap")
    }

    func testTheSecondaryMotionIsBoundedSoNothingBreaksApart() {
        var t = 0.0
        while t < SealChoreography.danceLength {
            let p = SealChoreography.pose(at: t)
            XCTAssertLessThanOrEqual(abs(p.frontFlipperTip), SealChoreography.maxTipBend + 1e-9)
            XCTAssertLessThanOrEqual(abs(p.backFlipperTip), SealChoreography.maxTipBend + 1e-9)
            XCTAssertLessThanOrEqual(abs(p.whiskerBend), 1 + 1e-9)
            t += Self.frame
        }
    }

    /// The freeze frame is the icon itself: once the dance has settled, every follow-through has died away.
    func testTheDanceStillEndsExactlyInTheIconsPose() {
        let end = SealChoreography.pose(at: SealChoreography.danceLength + 0.5)
        XCTAssertEqual(end, .rest)
        XCTAssertEqual(SealChoreography.pose(at: SealChoreography.danceLength + 30), .rest)
    }

    func testTheApprovedChoreographyIsKept() {
        XCTAssertLessThan(SealChoreography.pose(at: 0.1).dx, -200, "starts off-screen left: the belly slide")
        XCTAssertGreaterThan(SealChoreography.pose(at: 0.4).speedLines, 0.5, "speed lines during the slide")
        let clapping = (0..<120).map { SealChoreography.pose(at: SealChoreography.entrance + Double($0) / 100).frontFlipper }
        XCTAssertLessThan(clapping.min()!, -40, "A's clap swings the front flipper")
        let waving = SealChoreography.pose(at: SealChoreography.entrance + SealChoreography.clap + 0.5)
        XCTAssertLessThan(waving.frontFlipper, -30, "C's wave holds the flipper up")
        XCTAssertGreaterThan(waving.raysOpacity, 0.9, "and barks")
    }

    // MARK: the hand-off

    func testTheHandOffHasNoJumps() {
        var h = 0.0, previous = SealHandoffFrame.at(0, from: .rest)
        while h < LaunchSequence.handoff {
            h += Self.frame
            let f = SealHandoffFrame.at(h, from: .rest)
            assertContinuous(previous.pose, f.pose, at: h, "hand-off seal")
            XCTAssertLessThan(abs(f.irisRadius - previous.irisRadius), 30, "iris jumps at h=\(h)")
            XCTAssertLessThan(abs(f.sealX - previous.sealX), 25, "seal x jumps at h=\(h)")
            XCTAssertLessThan(abs(f.sealY - previous.sealY), 25, "seal y jumps at h=\(h)")
            XCTAssertLessThan(abs(f.sealScale - previous.sealScale), 0.05, "seal scale jumps at h=\(h)")
            for (a, b) in zip(f.rings, previous.rings) {
                XCTAssertLessThan(abs(a.opacity - b.opacity), 0.15, "a ring pops in or out at h=\(h)")
            }
            XCTAssertLessThan(abs(f.splashOpacity - previous.splashOpacity), 0.2, "the splash pops at h=\(h)")
            previous = f
        }
    }

    func testTheHandOffStartsFromTheFreezeFrame() {
        let start = SealHandoffFrame.at(0, from: .rest)
        XCTAssertEqual(start.pose, .rest)
        XCTAssertEqual(start.irisRadius, SealHandoffFrame.coverRadius, accuracy: 1e-9)
    }
}

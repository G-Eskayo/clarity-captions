import CaptionCore
import SwiftUI
import UIKit

/// When the app process started, for the launch-to-Start measurement (#104).
enum LaunchClock {
    static let start = Date()
}

/// The launch animation (#104, approved in #99; spec §8): on the green launch screen the seal belly-slides in, claps,
/// waves and barks, and settles into the icon's pose. Once the app is ready it does a happy beat, holds for 0.75 s,
/// then the green closes in behind it to a pool, it jumps in with a splash, and plain rings ripple out over the screen
/// underneath. The bar shows only when real work outlasts the dance. Timing and moves live in CaptionCore
/// (LaunchSequence, SealChoreography); this view only draws them.
struct LaunchOverlay: View {
    @ObservedObject var firstRun: FirstRunModel
    /// The captioning engine loading behind the dance (#119): the launch covers the getting-ready.
    @ObservedObject private var engine = EngineWarmupHost.shared
    let onFinished: () -> Void
    /// How the last launch went, for the beta measurements (ADR 0023): the full dance (not Reduce Motion's fade) and
    /// whether the progress bar showed.
    static var lastFullDance = false
    static var lastBarShown = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Moves only on drawn frames, so a startup stall never skips the belly slide (see LaunchAnimationClock).
    @State private var clock = LaunchAnimationClock()
    @State private var readyAt: TimeInterval?
    @State private var setupKnown = false
    @State private var includesDownload = false
    @State private var done = false
    private let colors: SealLaunchColors
    /// The launch green exactly as the system launch screen drew it: by the system appearance, not the app's theme
    /// (the main screen forces its own light or dark look), so the first frame matches and nothing flashes.
    private let launchGreen: Color

    init(firstRun: FirstRunModel, theme: CaptionStyle, onFinished: @escaping () -> Void) {
        self.firstRun = firstRun
        self.onFinished = onFinished
        colors = SealLaunchColors(theme: theme)
        let screenStyle = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.traitCollection.userInterfaceStyle ?? .light
        let green = UIColor(named: "LaunchBackground") ?? UIColor(SealLaunchColors.brightTeal.color)
        launchGreen = Color(green.resolvedColor(with: UITraitCollection(userInterfaceStyle: screenStyle)))
    }

    private var sequence: LaunchSequence { LaunchSequence(reducedMotion: reduceMotion) }

    /// First run has nothing left to do here: the facts are in and nothing is being set up, or setup stopped with a
    /// problem (the screen beneath then shows it with Try again, so a failed download never hangs here).
    private var firstRunReady: Bool {
        firstRun.checked && (firstRun.problem != nil || !firstRun.step.isAutomaticSetup)
    }

    /// Ready once first run is done and the captioning engine has loaded (#119), never held by a failed or hung load
    /// (LaunchReadiness). A first-run problem ends the launch at once, whatever the engine is doing.
    private func isReady(at t: TimeInterval) -> Bool {
        if firstRun.checked && firstRun.problem != nil { return true }
        return LaunchReadiness.isReady(firstRunReady: firstRunReady, warmup: engine.state,
                                       waitedPastDance: max(0, t - sequence.danceEnd))
    }

    var body: some View {
        TimelineView(.animation(paused: done)) { timeline in
            let t = clock.advance(to: timeline.date)
            Canvas { context, size in draw(in: &context, size: size, t: t) }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel(Text("Seal is getting ready"))
        .onAppear {
            noteSetup(firstRun.step)
            if isReady(at: 0) { readyAt = 0 }
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Seal is getting ready"))
        }
        .onChange(of: firstRun.step) { _, step in noteSetup(step) }
        .task { await waitForEnd() }
    }

    private func noteSetup(_ step: FirstRunStep) {
        guard firstRun.checked, step.isAutomaticSetup else { return }
        setupKnown = true
        if step == .speechModel { includesDownload = true }
    }

    private func waitForEnd() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            let t = clock.now
            if readyAt == nil && isReady(at: t) { readyAt = t }
            if let readyAt, t >= sequence.end(readyAt: readyAt) {
                done = true
                print(String(format: "[launch] main screen %.2f s after the app started (animation %.2f s, ready at %.2f s, bar %@)",
                             Date().timeIntervalSince(LaunchClock.start), t, readyAt, setupKnown ? "shown" : "not shown"))
                Self.lastFullDance = !reduceMotion
                Self.lastBarShown = setupKnown
                onFinished()
                return
            }
        }
    }

    // MARK: drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let space = DesignSpace(size: size)
        let phase = sequence.phase(at: t, readyAt: readyAt)
        let reduced = sequence.reducedMotion

        var pose: SealPose
        var frame: SealHandoffFrame
        var overlayOpacity = 1.0
        switch phase {
        case .dancing(let progress):
            pose = reduced ? .rest : SealChoreography.pose(at: progress * sequence.danceEnd)
            if reduced { pose.opacity = progress }
            frame = .before(pose: pose)
        case .waiting, .holding:
            pose = .rest
            frame = .before(pose: pose)
        case .readyBeat(let k):
            pose = SealChoreography.readyBeat(.rest, progress: k)
            frame = .before(pose: pose)
        case .handoff(let h):
            if reduced {
                overlayOpacity = 1 - (h / sequence.handoffLength)
                frame = .before(pose: .rest)
            } else {
                frame = .at(h, from: .rest)
            }
            pose = frame.pose
        case .finished:
            return
        }
        context.opacity = overlayOpacity

        // 1. The green, clipped to the iris; the bar sits on it.
        let irisRadius = frame.irisRadius >= SealHandoffFrame.poolRadius
            ? lerp(space.coverRadius, SealHandoffFrame.poolRadius * space.scale, frame.irisClosed)
            : frame.irisRadius * space.scale
        let center = space.point(SealHandoffFrame.center.x, SealHandoffFrame.center.y)
        if irisRadius > 0.5 {
            var green = context
            green.clip(to: Path(ellipseIn: CGRect(x: center.x - irisRadius, y: center.y - irisRadius,
                                                  width: irisRadius * 2, height: irisRadius * 2)))
            var fill = GraphicsContext.Shading.color(launchGreen)
            if let pool = colors.pool, frame.irisClosed > 0 {
                // On a dark theme the pool brightens as it closes, so the splash reads clearly (owner, #104).
                green.fill(Path(CGRect(origin: .zero, size: size)), with: fill)
                green.opacity = frame.irisClosed
                fill = .color(pool.color)
            }
            green.fill(Path(CGRect(origin: .zero, size: size)), with: fill)
            green.opacity = 1
            drawBar(in: &green, space: space, t: t)
        }

        // 2. Splash droplets and plain ripple rings over the screen beneath.
        for ring in frame.rings where ring.opacity > 0 {
            let r = ring.radius * space.scale
            context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                           with: .color(colors.ripple.color.opacity(ring.opacity)), lineWidth: ring.width * space.scale)
        }
        if let sp = frame.splash {
            let fade = frame.splashOpacity
            for d in SealHandoffFrame.drops {
                let p = SealHandoffFrame.dropPosition(d, splash: sp)
                let at = space.point(p.x, p.y), r = d.radius * space.scale
                context.fill(Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)),
                             with: .color(colors.drops.color.opacity(fade)))
            }
        }

        // 3. The seal, always on top (the green closes behind it).
        let sealCenter = space.point(frame.sealX, frame.sealY)
        let scale = frame.sealScale * space.scale
        let pivot = CGPoint(x: sealCenter.x, y: sealCenter.y + SealHandoffFrame.centerAbovePivot * scale)
        if pose.speedLines > 0 {
            drawSpeedLines(in: context, at: CGPoint(x: pivot.x - 150 * space.scale, y: pivot.y - 80 * space.scale),
                           scale: space.scale, opacity: pose.speedLines)
        }
        SealRig.draw(in: context, pose: pose, pivot: pivot, scale: scale)
    }

    private func drawBar(in context: inout GraphicsContext, space: DesignSpace, t: TimeInterval) {
        let opacity = sequence.barOpacity(at: t, readyAt: readyAt, setupKnown: setupKnown)
        guard opacity > 0 else { return }
        let progress: LaunchProgress
        if case .preparing(let step) = engine.state, !firstRun.step.isAutomaticSetup {
            progress = .engine(step: step)  // the engine's real loading steps (#119)
        } else {
            progress = LaunchProgress.at(step: firstRun.step, downloadProgress: firstRun.progress, includesDownload: includesDownload)
        }
        let origin = space.point(111, 640), width = 180 * space.scale, height = 10 * space.scale
        func bar(_ from: Double, _ to: Double) -> Path {
            Path(roundedRect: CGRect(x: origin.x + width * from, y: origin.y, width: width * (to - from), height: height),
                 cornerRadius: height / 2)
        }
        let cream = SealLaunchColors.cream.color
        context.fill(bar(0, 1), with: .color(cream.opacity(0.28 * opacity)))
        if let pulse = progress.pulse {
            let beat = 0.15 + 0.2 * (0.5 + 0.5 * sin(t * 7))
            context.fill(bar(pulse.lowerBound, pulse.upperBound), with: .color(cream.opacity(beat * opacity)))
        }
        if progress.fill > 0 { context.fill(bar(0, progress.fill), with: .color(cream.opacity(opacity))) }
    }

    private func drawSpeedLines(in context: GraphicsContext, at origin: CGPoint, scale: CGFloat, opacity: Double) {
        var c = context
        c.translateBy(x: origin.x, y: origin.y)
        c.scaleBy(x: scale, y: scale)
        var lines = Path()
        lines.move(to: CGPoint(x: 0, y: 0)); lines.addLine(to: CGPoint(x: -70, y: 0))
        lines.move(to: CGPoint(x: -14, y: -34)); lines.addLine(to: CGPoint(x: -64, y: -34))
        lines.move(to: CGPoint(x: -14, y: 34)); lines.addLine(to: CGPoint(x: -54, y: 34))
        c.stroke(lines, with: .color(SealLaunchColors.cream.color.opacity(opacity)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ k: Double) -> CGFloat { a + (b - a) * k }
}

/// The prototype's 402 × 874 design space, centred and scaled to fit the screen (landscape and iPad included).
private struct DesignSpace {
    let size: CGSize
    var scale: CGFloat { min(size.width / SealHandoffFrame.screen.width, size.height / SealHandoffFrame.screen.height) }
    /// A radius that covers the whole screen from its centre.
    var coverRadius: CGFloat { hypot(size.width, size.height) / 2 + 10 }
    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: size.width / 2 + (x - SealHandoffFrame.center.x) * scale,
                y: size.height / 2 + (y - SealHandoffFrame.center.y) * scale)
    }
}

/// The seal mascot, drawn from design/mascot/seal-rig.svg (1024 × 1024 rig units) with its moving parts.
enum SealRig {
    private static let cream = Color(red: 0xFB / 255, green: 0xE8 / 255, blue: 0xC1 / 255)
    private static let peach = Color(red: 0xEF / 255, green: 0xC5 / 255, blue: 0x87 / 255)
    private static let deepTeal = Color(red: 0x0E / 255, green: 0x5A / 255, blue: 0x56 / 255)

    /// `pivot` is the bottom of the body (rig 430, 905) on screen; `scale` maps rig units to points.
    static func draw(in context: GraphicsContext, pose p: SealPose, pivot: CGPoint, scale: CGFloat) {
        guard p.opacity > 0, scale > 0 else { return }
        var c = context
        c.opacity *= p.opacity
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: .degrees(p.rotation))
        c.scaleBy(x: scale * p.scaleX, y: scale * p.scaleY)
        c.translateBy(x: -430, y: -905)

        rotated(c, by: p.backFlipper, around: CGPoint(x: 130, y: 600)) { c in
            c.fill(ellipse(88, 598, 92, 50, -38), with: .color(cream))
            // The tip follows through behind the flipper (#119).
            rotated(c, by: p.backFlipperTip, around: CGPoint(x: 82, y: 562)) { c in
                c.fill(ellipse(60, 535, 38, 30, -20), with: .color(cream))
            }
        }
        c.fill(ellipse(410, 612, 300, 298), with: .color(peach))
        c.fill(ellipse(430, 505, 322, 322), with: .color(cream))
        c.fill(ellipse(705, 402, 36, 31), with: .color(peach))
        c.fill(ellipse(397, 578, 54, 32), with: .color(peach))
        c.fill(ellipse(357, 472, 62, 62), with: .color(deepTeal))
        c.fill(ellipse(362, 440, 17, 17), with: .color(cream))
        c.fill(ellipse(322, 471, 9, 9), with: .color(cream))
        c.fill(ellipse(630, 329, 37, 40), with: .color(deepTeal))
        c.fill(ellipse(621, 309, 11, 11), with: .color(cream))
        c.fill(ellipse(604, 330, 5, 5), with: .color(cream))
        c.fill(ellipse(568, 430, 57, 33, -18), with: .color(deepTeal))
        scaled(c, x: 1, y: p.mouthOpen, around: CGPoint(x: 565, y: 560)) { c in
            var mouth = Path()
            mouth.move(to: CGPoint(x: 487, y: 580))
            mouth.addCurve(to: CGPoint(x: 642, y: 508), control1: CGPoint(x: 540, y: 592), control2: CGPoint(x: 602, y: 560))
            mouth.addLine(to: CGPoint(x: 634, y: 606))
            mouth.addCurve(to: CGPoint(x: 558, y: 656), control1: CGPoint(x: 628, y: 648), control2: CGPoint(x: 590, y: 668))
            mouth.addCurve(to: CGPoint(x: 487, y: 580), control1: CGPoint(x: 528, y: 644), control2: CGPoint(x: 505, y: 614))
            mouth.closeSubpath()
            c.fill(mouth, with: .color(deepTeal))
            c.fill(ellipse(586, 624, 47, 25, -12), with: .color(peach))
        }
        // Whiskers sway behind the body's motion (#119): straight at rest, curved while it moves.
        var whiskers = Path()
        let sway = p.whiskerBend
        for (x1, y1, x2, y2) in [(450.0, 560.0, 318.0, 572.0), (450, 564, 320, 607), (452, 567, 342, 636)] {
            let tip = CGPoint(x: x2, y: y2 + 14 * sway)
            whiskers.move(to: CGPoint(x: x1, y: y1))
            whiskers.addQuadCurve(to: tip, control: CGPoint(x: (x1 + x2) / 2, y: (y1 + y2) / 2 + 22 * sway))
        }
        c.stroke(whiskers, with: .color(deepTeal), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        rotated(c, by: p.frontFlipper, around: CGPoint(x: 600, y: 760)) { c in
            // One flipper in two halves that bend at the middle: the tip follows through behind the wave (#119).
            // At rest the halves line up into exactly the icon's flipper.
            let flipper = ellipse(662, 782, 100, 44, -32)
            let joint = CGPoint(x: 662, y: 782)
            if abs(p.frontFlipperTip) < 0.05 {
                c.fill(flipper, with: .color(cream)) // straight: one shape, no seam even while the seal fades
            } else {
                var base = c
                base.clip(to: halfPlane(through: joint, degrees: -32, keepingTip: false))
                base.fill(flipper, with: .color(cream))
                rotated(c, by: p.frontFlipperTip, around: joint) { c in
                    var tip = c
                    tip.clip(to: halfPlane(through: joint, degrees: -32, keepingTip: true))
                    tip.fill(flipper, with: .color(cream))
                }
            }
            var crease = Path()
            crease.move(to: CGPoint(x: 612, y: 800))
            crease.addQuadCurve(to: CGPoint(x: 712, y: 752), control: CGPoint(x: 660, y: 778))
            c.stroke(crease, with: .color(peach), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        }
        if p.raysOpacity > 0 {
            var r = c
            r.opacity *= p.raysOpacity
            scaled(r, x: p.rays, y: p.rays, around: CGPoint(x: 760, y: 460)) { c in
                var rays = Path()
                for (x1, y1, x2, y2) in [(760.0, 345.0, 870.0, 197.0), (808, 462, 963, 385), (818, 578, 962, 578)] {
                    rays.move(to: CGPoint(x: x1, y: y1)); rays.addLine(to: CGPoint(x: x2, y: y2))
                }
                c.stroke(rays, with: .color(cream), style: StrokeStyle(lineWidth: 34, lineCap: .round))
            }
        }
    }

    /// The side of the line through `p`, across a flipper pointing at `degrees`, that holds the tip (or the base).
    /// The two sides overlap by a couple of units so no hairline shows where the halves meet.
    private static func halfPlane(through p: CGPoint, degrees: Double, keepingTip: Bool) -> Path {
        let overlap = 2.0, far = 2000.0
        var r = Path(CGRect(x: keepingTip ? -overlap : -far, y: -far, width: far + overlap, height: far * 2))
        r = r.applying(CGAffineTransform(rotationAngle: degrees * .pi / 180))
        return r.applying(CGAffineTransform(translationX: p.x, y: p.y))
    }

    /// An ellipse centred at (cx, cy), rotated about its own centre by `degrees`, like SVG's rotate(deg cx cy).
    private static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ degrees: Double = 0) -> Path {
        let base = Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        guard degrees != 0 else { return base }
        let t = CGAffineTransform(translationX: cx, y: cy).rotated(by: degrees * .pi / 180).translatedBy(x: -cx, y: -cy)
        return base.applying(t)
    }

    private static func rotated(_ context: GraphicsContext, by degrees: Double, around p: CGPoint, _ body: (GraphicsContext) -> Void) {
        var c = context
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .degrees(degrees))
        c.translateBy(x: -p.x, y: -p.y)
        body(c)
    }

    private static func scaled(_ context: GraphicsContext, x: Double, y: Double, around p: CGPoint, _ body: (GraphicsContext) -> Void) {
        var c = context
        c.translateBy(x: p.x, y: p.y)
        c.scaleBy(x: x, y: y)
        c.translateBy(x: -p.x, y: -p.y)
        body(c)
    }
}

import Foundation

/// The seal's moves in the launch animation (#104), ported from the approved prototype
/// (design/mascot/launch-prototype.html, round 3, owner's #99 answers): belly slide in → A's clapping → C's wave and
/// bark → settle into the icon's pose; the ready beat; then the hand-off (iris in behind the seal, jump, splash,
/// plain ripple rings). Pure math in the prototype's 402 × 874 design space; the view scales it to the screen.
public struct SealPose: Equatable, Sendable {
    public var dx = 0.0, dy = 0.0, rotation = 0.0, scaleX = 1.0, scaleY = 1.0, opacity = 1.0
    /// Degrees, rig pivots (front flipper at 600,760; back flipper at 130,600).
    public var frontFlipper = 0.0, backFlipper = 0.0
    public var mouthOpen = 1.0
    public var rays = 1.0, raysOpacity = 1.0
    /// The belly slide's speed lines, 0...1.
    public var speedLines = 0.0

    public init() {}

    /// The icon's own pose: where the dance ends and the freeze frame holds.
    public static let rest = SealPose()
}

public enum SealChoreography {
    public static let entrance = 1.1, clap = 1.2, wave = 1.0, settle = 0.45
    public static var danceLength: TimeInterval { entrance + clap + wave + settle }

    /// The dance at `u` seconds in. Past the end it holds the final (icon) pose.
    public static func pose(at u: TimeInterval) -> SealPose {
        typealias M = LaunchMath
        var p = SealPose()
        let u = max(0, u)
        if u < entrance { // C: belly slide in, stop with a bounce
            p.raysOpacity = 0
            if u < 0.85 {
                let k = M.easeOutCubic(u / 0.85)
                p.dx = M.lerp(-460, 0, k); p.rotation = 16; p.speedLines = 1 - M.seg(u, 0.55, 0.85)
                p.scaleY = 0.92; p.scaleX = 1.06; p.backFlipper = -10
            } else {
                let k = M.seg(u, 0.85, 1.1)
                p.rotation = M.lerp(16, 0, M.easeOutCubic(k))
                let q = sin(.pi * k)
                p.scaleX = 1 + 0.1 * q; p.scaleY = 1 - 0.1 * q; p.dy = -20 * q
            }
            return p
        }
        let c = u - entrance
        if c < clap { // A's clapping and wiggle; the bark rays pop in with the first clap
            let w = c / clap, env = sin(.pi * w)
            p.rotation = 9 * env * sin(2 * .pi * 2.5 * w)
            let beat = (sin(2 * .pi * 3 * w - .pi / 2) + 1) / 2
            p.frontFlipper = -55 * beat * env; p.backFlipper = 32 * beat * env
            p.mouthOpen = 0.55 + 0.45 * beat
            p.raysOpacity = 1; p.rays = M.easeOutBack(M.seg(c, 0, 0.25)) * (0.7 + 0.45 * beat)
            return p
        }
        let v = c - clap
        if v < wave { // C's wave and bark
            let w = v / wave
            p.frontFlipper = -62 + 26 * sin(2 * .pi * 2 * w) * min(1, w * 6)
            p.mouthOpen = 0.6 + 0.4 * abs(sin(2 * .pi * 2 * w))
            p.rays = 0.85 + 0.25 * abs(sin(2 * .pi * 2 * w))
            return p
        }
        let k = M.easeInOutSine(M.clamp((v - wave) / settle)) // settle into the icon's pose
        p.frontFlipper = M.lerp(-62, 0, k)
        return p
    }

    /// The ready beat on top of a pose: a happy nod with a little hop, a flipper flick and a ray flash. k runs 0...1.
    public static func readyBeat(_ pose: SealPose, progress k: Double) -> SealPose {
        typealias M = LaunchMath
        var p = pose
        let k = M.clamp(k)
        p.rotation += 10 * sin(.pi * 2 * k) * (1 - k)
        p.dy -= 26 * sin(.pi * M.clamp(k / 0.6))
        let squash = sin(.pi * M.seg(k, 0.6, 1))
        p.scaleX *= 1 + 0.08 * squash; p.scaleY *= 1 - 0.08 * squash
        p.frontFlipper += -30 * sin(.pi * k)
        p.rays *= 1 + 0.35 * sin(.pi * k)
        p.mouthOpen = max(p.mouthOpen, 0.7 + 0.3 * sin(.pi * k))
        return p
    }
}

/// One frame of the hand-off, in the 402 × 874 design space. The green closes in to a small pool at the centre,
/// behind the seal; the seal crouches, jumps in an arc and dives into the pool; droplets splash; plain rings ripple
/// out over the main screen.
public struct SealHandoffFrame: Equatable, Sendable {
    public static let screen = (width: 402.0, height: 874.0)
    public static let center = (x: 201.0, y: 437.0)
    /// Where the seal stands (the bottom of its body) and how big it is, before the hand-off.
    public static let sealHome = (x: 201.0, y: 560.0)
    public static let sealScale = 0.3
    /// From the rig's pivot (bottom of the body) up to its visual centre, in rig units.
    public static let centerAbovePivot = 360.0
    public static let poolRadius = 62.0
    public static let coverRadius = hypot(402.0, 874.0) / 2 + 10
    public static let ringDelays = [0.0, 0.12, 0.24]

    public var irisRadius: Double
    /// 0 before the iris starts closing, 1 once it's a pool: drives the pool's brightening on dark themes.
    public var irisClosed: Double
    public var pose: SealPose
    /// The seal's visual centre and scale.
    public var sealX: Double, sealY: Double, sealScale: Double
    /// nil when no splash is showing; otherwise 0...1 through it.
    public var splash: Double?
    /// Per ring: radius, stroke width and opacity.
    public var rings: [(radius: Double, width: Double, opacity: Double)]

    public static func == (a: Self, b: Self) -> Bool {
        a.irisRadius == b.irisRadius && a.pose == b.pose && a.sealX == b.sealX && a.sealY == b.sealY
            && a.sealScale == b.sealScale && a.splash == b.splash && a.rings.map(\.radius) == b.rings.map(\.radius)
    }

    /// Before the hand-off: the seal at home with the green covering the screen.
    public static func before(pose: SealPose) -> SealHandoffFrame {
        SealHandoffFrame(irisRadius: coverRadius, irisClosed: 0, pose: pose,
                         sealX: sealHome.x + pose.dx, sealY: sealHome.y + pose.dy - centerAbovePivot * sealScale,
                         sealScale: sealScale, splash: nil, rings: [])
    }

    /// `h` seconds into the hand-off, starting from the frozen pose.
    public static func at(_ h: TimeInterval, from frozen: SealPose) -> SealHandoffFrame {
        typealias M = LaunchMath
        var f = before(pose: frozen)
        var p = frozen
        f.irisClosed = M.easeInOutCubic(M.seg(h, 0, 0.5))
        f.irisRadius = M.lerp(coverRadius, poolRadius, f.irisClosed)
        let crouch = sin(.pi * M.seg(h, 0.2, 0.42))
        p.scaleX *= 1 + 0.12 * crouch; p.scaleY *= 1 - 0.16 * crouch
        let j = M.seg(h, 0.42, 0.9)
        if j > 0 {
            let startX = f.sealX, startY = f.sealY
            f.sealX = M.lerp(startX, center.x, M.easeInOutSine(j))
            f.sealY = M.lerp(startY, center.y, j) - 170 * sin(.pi * j)
            p.rotation += M.lerp(0, 35, M.easeInCubic(j))
            p.scaleX = M.lerp(p.scaleX, 0.92, j); p.scaleY = M.lerp(p.scaleY, 1.1, j)
            f.sealScale *= 1 - 0.95 * M.easeInCubic(M.seg(h, 0.72, 0.92))
            p.opacity = 1 - M.seg(h, 0.86, 0.93)
        }
        let sp = M.seg(h, 0.88, 1.35)
        f.splash = sp > 0 && sp < 1 ? sp : nil
        if h > 0.9 { f.irisRadius = poolRadius * (1 - M.easeInCubic(M.seg(h, 0.9, 1.15))) }
        f.rings = ringDelays.map { delay in
            let k = M.seg(h, 0.9 + delay, 0.9 + delay + 0.72)
            return (radius: 12 + 300 * M.easeOutCubic(k), width: 4 - 2.5 * k, opacity: k > 0 && k < 1 ? (1 - k) * 0.85 : 0)
        }
        f.pose = p
        return f
    }

    /// Droplets thrown out of the pool: angle, speed and size, matching the prototype.
    public static let drops: [(angle: Double, speed: Double, radius: Double)] = (0..<9).map { i in
        let n = Double(i)
        let angle: Double = -Double.pi / 2 + (n - 4) * 0.33
        let speed: Double = 150 + 55 * Double((i * 7) % 3)
        let radius: Double = 4 + Double(i % 3) * 1.5
        return (angle: angle, speed: speed, radius: radius)
    }

    public static func dropPosition(_ d: (angle: Double, speed: Double, radius: Double), splash sp: Double) -> (x: Double, y: Double) {
        (center.x + cos(d.angle) * d.speed * sp, center.y + sin(d.angle) * d.speed * sp + 260 * sp * sp)
    }
}

enum LaunchMath {
    static func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, x)) }
    static func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }
    static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
    static func easeOutCubic(_ k: Double) -> Double { 1 - pow(1 - k, 3) }
    static func easeInCubic(_ k: Double) -> Double { k * k * k }
    static func easeInOutSine(_ k: Double) -> Double { -(cos(.pi * k) - 1) / 2 }
    static func easeInOutCubic(_ k: Double) -> Double { k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2 }
    static func easeOutBack(_ k: Double) -> Double { let c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * pow(k - 1, 3) + c1 * pow(k - 1, 2) }
}

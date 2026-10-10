import Foundation

/// When each part of the launch animation happens (#104, approved in #99; spec §8). Pure timing, so the rules are
/// tested without drawing anything:
/// - The dance always finishes, however fast the app gets ready.
/// - After the dance and once the app is ready: a short ready beat, then a 0.75 s hold, then the hand-off.
/// - The progress bar shows only when real work outlasts the animation: from the start when setup is known
///   (first launch, after an update), or from the end of the dance if the app still isn't ready then.
public struct LaunchSequence: Equatable, Sendable {
    public static let readyBeat: TimeInterval = 0.55
    public static let hold: TimeInterval = 0.75
    public static let handoff: TimeInterval = 1.9
    /// Reduce Motion: the seal fades in already in its pose, and the screens cross-fade.
    public static let reducedIntro: TimeInterval = 0.3
    public static let reducedHandoff: TimeInterval = 0.6
    public static let barFadeIn: TimeInterval = 0.25
    public static let barFadeOut: TimeInterval = 0.2

    public let reducedMotion: Bool

    public init(reducedMotion: Bool) { self.reducedMotion = reducedMotion }

    public var danceEnd: TimeInterval { reducedMotion ? Self.reducedIntro : SealChoreography.danceLength }
    public var beatLength: TimeInterval { reducedMotion ? 0 : Self.readyBeat }
    public var handoffLength: TimeInterval { reducedMotion ? Self.reducedHandoff : Self.handoff }

    public func beatStart(readyAt: TimeInterval) -> TimeInterval { max(danceEnd, readyAt) }
    public func handoffStart(readyAt: TimeInterval) -> TimeInterval { beatStart(readyAt: readyAt) + beatLength + Self.hold }
    public func end(readyAt: TimeInterval) -> TimeInterval { handoffStart(readyAt: readyAt) + handoffLength }

    public enum Phase: Equatable, Sendable {
        /// `progress` runs 0...1 through the dance.
        case dancing(progress: Double)
        /// The dance is over and the app isn't ready yet: the seal holds its pose.
        case waiting
        case readyBeat(progress: Double)
        case holding
        /// Seconds into the hand-off.
        case handoff(seconds: TimeInterval)
        case finished
    }

    /// `readyAt` is when the app became ready, in seconds since the animation started; nil while it isn't.
    public func phase(at t: TimeInterval, readyAt: TimeInterval?) -> Phase {
        if t < danceEnd { return .dancing(progress: max(0, t) / danceEnd) }
        guard let readyAt else { return .waiting }
        let beat = beatStart(readyAt: readyAt)
        if t < beat { return .waiting }
        if t < beat + beatLength { return .readyBeat(progress: (t - beat) / beatLength) }
        let handoff = handoffStart(readyAt: readyAt)
        if t < handoff { return .holding }
        if t < handoff + handoffLength { return .handoff(seconds: t - handoff) }
        return .finished
    }

    /// 0...1. `setupKnown` is true when this launch is doing real setup (a download or a warm-up).
    public func barOpacity(at t: TimeInterval, readyAt: TimeInterval?, setupKnown: Bool) -> Double {
        let shown: Double
        if setupKnown {
            shown = LaunchMath.clamp(t / Self.barFadeIn)
        } else if readyAt.map({ $0 > danceEnd }) ?? true {
            shown = t < danceEnd ? 0 : LaunchMath.clamp((t - danceEnd) / Self.barFadeIn)
        } else {
            shown = 0
        }
        guard let readyAt else { return shown }
        return shown * (1 - LaunchMath.clamp((t - handoffStart(readyAt: readyAt)) / Self.barFadeOut))
    }
}

/// How full the bar is, from the real first-run steps. A download reports a real percentage; the warm-up has none, so
/// its part of the bar pulses until it finishes instead of pretending to move.
public struct LaunchProgress: Equatable, Sendable {
    public let fill: Double
    /// The stretch of the bar a step without a percentage is working through, or nil.
    public let pulse: ClosedRange<Double>?

    public static let downloadShare = 0.75

    public static func at(step: FirstRunStep, downloadProgress: Double, includesDownload: Bool) -> LaunchProgress {
        switch step {
        case .speechModel:
            return LaunchProgress(fill: downloadShare * LaunchMath.clamp(downloadProgress), pulse: nil)
        case .speakerModel:
            let from = includesDownload ? downloadShare : 0
            return LaunchProgress(fill: from, pulse: from...1)
        default:
            return LaunchProgress(fill: 1, pulse: nil)
        }
    }
}

public extension FirstRunStep {
    /// The steps that run by themselves behind the launch animation (a download, a warm-up).
    var isAutomaticSetup: Bool { self == .speechModel || self == .speakerModel }
}

/// The launch animation's colours on the chosen theme (#104): as prototyped and approved in #99 ("the color is fine"),
/// with the pool brightened on the dark themes so the splash reads clearly (owner, 2026-10-09).
public struct SealLaunchColors: Equatable, Sendable {
    /// The icon's teal: the launch green in light appearance, and the brightened pool on dark themes.
    public static let brightTeal = RGBA(hex: "#1F998B")
    public static let cream = RGBA(hex: "#FBE8C1")
    public static let lightTeal = RGBA(hex: "#7FD1C9")

    public let ripple: RGBA
    public let drops: RGBA
    /// What the pool turns into as the green closes; nil keeps the launch green.
    public let pool: RGBA?

    public init(theme: CaptionStyle) {
        let dark = theme.background.isDark
        ripple = dark ? Self.lightTeal : Self.brightTeal
        drops = dark ? Self.cream : Self.brightTeal
        pool = dark ? Self.brightTeal : nil
    }
}

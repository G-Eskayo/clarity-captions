import Foundation

/// Controls the duration of the brand animation moment (first-run wait or cold startup).
/// Ends when real setup is ready AND minimum duration has elapsed.
public struct BrandAnimationGate: Equatable, Sendable {
    public let minimumDuration: TimeInterval
    public init(minimumDuration: TimeInterval = 0.4) { self.minimumDuration = minimumDuration }

    /// True when setup is complete and minimum duration has passed. False if not ready, or if elapsed time is less than minimum.
    public func isFinished(ready: Bool, elapsed: TimeInterval) -> Bool {
        ready && elapsed >= minimumDuration
    }

    /// Time remaining (in seconds) before the animation is allowed to end. Negative means finished.
    public func remainingDelay(elapsed: TimeInterval) -> TimeInterval {
        max(0, minimumDuration - elapsed)
    }
}

/// How the brand animation should be presented: animated smoothly or statically (for accessibility).
public enum BrandAnimationPresentation: Equatable, Sendable {
    case animated
    case calmStatic

    /// Returns the appropriate presentation based on the system's motion preference.
    public static func `for`(reduceMotion: Bool) -> BrandAnimationPresentation {
        reduceMotion ? .calmStatic : .animated
    }
}

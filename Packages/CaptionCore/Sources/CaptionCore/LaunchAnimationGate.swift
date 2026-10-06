import Foundation

public enum LaunchAnimationGate {
    /// Once the animation is showing, it stays at least this long so it never flickers.
    public static let minimumDuration: TimeInterval = 0.5
    /// Getting ready must take at least this long before the animation appears at all. A warm start takes a
    /// fraction of a second, and covering the screen for that looks like a flash; the button morphing is enough.
    public static let showDelay: TimeInterval = 0.6

    /// How much longer to wait before showing the animation, given how long getting ready has taken so far.
    /// Returns 0 once it is genuinely slow.
    public static func delayBeforeShowing(elapsedPreparing: TimeInterval, showDelay: TimeInterval = showDelay) -> TimeInterval {
        max(0, showDelay - elapsedPreparing)
    }

    /// Calculates how much longer the animation should play, given elapsed time and a minimum duration floor.
    /// Returns 0 if the minimum has already elapsed.
    public static func remainingDelay(elapsed: TimeInterval, minimumDuration: TimeInterval = minimumDuration) -> TimeInterval {
        max(0, minimumDuration - elapsed)
    }
}

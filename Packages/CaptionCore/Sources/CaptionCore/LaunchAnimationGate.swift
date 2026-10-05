import Foundation

public enum LaunchAnimationGate {
    public static let minimumDuration: TimeInterval = 0.5

    /// Calculates how much longer the animation should play, given elapsed time and a minimum duration floor.
    /// Returns 0 if the minimum has already elapsed.
    public static func remainingDelay(elapsed: TimeInterval, minimumDuration: TimeInterval = minimumDuration) -> TimeInterval {
        max(0, minimumDuration - elapsed)
    }
}

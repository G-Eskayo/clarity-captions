import Foundation

/// Tracks background/foreground transitions to detect real background returns (not transient Control Center or similar).
public struct BackgroundReturnTracker {
    private var wasInBackground = false

    /// Call when app enters background.
    public mutating func appDidEnterBackground() {
        wasInBackground = true
    }

    /// Call when app becomes active. Returns true only once per real background excursion.
    public mutating func appDidBecomeActive() -> Bool {
        guard wasInBackground else { return false }
        wasInBackground = false
        return true
    }
}

import Foundation

/// Tracks whether the app has returned from background, distinguishing real background excursions
/// (app -> background -> active) from transient interruptions (active -> inactive -> active via alerts/Control Center).
public struct BackgroundReturnTracker: Sendable {
    private(set) var inBackground = false

    public init() {}

    /// Called when the app enters background.
    public mutating func appDidEnterBackground() {
        inBackground = true
    }

    /// Called when the app becomes active.
    /// Returns true if and only if the app previously entered background, marking a real excursion.
    /// On the first call after becoming active, returns true once and resets, so subsequent
    /// calls without an intervening background transition return false.
    public mutating func appDidBecomeActive() -> Bool {
        guard inBackground else { return false }
        inBackground = false
        return true
    }
}

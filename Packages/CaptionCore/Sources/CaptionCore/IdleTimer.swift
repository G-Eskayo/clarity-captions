import Foundation

public enum IdleTimer {
    /// Returns true if the system idle timer should be disabled for this state.
    /// The timer is disabled while actively captioning (preparing/listening/paused)
    /// and enabled during idle or failed states.
    public static func shouldDisable(for state: CaptionState) -> Bool {
        switch state {
        case .preparing, .listening, .paused:
            return true
        case .idle, .failed:
            return false
        }
    }
}

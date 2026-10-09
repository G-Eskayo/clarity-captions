import Foundation

/// Determines whether the screen should stay awake for a given caption state.
/// Pure logic; the actual UIApplication side-effect lives in the app layer.
public enum ScreenWakePolicy {
    public static func shouldStayAwake(for state: CaptionState) -> Bool {
        switch state {
        case .listening, .paused:
            return true
        case .idle, .preparing, .failed:
            return false
        }
    }
}

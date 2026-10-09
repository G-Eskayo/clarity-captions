import Foundation

/// Maps CaptionState to a menu bar icon, decoupling icon choice from the state logic itself.
public enum MenuBarPresentation: Equatable, Sendable {
    public static func symbolName(for state: CaptionState) -> String {
        switch state {
        case .idle:
            return "mic"
        case .preparing:
            return "waveform.circle"
        case .listening:
            return "mic.fill"
        case .failed:
            return "mic.slash"
        }
    }
}

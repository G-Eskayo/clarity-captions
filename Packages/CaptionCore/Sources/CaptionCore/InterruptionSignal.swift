import Foundation

/// Signals that something has interrupted the audio session or resumed it.
public enum InterruptionSignal: Equatable, Sendable {
    case paused(String)
    case resumed
}

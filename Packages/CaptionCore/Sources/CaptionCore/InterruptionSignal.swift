import Foundation

/// Signals that something has interrupted the audio session or resumed it.
/// The reason text is honestly generic—the system API does not expose why (call vs. Siri vs. another app),
/// only that something else has the microphone.
public enum InterruptionSignal: Equatable, Sendable {
    case paused(String)
    case resumed
}

import Foundation

/// Visual indicator of app state and listening activity.
public enum StatusDot: Equatable, Sendable {
    case pulsing(level: Double)
    case flatAmber
    case hidden

    /// Selects the dot style from state and activity.
    /// While listening (both speech and silence), dot pulses with room level.
    /// During can't-hear, dot is flat amber. Otherwise hidden.
    public static func select(state: CaptionState, activity: ListeningActivity?, roomLevelDBFS: Double?) -> StatusDot {
        guard case .listening = state else { return .hidden }
        guard let activity else { return .hidden }

        switch activity {
        case .activelyListening, .noOneTalking:
            let level = roomLevelDBFS ?? -60.0
            return .pulsing(level: level)
        case .cantHearAnything:
            return .flatAmber
        }
    }
}

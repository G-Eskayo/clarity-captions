import Foundation

/// What's happening while listening is active, for state-machine wording.
public enum ListeningActivity: Equatable, Sendable {
    case activelyListening
    case noOneTalking
    case cantHearAnything
}

/// Classifies listening activity from speech recency and room audio level.
public enum ListeningActivityClassifier {
    private static let speechSilenceThresholdSeconds = 10.0
    private static let silenceFloorDBFS = -60.0

    /// Classifies activity given how long since the last speech and current room level.
    /// - Parameters:
    ///   - secondsSinceSpeech: Seconds elapsed since the last non-empty caption. Zero = speech now.
    ///   - roomLevelDBFS: RMS dBFS of the current audio, or nil if unavailable.
    public static func classify(secondsSinceSpeech: Double, roomLevelDBFS: Double?) -> ListeningActivity {
        if secondsSinceSpeech < speechSilenceThresholdSeconds {
            return .activelyListening
        }
        guard let level = roomLevelDBFS else {
            return .noOneTalking
        }
        if level <= silenceFloorDBFS {
            return .cantHearAnything
        }
        return .noOneTalking
    }
}

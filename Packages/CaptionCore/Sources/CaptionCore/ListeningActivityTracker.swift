import Foundation

/// Tracks when speech last occurred to compute listening activity state.
public struct ListeningActivityTracker {
    private var lastSpeechAt: Date?

    public init() {}

    /// Records that speech occurred at the given time.
    public mutating func recordSpeech(at date: Date) {
        lastSpeechAt = date
    }

    /// Computes current listening activity given elapsed time and room audio level.
    /// - Parameters:
    ///   - now: Current time for computing seconds elapsed.
    ///   - roomLevelDBFS: RMS dBFS of the current audio, or nil if unavailable.
    public func activity(now: Date, roomLevelDBFS: Double?) -> ListeningActivity {
        guard let lastSpeech = lastSpeechAt else {
            let secondsSinceSpeech = Double.infinity
            return ListeningActivityClassifier.classify(secondsSinceSpeech: secondsSinceSpeech, roomLevelDBFS: roomLevelDBFS)
        }
        let secondsSinceSpeech = now.timeIntervalSince(lastSpeech)
        return ListeningActivityClassifier.classify(secondsSinceSpeech: secondsSinceSpeech, roomLevelDBFS: roomLevelDBFS)
    }
}

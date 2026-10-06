import Foundation

/// Measures wall-clock latency: time from when audio ends (per the recognizer's audio timestamp) to when
/// that end-time appears in a result, as observed by wall-clock time at the moment the result arrives.
/// Given elapsed wall-clock seconds and the audio-end times from the latest transcription result,
/// returns the lag for the *most recently newly seen* word end, or nil if nothing new appeared.
/// No flooring — a negative result indicates wall-clock / audio-clock disagreement.
struct WordLagTracker: Sendable {
    private var lastSampledEnd: Double?

    /// Given the wall-clock seconds elapsed since the clock started ticking, and the set of audio-end
    /// times visible in the latest result, samples the lag for the maximum newly *seen* end time.
    /// Returns nil if: no ends are present, or the maximum end time was already sampled before.
    /// The returned lag is (elapsed wall time) - (audio end time).
    mutating func sample(elapsed: Double, audioEnds: [Double]) -> Double? {
        guard let maxEnd = audioEnds.max() else { return nil }

        // Avoid re-counting the same word as it gets refined by volatile results.
        if let last = lastSampledEnd, maxEnd <= last {
            return nil
        }

        lastSampledEnd = maxEnd
        return elapsed - maxEnd
    }

    /// Reset the tracker for a new measurement session.
    mutating func reset() {
        lastSampledEnd = nil
    }
}

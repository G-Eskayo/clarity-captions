import Foundation

struct LoudnessWordTracker: Sendable {
    private var measurements: [Double: Double] = [:]
    private var lastSeenUpTo: Double = -1

    /// Records average loudness for each word audio-time span.
    /// Given the audio-time range of a word and its loudness in dBFS, stores it for later retrieval.
    mutating func feed(span: ClosedRange<Double>, loudness: Double) {
        let key = span.lowerBound
        measurements[key] = loudness
    }

    /// Retrieves average loudness for a word's audio-time span, or nil if never seen.
    /// To avoid re-measuring the same word across volatile results, this method tracks the
    /// maximum audio time it has already computed emphasis for. Once a span is seen, asking
    /// for an earlier or equal time will be refused.
    mutating func measurement(for span: ClosedRange<Double>) -> Double? {
        let start = span.lowerBound
        guard start > lastSeenUpTo else { return nil }
        lastSeenUpTo = start
        return measurements[start]
    }

    mutating func reset() {
        measurements.removeAll()
        lastSeenUpTo = -1
    }
}

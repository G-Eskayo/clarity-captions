import Foundation

/// Audio loudness in dBFS, computed from a block of samples.
public enum AudioLevel {
    /// Compute RMS → dBFS for the given samples, or -60 (silence floor) for empty input.
    public static func dBFS(samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -60.0 }
        let meanSquare = samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count)
        guard meanSquare > 0 else { return -60.0 }
        return 20.0 * log10(sqrt(meanSquare))
    }
}

/// Append-only timeline of loudness measurements, time-pruned to keep ~60 seconds.
public struct LoudnessTimeline: Sendable {
    private let maxWindow: Double = 60.0
    private var measurements: [(timeRange: ClosedRange<Double>, dBFS: Double)] = []

    public mutating func append(timeRange: ClosedRange<Double>, dBFS: Double) {
        measurements.append((timeRange, dBFS))
        prune()
    }

    /// Average loudness over the given time range, or nil if no measurements overlap.
    public func averageLevel(in timeRange: ClosedRange<Double>) -> Double? {
        let overlapping = measurements.filter { $0.timeRange.lowerBound < timeRange.upperBound && $0.timeRange.upperBound > timeRange.lowerBound }
        guard !overlapping.isEmpty else { return nil }
        return overlapping.map(\.dBFS).reduce(0, +) / Double(overlapping.count)
    }

    /// Remove measurements older than 60 seconds from the newest.
    private mutating func prune() {
        guard let newest = measurements.last?.timeRange.upperBound else { return }
        measurements.removeAll { $0.timeRange.upperBound < newest - maxWindow }
    }
}

/// Slow EMA (exponential moving average) of per-word loudness levels, representing a speaker's baseline.
/// Seeded on first sample; requires minimum samples before trusted.
public struct LoudnessBaseline: Sendable {
    private let alpha: Double = 0.3
    private let minSamplesBeforeTrusted: Int = 3
    private var value: Double?
    private var sampleCount: Int = 0

    public mutating func feed(_ level: Double) {
        sampleCount += 1
        if value == nil {
            value = level
        } else if let current = value {
            value = alpha * level + (1.0 - alpha) * current
        }
    }

    public var isTrusted: Bool { sampleCount >= minSamplesBeforeTrusted }
    public var current: Double? { value }
}

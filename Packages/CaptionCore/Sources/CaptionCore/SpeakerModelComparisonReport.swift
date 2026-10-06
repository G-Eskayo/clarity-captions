import Foundation

/// Aggregated metrics from comparing speaker-diarization models on a synthetic test.
public struct SpeakerModelComparisonReport: Sendable {
    /// Model name (e.g., "Sortformer", "LS-EEND/dihard3").
    public let modelName: String
    /// Number of distinct speakers detected by this model on the test audio.
    public let speakersFound: Int
    /// Diarization Error Rate (DER), in [0, 1], computed as frame-wise error vs. ground truth.
    /// Lower is better; 0 means perfect agreement, 1 means worst-case error.
    public let der: Double
    /// Wall-clock time from audio start to the first speaker label, in seconds.
    public let timeToFirstLabelSeconds: Double?

    public init(modelName: String, speakersFound: Int, der: Double, timeToFirstLabel: Double? = nil) {
        self.modelName = modelName
        self.speakersFound = speakersFound
        self.der = der
        self.timeToFirstLabelSeconds = timeToFirstLabel
    }

    /// Human-readable summary line, suitable for logging or test output.
    public func summaryLine() -> String {
        let paddedName = modelName.padding(toLength: 30, withPad: " ", startingAt: 0)
        let timeLabel = timeToFirstLabelSeconds.map { String(format: "%.3f s", $0) } ?? "N/A"
        return String(
            format: "%@ speakers: %d, DER: %.3f, time-to-label: %@",
            paddedName,
            speakersFound,
            der,
            timeLabel
        )
    }
}

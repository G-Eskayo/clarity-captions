import Foundation

/// Marks a gap or transition in the transcript (backgrounding, missed a segment during interruption).
public enum TranscriptMarker: Equatable, Sendable {
    case wasAway
    case resumedAfterInterruption
}

/// Formats transcript markers for display in captions.
public enum TranscriptMarkerFormatter {
    public static func caption(for marker: TranscriptMarker) -> String {
        switch marker {
        case .wasAway:
            return String(localized: "— while you were away —")
        case .resumedAfterInterruption:
            return String(localized: "— missed a bit during your call —")
        }
    }
}

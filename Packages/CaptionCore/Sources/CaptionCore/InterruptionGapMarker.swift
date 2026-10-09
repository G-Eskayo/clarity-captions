import Foundation

/// Marker inserted into the transcript when resuming after an interruption (ADR 0021).
public enum InterruptionGapMarker {
    public static let text = String(localized: "— captions paused —")
}

import Foundation

/// Marker inserted into the transcript when returning from background while captioning (ADR 0020).
public enum BackgroundMarker {
    public static let text = String(localized: "— while you were away —")
}

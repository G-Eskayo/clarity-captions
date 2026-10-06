import Foundation
import SoundAnalysis

/// One of the five ambient sounds recognized in captions. Domain vocabulary, not Apple's raw classifier strings.
public enum SoundLabelKind: Equatable, Sendable {
    case laughter
    case applause
    case doorbell
    case phoneRinging
    case knock

    /// Maps SoundAnalysis's SNClassifierIdentifier.version1 taxonomy strings to our domain enum.
    /// Unknown identifiers return nil (sound is ignored).
    public init?(classifierIdentifier: String) {
        switch classifierIdentifier {
        case "laughter": self = .laughter
        case "applause": self = .applause
        case "doorbell": self = .doorbell
        case "telephone_bell_ringing": self = .phoneRinging
        case "knock": self = .knock
        default: return nil
        }
    }

    /// Display text for the user: "Laughter", "Applause", etc. (for broadcast-caption-style brackets).
    public var displayText: String {
        switch self {
        case .laughter: String(localized: "Laughter")
        case .applause: String(localized: "Applause")
        case .doorbell: String(localized: "Doorbell")
        case .phoneRinging: String(localized: "Phone ringing")
        case .knock: String(localized: "Knocking")
        }
    }
}

/// Formats sound labels for broadcast captions: `"[Laughter]"` (shared by UI and tests).
public enum SoundLabelFormatter {
    public static func caption(for label: SoundLabelKind) -> String {
        "[\(label.displayText)]"
    }
}

/// Applies the confidence threshold and debounce rule to sound-classification events,
/// producing only the sounds that should be shown to the user.
public struct SoundLabelDetector {
    /// Minimum confidence (0.0–1.0) to emit a sound label. Conservative default keeps false positives rare.
    let threshold: Double
    /// Debounce window: sounds identical to the last one within this duration are suppressed.
    let debounceSeconds: Double
    /// Last emitted label (kind + emission time).
    private(set) var lastEmitted: (kind: SoundLabelKind, time: Double)?

    public init(threshold: Double = 0.65, debounceSeconds: Double = 3.0) {
        self.threshold = threshold
        self.debounceSeconds = debounceSeconds
    }

    /// Consumes a classifier identifier and confidence value (at a given audio time).
    /// Returns a `SoundLabelKind` if the sound should be emitted (passes threshold and debounce),
    /// or nil if it should be suppressed. Updates `lastEmitted` on emission.
    mutating func label(identifier: String, confidence: Double, at audioTime: Double) -> SoundLabelKind? {
        guard confidence >= threshold else { return nil }
        guard let kind = SoundLabelKind(classifierIdentifier: identifier) else { return nil }

        if let (lastKind, lastTime) = lastEmitted {
            if kind == lastKind && audioTime - lastTime < debounceSeconds {
                return nil
            }
        }

        lastEmitted = (kind, audioTime)
        return kind
    }
}

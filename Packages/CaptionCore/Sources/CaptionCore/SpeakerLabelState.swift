import Foundation

/// The label state for a caption line, purely derived from the line's own fields.
public enum SpeakerLabelState: Equatable, Sendable {
    /// No speaker label row for sound labels.
    case none
    /// Speaker label row pending: text is still being revised, awaiting speaker attribution.
    case pending
    /// Speaker label row resolved to a speaker index.
    case resolved(Int)
    /// Speaker label row resolved to unknown: the line is final but was never attributed.
    case unknown
}

public enum SpeakerLabeling {
    /// Derive the speaker label state purely from a line's own fields.
    public static func state(for line: CaptionLine) -> SpeakerLabelState {
        if line.isSoundLabel { return .none }
        if let s = line.speaker { return .resolved(s) }
        return line.isFinal ? .unknown : .pending
    }
}

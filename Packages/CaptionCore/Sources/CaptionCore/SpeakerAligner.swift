import Foundation

/// One stretch of audio attributed to one speaker slot. Slot numbers are only
/// meaningful within a session (CONTEXT.md: "Speaker labels are not guaranteed stable
/// across separate sessions").
public struct SpeakerSegment: Equatable, Sendable {
    public let speaker: Int
    public let start: Double
    public let end: Double
    public init(speaker: Int, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

/// Decides which speaker a caption belongs to, by overlap between the caption's audio
/// time range and the diarizer's segments. Pure logic -- no FluidAudio, no audio.
public enum SpeakerAligner {
    public static func speaker(start: Double, end: Double, segments: [SpeakerSegment]) -> Int? {
        var overlap: [Int: Double] = [:]
        for s in segments {
            let o = min(end, s.end) - max(start, s.start)
            if o > 0 { overlap[s.speaker, default: 0] += o }
        }
        if let best = overlap.max(by: { $0.value < $1.value }) { return best.key }
        // A zero-length caption range has no overlap; fall back to the segment containing it.
        if end <= start { return segments.last(where: { $0.start <= start && start < $0.end })?.speaker }
        return nil
    }
}

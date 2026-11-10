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
/// Tie-breaking (when speakers have equal overlap) is deterministic: current speaker, then lowest
/// display number (for consistent numbering across face-to-face), then lowest slot index (#275).
public enum SpeakerAligner {
    /// Returns the speaker slot with the greatest overlap, breaking ties deterministically.
    /// Prefers `current` if it's tied for max, then the lowest-numbered display slot (from `numbering`),
    /// then the lowest slot index.
    public static func bestSlot(_ overlap: [Int: Double], current: Int? = nil, numbering: [Int: Int] = [:]) -> Int? {
        guard let maxValue = overlap.values.max() else { return nil }
        let tied = overlap.filter { $0.value == maxValue }.keys

        if let current = current, tied.contains(current) {
            return current
        }

        let withNumbers = tied.compactMap { key -> (key: Int, displayNumber: Int)? in
            guard let displayNumber = numbering[key] else { return nil }
            return (key, displayNumber)
        }

        if let lowestByNumber = withNumbers.min(by: { $0.displayNumber < $1.displayNumber }) {
            return lowestByNumber.key
        }

        return tied.min()
    }

    public static func speaker(start: Double, end: Double, segments: [SpeakerSegment]) -> Int? {
        var overlap: [Int: Double] = [:]
        for s in segments {
            let o = min(end, s.end) - max(start, s.start)
            if o > 0 { overlap[s.speaker, default: 0] += o }
        }
        if let best = bestSlot(overlap) { return best }
        // A zero-length caption range has no overlap; fall back to the segment containing it.
        if end <= start { return segments.last(where: { $0.start <= start && start < $0.end })?.speaker }
        return nil
    }
}

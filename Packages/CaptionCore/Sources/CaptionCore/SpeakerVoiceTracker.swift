import Foundation

/// Tracks each speaker's voice characteristics (pitch and pace) from audio samples and finished captions.
/// Holds one `SpeakerProfile` per diarizer slot, capped to avoid memory growth in long sessions.
struct SpeakerVoiceTracker: Sendable {
    private var profilesBySlot: [Int: SpeakerProfile] = [:]
    private static let maximumSlots = 16

    /// Feed audio samples: attributes them to the diarizer segment with dominant overlap in this time range.
    /// Does nothing if no segments cover this range.
    mutating func feed(samples: [Float], sampleRate: Double, at: Double, segments: [SpeakerSegment]) {
        guard !samples.isEmpty, sampleRate >= 4000 else { return }
        guard let slot = overlappingSlot(at: at, duration: Double(samples.count) / sampleRate, segments: segments) else { return }
        profilesBySlot[slot, default: SpeakerProfile()].add(samples, sampleRate: sampleRate)
    }

    /// Record a finished caption line: forward it to the profile of the slot that spoke it.
    mutating func addLine(_ text: String, speechSeconds: Double, language: String?, forSlot slot: Int) {
        profilesBySlot[slot, default: SpeakerProfile()].addLine(text, speechSeconds: speechSeconds, language: language)
    }

    /// Get the voice traits for a diarizer slot, or nil if not enough speech yet.
    func traits(forSlot slot: Int) -> SpeakerTraits? {
        profilesBySlot[slot]?.traits
    }

    /// Determine which diarizer slot has the most overlap with the time range [at, at + duration).
    private func overlappingSlot(at: Double, duration: Double, segments: [SpeakerSegment]) -> Int? {
        let range = at..<(at + duration)
        var overlap: [Int: Double] = [:]
        for segment in segments {
            let segStart = max(at, segment.start)
            let segEnd = min(range.upperBound, segment.end)
            if segStart < segEnd {
                overlap[segment.speaker, default: 0] += segEnd - segStart
            }
        }
        return overlap.max(by: { $0.value < $1.value })?.key
    }
}

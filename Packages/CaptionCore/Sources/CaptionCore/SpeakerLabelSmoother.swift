import Foundation

/// Turns the diarizer's raw speaker slots into the labels shown on screen (#91).
///
/// Measured on replayed speech (SpeakerStabilityReplayTests), labeling each live result by plain overlap
/// (`SpeakerAligner`) let sub-second segments of another slot relabel a line while it was being spoken, and showed
/// two people as "Speaker 1" and "Speaker 3" whenever the model used slots 0 and 2. This:
/// - ignores segments shorter than `minSegmentSeconds` when longer ones also cover the caption;
/// - keeps a live utterance on the speaker it was shown with until another slot holds `switchSeconds` of it
///   (a new utterance, or a final result, goes to whoever holds most of it, so real turns aren't delayed);
/// - numbers speakers in order of first appearance, and doesn't let a live scrap (only segments shorter than
///   `minSegmentSeconds`) of an unseen slot take a number.
/// It does not stop the model putting a whole stretch of one voice in a new slot after a pitch or pace change:
/// timing alone can't tell that from a second person, and a "new speakers must prove themselves" rule measured
/// worse (it merged the next person's first words into the previous person's line).
/// One instance per session: slot numbers mean nothing across sessions (CONTEXT.md).
public struct SpeakerLabelSmoother: Sendable {
    public var minSegmentSeconds: Double
    public var switchSeconds: Double

    private var current: Int?             // raw slot of the last label given
    private var currentStart: Double?     // where the caption that got it starts: same start = same utterance
    private var displayBySlot: [Int: Int] = [:]

    public init(minSegmentSeconds: Double = 0.5, switchSeconds: Double = 1.0) {
        self.minSegmentSeconds = minSegmentSeconds
        self.switchSeconds = switchSeconds
    }

    /// The display label (0-based, in order of appearance) for the caption covering `start...end`, given every
    /// segment the diarizer has produced so far. Nil until the diarizer has anything for that stretch.
    public mutating func label(start: Double, end: Double, segments: [SpeakerSegment], isFinal: Bool) -> Int? {
        guard let slot = chooseSlot(start: start, end: end, segments: segments, isFinal: isFinal) else { return nil }
        current = slot
        currentStart = start
        if let shown = displayBySlot[slot] { return shown }
        let shown = displayBySlot.count
        displayBySlot[slot] = shown
        return shown
    }

    private func chooseSlot(start: Double, end: Double, segments: [SpeakerSegment], isFinal: Bool) -> Int? {
        let covering = segments.filter { min(end, $0.end) - max(start, $0.start) > 0 }
        if covering.isEmpty {
            // A zero-length caption range has no overlap; fall back to the segment containing it.
            guard end <= start else { return nil }
            return segments.last(where: { $0.start <= start && start < $0.end })?.speaker
        }
        let long = covering.filter { $0.end - $0.start >= minSegmentSeconds }
        let evidence = long.isEmpty ? covering : long
        var overlap: [Int: Double] = [:]
        for s in evidence { overlap[s.speaker, default: 0] += min(end, s.end) - max(start, s.start) }
        guard let best = overlap.max(by: { $0.value < $1.value || ($0.value == $1.value && $1.key == current) }) else {
            return current
        }
        // A live scrap of a slot nobody has been shown as can't create a person (it would take the next number);
        // wait for more of it, or for the final result.
        if long.isEmpty && !isFinal && displayBySlot[best.key] == nil { return nil }
        guard let current, best.key != current else { return best.key }
        let sameUtterance = currentStart.map { abs($0 - start) < 0.05 } ?? false
        if !isFinal && sameUtterance && best.value < switchSeconds { return current }
        return best.key
    }
}

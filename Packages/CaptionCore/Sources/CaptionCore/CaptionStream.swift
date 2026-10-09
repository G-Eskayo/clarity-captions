import Foundation

public struct CaptionWord: Equatable, Sendable {
    public let text: String
    public let emphasis: EmphasisLevel
}

/// One caption line: a paragraph of finalized speech plus, while someone is still talking, a volatile tail
/// that is revised in place. `id` stays stable throughout, so the UI doesn't flicker as text flows in.
public struct CaptionLine: Identifiable, Equatable, Sendable {
    /// How faded a line is while it is still being revised. The screen and the contrast test both use this, so they cannot drift apart.
    public static let volatileOpacity: Double = 0.6
    public let id: Int
    /// 0-based speaker slot within this session, nil until the diarizer has attributed it.
    public var speaker: Int?
    /// Sound label for non-speech lines (laughter, applause, etc.); nil for ordinary speech lines.
    public var soundLabel: SoundLabelKind?
    /// Marker for non-speech lines (background return, etc.); nil for ordinary speech lines.
    public var marker: String?
    var committed: [CaptionWord]
    var tail: String?
    var tailRange: ClosedRange<Double>?
    var startTime: Double?
    var endTime: Double?

    public var text: String {
        let committedText = committed.map(\.text).joined(separator: " ")
        return [committedText, tail ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }
    public var styledWords: [(text: String, emphasis: EmphasisLevel)] {
        committed.map { (text: $0.text, emphasis: $0.emphasis) }
    }
    public var isFinal: Bool { tail == nil }
    public var isSoundLabel: Bool { soundLabel != nil }
    public var isMarker: Bool { marker != nil }
}

/// The live caption transcript. Pure value type -- no audio, no UI, no platform APIs -- so it is tested
/// on the host and shared by every platform target.
///
/// With audio times, speech flows into one line and breaks only at a real pause or a speaker change
/// (a wall of text and a line per fragment are both wrong). Without times, each finished result closes its line.
public struct CaptionStream: Sendable {
    /// A silence this long, in seconds of audio, starts a new line. One setting, tuned on real conversation.
    public static let defaultPauseSeconds: Double = 1.2

    public let pauseSeconds: Double
    public private(set) var lines: [CaptionLine] = []
    private var nextID = 0

    public init(pauseSeconds: Double = CaptionStream.defaultPauseSeconds) {
        self.pauseSeconds = pauseSeconds
    }

    private static func captionWords(from text: String, emphasis: [EmphasisLevel]) -> [CaptionWord] {
        let words = text.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
        return words.enumerated().map { (i, word) in
            let wordEmphasis = i < emphasis.count ? emphasis[i] : .normal
            return CaptionWord(text: word, emphasis: wordEmphasis)
        }
    }

    public mutating func apply(text: String, isFinal: Bool, speaker: Int? = nil, range: ClosedRange<Double>? = nil, wordEmphasis: [EmphasisLevel] = []) {
        let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return }

        let words = Self.captionWords(from: piece, emphasis: wordEmphasis)
        if var last = lines.last {
            // Never merge speech into a line marked as a sound label or marker.
            guard !last.isSoundLabel && !last.isMarker else {
                // Breaking away: close whatever was still open on the previous line (should already be final for sound labels/markers).
                if let stale = last.tail {
                    last.committed = Self.joinWords(last.committed, stale); last.tail = nil; last.tailRange = nil
                    lines[lines.count - 1] = last
                }
                lines.append(CaptionLine(
                    id: nextID, speaker: speaker,
                    committed: isFinal ? words : [], tail: isFinal ? nil : piece,
                    tailRange: isFinal ? nil : range, startTime: range?.lowerBound, endTime: range?.upperBound))
                nextID += 1
                return
            }

            // A revision of the segment still being spoken replaces the tail. Without timing, any result
            // arriving while a tail is open is a revision; with timing, it must start before the tail ends.
            if last.tail != nil {
                let revises: Bool
                if let r = range, let tr = last.tailRange { revises = r.lowerBound < tr.upperBound } else { revises = true }
                if revises {
                    if isFinal { last.committed = Self.joinWords(last.committed, piece); last.tail = nil; last.tailRange = nil }
                    else { last.tail = piece; last.tailRange = range ?? last.tailRange }
                    if let r = range { last.endTime = r.upperBound }
                    last.speaker = speaker ?? last.speaker
                    lines[lines.count - 1] = last
                    return
                }
            }
            if last.tail == nil, range == nil {
                // No timing information: each finished result closes its line.
            } else if let r = range, let end = last.endTime ?? last.tailRange?.upperBound {
                let changed = speaker != nil && last.speaker != nil && speaker != last.speaker
                if r.lowerBound - end < pauseSeconds && !changed {
                    if let stale = last.tail { last.committed = Self.joinWords(last.committed, stale); last.tail = nil; last.tailRange = nil }
                    if isFinal { last.committed = Self.joinWords(last.committed, piece) }
                    else { last.tail = piece; last.tailRange = r }
                    last.endTime = r.upperBound
                    last.speaker = speaker ?? last.speaker
                    lines[lines.count - 1] = last
                    return
                }
            }
            // Breaking away: close whatever was still open on the previous line.
            if let stale = last.tail {
                last.committed = Self.joinWords(last.committed, stale); last.tail = nil; last.tailRange = nil
                lines[lines.count - 1] = last
            }
        }

        lines.append(CaptionLine(
            id: nextID, speaker: speaker,
            committed: isFinal ? words : [], tail: isFinal ? nil : piece,
            tailRange: isFinal ? nil : range, startTime: range?.lowerBound, endTime: range?.upperBound))
        nextID += 1
    }

    /// Closes any open volatile tail on the last line and appends a new, already-final sound label line.
    public mutating func insertSoundLabel(_ label: SoundLabelKind) {
        if var last = lines.last {
            if let stale = last.tail {
                last.committed = Self.joinWords(last.committed, stale); last.tail = nil; last.tailRange = nil
                lines[lines.count - 1] = last
            }
        }

        let labelText = SoundLabelFormatter.caption(for: label)
        let labelWords = Self.captionWords(from: labelText, emphasis: [])
        lines.append(CaptionLine(
            id: nextID, speaker: nil, soundLabel: label,
            committed: labelWords,
            tail: nil, tailRange: nil, startTime: nil, endTime: nil))
        nextID += 1
    }

    /// Closes any open volatile tail on the last line and appends a new, already-final marker line.
    public mutating func insertMarker(_ text: String) {
        if var last = lines.last {
            if let stale = last.tail {
                last.committed = Self.joinWords(last.committed, stale); last.tail = nil; last.tailRange = nil
                lines[lines.count - 1] = last
            }
        }

        let markerWords = Self.captionWords(from: text, emphasis: [])
        lines.append(CaptionLine(
            id: nextID, speaker: nil, marker: text,
            committed: markerWords,
            tail: nil, tailRange: nil, startTime: nil, endTime: nil))
        nextID += 1
    }

    private static func joinWords(_ a: [CaptionWord], _ b: String) -> [CaptionWord] {
        let bWords = captionWords(from: b, emphasis: [])
        return a.isEmpty ? bWords : a + bWords
    }

    private static func join(_ a: String, _ b: String) -> String { a.isEmpty ? b : a + " " + b }
}

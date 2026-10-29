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
    /// Face to face (#60): which half's language engine wrote this line. Nil for one-way captions.
    public var lane: FaceToFaceHalf?
    var committed: [CaptionWord]
    var tail: String?
    var tailRange: ClosedRange<Double>?
    var startTime: Double?
    var endTime: Double?

    init(id: Int, speaker: Int? = nil, soundLabel: SoundLabelKind? = nil, lane: FaceToFaceHalf? = nil, committed: [CaptionWord],
         tail: String? = nil, tailRange: ClosedRange<Double>? = nil, startTime: Double? = nil, endTime: Double? = nil) {
        self.id = id
        self.speaker = speaker
        self.soundLabel = soundLabel
        self.lane = lane
        self.committed = committed
        self.tail = tail
        self.tailRange = tailRange
        self.startTime = startTime
        self.endTime = endTime
    }

    public var text: String {
        let committedText = committed.map(\.text).joined(separator: " ")
        return [committedText, tail ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }
    public var styledWords: [(text: String, emphasis: EmphasisLevel)] {
        committed.map { (text: $0.text, emphasis: $0.emphasis) }
    }
    public var isFinal: Bool { tail == nil }
    public var isSoundLabel: Bool { soundLabel != nil }
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

    public mutating func apply(text: String, isFinal: Bool, speaker: Int? = nil, range: ClosedRange<Double>? = nil, wordEmphasis: [EmphasisLevel] = [],
                               lane: FaceToFaceHalf? = nil) {
        let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else {
            // Face to face (#60): an engine's revision that now has none of its own words takes back its open words.
            if let lane, let i = lines.lastIndex(where: { $0.lane == lane }), lines[i].tail != nil {
                if lines[i].committed.isEmpty { lines.remove(at: i) } else { lines[i].tail = nil; lines[i].tailRange = nil }
            }
            return
        }

        let words = Self.captionWords(from: piece, emphasis: wordEmphasis)
        // Face to face (#60): each engine continues its own lines; another engine's line in between is skipped, and a
        // sound label still breaks the line. One-way captions (no lane) only ever continue the last line.
        let index = lane == nil ? lines.indices.last.flatMap { lines[$0].lane == nil ? $0 : nil }
            : lines.lastIndex { $0.lane == lane || $0.isSoundLabel }
        if let index {
            var last = lines[index]
            // Never merge speech into a line marked as a sound label.
            guard !last.isSoundLabel else {
                // Breaking away: close whatever was still open on the previous line (should already be final for sound labels).
                if let stale = last.tail {
                    last.committed = Self.joinWords(last.committed, stale); last.tail = nil; last.tailRange = nil
                    lines[index] = last
                }
                lines.append(CaptionLine(
                    id: nextID, speaker: speaker, lane: lane,
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
                    // The words being revised joined this line before their speaker was known, and belong to
                    // someone else: give them their own line instead of relabeling the earlier words (#91).
                    if let speaker, let lineSpeaker = last.speaker, speaker != lineSpeaker, !last.committed.isEmpty {
                        let tailStart = last.tailRange?.lowerBound ?? range?.lowerBound
                        last.tail = nil; last.tailRange = nil
                        lines[index] = last
                        lines.append(CaptionLine(
                            id: nextID, speaker: speaker, lane: lane,
                            committed: isFinal ? words : [], tail: isFinal ? nil : piece,
                            tailRange: isFinal ? nil : range, startTime: tailStart, endTime: range?.upperBound))
                        nextID += 1
                        return
                    }
                    if isFinal { last.committed = Self.joinWords(last.committed, piece); last.tail = nil; last.tailRange = nil }
                    else { last.tail = piece; last.tailRange = range ?? last.tailRange }
                    if let r = range { last.endTime = r.upperBound }
                    last.speaker = speaker ?? last.speaker
                    lines[index] = last
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
                    lines[index] = last
                    return
                }
            }
            // Breaking away: close whatever was still open on the previous line.
            if let stale = last.tail {
                last.committed = Self.joinWords(last.committed, stale); last.tail = nil; last.tailRange = nil
                lines[index] = last
            }
        }

        lines.append(CaptionLine(
            id: nextID, speaker: speaker, lane: lane,
            committed: isFinal ? words : [], tail: isFinal ? nil : piece,
            tailRange: isFinal ? nil : range, startTime: range?.lowerBound, endTime: range?.upperBound))
        nextID += 1
    }

    /// Leaving the face-to-face split (#60): drops the lines it didn't show. Ids are kept, and never reused.
    public mutating func removeLines(where shouldRemove: (CaptionLine) -> Bool) {
        lines.removeAll(where: shouldRemove)
    }

    /// Ends the last line, so the next result starts a new one. Called when captioning resumes after a pause (#102):
    /// the new engine session's audio clock starts again at zero, which would otherwise read as a short pause and
    /// merge into the line spoken before it.
    public mutating func breakLine() {
        guard var last = lines.last else { return }
        if let stale = last.tail { last.committed = Self.joinWords(last.committed, stale); last.tail = nil }
        last.tailRange = nil
        last.endTime = nil
        lines[lines.count - 1] = last
    }

    /// Closes any open volatile tail on the last line and appends a new, already-final sound label line.
    public mutating func insertSoundLabel(_ label: SoundLabelKind) {
        // Every open tail, not only the last line's: face to face has one per engine (#60).
        for i in lines.indices.reversed() where lines[i].tail != nil {
            var line = lines[i]
            line.committed = Self.joinWords(line.committed, line.tail!); line.tail = nil; line.tailRange = nil
            lines[i] = line
        }

        let labelText = SoundLabelFormatter.caption(for: label)
        let labelWords = Self.captionWords(from: labelText, emphasis: [])
        lines.append(CaptionLine(
            id: nextID, speaker: nil, soundLabel: label,
            committed: labelWords,
            tail: nil, tailRange: nil, startTime: nil, endTime: nil))
        nextID += 1
    }

    private static func joinWords(_ a: [CaptionWord], _ b: String) -> [CaptionWord] {
        let bWords = captionWords(from: b, emphasis: [])
        return a.isEmpty ? bWords : a + bWords
    }

    private static func join(_ a: String, _ b: String) -> String { a.isEmpty ? b : a + " " + b }
}

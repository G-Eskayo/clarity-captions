import Foundation

/// #60: the two halves of the face-to-face split. The owner's half faces her; the partner's half is turned 180°
/// to face the person across from her.
public enum FaceToFaceHalf: Equatable, Hashable, Sendable {
    case owner, partner

    /// The half across the middle line.
    public var other: FaceToFaceHalf { self == .owner ? .partner : .owner }
}

/// Which half each speaker belongs to. Live, `SpeakerLanguages` gives a voice its half from the language it speaks
/// (the owner's "voice first", #60); the debug demo places its two speakers by hand.
public struct FaceToFaceSides: Equatable, Sendable {
    private var bySpeaker: [Int: FaceToFaceHalf] = [:]

    public init() {}

    public mutating func assign(speaker: Int, to half: FaceToFaceHalf) { bySpeaker[speaker] = half }

    /// The half a speaker belongs to, or nil when nobody has said yet.
    public func half(ofSpeaker speaker: Int?) -> FaceToFaceHalf? { speaker.flatMap { bySpeaker[$0] } }
}

/// One line as a half shows it: the words in that half's reader's language when known, and what was said when the
/// words shown are a translation (#171's look: translation on top, what was said smaller underneath).
public struct FaceToFaceEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    /// The words shown at caption size.
    public let text: String
    /// What was said, when `text` is its translation; nil otherwise.
    public let said: String?
    /// The half whose speaker said it; nil while nobody knows.
    public let from: FaceToFaceHalf?
    public let isFinal: Bool
    public let isSoundLabel: Bool

    public var isTranslated: Bool { said != nil }
}

public enum FaceToFace {
    /// The smallest screen side, in points, that fits two readable halves. iPad mini (744) and the unfolded iPhone Duo
    /// (669) clear it; every plain iPhone (440 at most) and the folded Duo (466) don't.
    public static let minimumShortSide: Double = 600

    /// Whether the captions screen offers the Face to face button: a screen big enough for two halves, with
    /// translation on. Everywhere else translation stays one-way (#171).
    public static func offersSplit(width: Double, height: Double, translationOn: Bool) -> Bool {
        translationOn && min(width, height) >= minimumShortSide
    }

    /// What a half shows, in the stream's order. Its own speaker's words as said; the other person's finished words
    /// translated into this half's language when the translation has arrived; anything still being spoken, not yet
    /// translated, or from a speaker with no half yet, as said. `translation(line, into)` gives a line's words in
    /// the language of the half `into`, or nil.
    public static func entries(for half: FaceToFaceHalf, lines: [CaptionLine], sides: FaceToFaceSides,
                               translation: (CaptionLine, FaceToFaceHalf) -> String?) -> [FaceToFaceEntry] {
        entries(for: half, lines: lines, half: { sides.half(ofSpeaker: $0.speaker) }, translation: translation)
    }

    /// The same, with each line's half given by `half(line)` (live: `SpeakerLanguages.half(of:)`).
    public static func entries(for half: FaceToFaceHalf, lines: [CaptionLine], half lineHalf: (CaptionLine) -> FaceToFaceHalf?,
                               translation: (CaptionLine, FaceToFaceHalf) -> String?) -> [FaceToFaceEntry] {
        lines.compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let from = line.isSoundLabel ? nil : lineHalf(line)
            if let from, from != half, line.isFinal, let translated = translation(line, half) {
                return FaceToFaceEntry(id: line.id, text: translated, said: line.text, from: from,
                                       isFinal: true, isSoundLabel: false)
            }
            return FaceToFaceEntry(id: line.id, text: line.text, said: nil, from: from,
                                   isFinal: line.isFinal, isSoundLabel: line.isSoundLabel)
        }
    }

    /// The lines the split shows, from captions both engines wrote into (#60): for each voice, only the engine of the
    /// language it was matched to (or, before that, the one its words lean toward). Lines with no engine lane (from
    /// before the split, sound labels) always show. Leaving the split keeps exactly these.
    public static func shown(_ lines: [CaptionLine], languages: SpeakerLanguages) -> [CaptionLine] {
        lines.filter { isShown($0, languages: languages) }
    }

    public static func isShown(_ line: CaptionLine, languages: SpeakerLanguages) -> Bool {
        guard let lane = line.lane else { return true }
        return lane == languages.shownLane(for: line.speaker, at: line.startTime)
    }

    /// The lines said on `half`: the ones its translator turns into the other half's language. Lines with no half yet
    /// are translated by neither (they show as said on both halves).
    public static func lines(saidOn half: FaceToFaceHalf, in lines: [CaptionLine],
                             half lineHalf: (CaptionLine) -> FaceToFaceHalf?) -> [CaptionLine] {
        lines.filter { !$0.isSoundLabel && lineHalf($0) == half }
    }

    /// One engine's result with the words of voices that belong to the other half's engine taken out (#60): a result
    /// can run past a turn change, because Apple's engine only ends one at a long pause and an engine keeps hearing the
    /// next voice for the moment before the diarizer names it. Words the diarizer hasn't placed yet, and voices not
    /// matched yet, stay. Nil when nothing is left; the same result when nothing was taken out.
    public static func keep(_ piece: RecognizedPiece, lane: FaceToFaceHalf, segments: [SpeakerSegment], number: (Int) -> Int?,
                            languages: SpeakerLanguages) -> RecognizedPiece? {
        let kept = piece.words.filter { word in
            guard let range = word.range,
                  let slot = SpeakerAligner.speaker(start: range.lowerBound, end: range.upperBound, segments: segments),
                  let voice = number(slot), languages.isMatched(voice) else { return true }
            return languages.shownLane(for: voice, at: range.lowerBound) == lane
        }
        if kept.count == piece.words.count { return piece }
        if kept.isEmpty { return nil }
        return RecognizedPiece(text: kept.map(\.text).joined(separator: " "), isFinal: piece.isFinal, words: kept)
    }

    /// Word times moved to where the engine's audio resumed, for words that start before a skip and end after it (#60):
    /// Apple's open result reports its words from the last audio it heard, which is before the other voice's turn, and
    /// would glue the new turn onto the old line. The same result when nothing straddles a skip.
    public static func clamp(_ piece: RecognizedPiece, skips: [Double]) -> RecognizedPiece {
        var changed = false
        let words = piece.words.map { word -> RecognizedWord in
            guard let r = word.range, let skip = skips.last(where: { $0 > r.lowerBound && $0 <= r.upperBound }) else { return word }
            changed = true
            return RecognizedWord(text: word.text, range: skip...r.upperBound)
        }
        guard changed else { return piece }
        return RecognizedPiece(text: piece.text, isFinal: piece.isFinal, words: words)
    }
}

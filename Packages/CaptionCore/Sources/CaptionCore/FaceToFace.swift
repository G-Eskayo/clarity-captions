import Foundation

/// #60: the two halves of the face-to-face split. The owner's half faces her; the partner's half is turned 180°
/// to face the person across from her.
public enum FaceToFaceHalf: Equatable, Hashable, Sendable {
    case owner, partner

    /// The half across the middle line.
    public var other: FaceToFaceHalf { self == .owner ? .partner : .owner }
}

/// Which half each speaker belongs to. How a speaker gets a half (a tap, the speaker diarizer, or whichever
/// language engine recognised them) is the owner's open decision on #60; this only keeps the answer.
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
        lines.compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let from = line.isSoundLabel ? nil : sides.half(ofSpeaker: line.speaker)
            if let from, from != half, line.isFinal, let translated = translation(line, half) {
                return FaceToFaceEntry(id: line.id, text: translated, said: line.text, from: from,
                                       isFinal: true, isSoundLabel: false)
            }
            return FaceToFaceEntry(id: line.id, text: line.text, said: nil, from: from,
                                   isFinal: line.isFinal, isSoundLabel: line.isSoundLabel)
        }
    }
}

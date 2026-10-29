import Foundation
import NaturalLanguage

/// #60, the owner's "voice first" (2026-10-29): the diarizer tells the people apart, and each voice is matched to one of
/// the split's two languages from the words its first lines are in. Lock as soon as that's sure; stay correctable.
///
/// The numbers (measured in docs/perf/face-to-face-spike.md, put to the owner as a Decision on the PR):
/// - **Lock:** 4 or more words of that voice, 95% sure of one language. Every real Spanish sentence and every
///   English line of 4+ words scored 99% or more in the spike; one word ("Hi.") only reached 68%.
/// - **Correct:** once locked, a finished line of 4+ words that is 95% sure of the *other* language counts against the
///   lock; two in a row move the voice to the other language. One garbled line never does.
/// - **Check:** two finished lines in a row that are sure of neither language bring the other engine back for that
///   voice, and the next sure 4+ words decide (stay, or move).
/// - **Give up waiting:** 30 words without a sure answer: lock to the likelier language (or, when checking, stay), so
///   both engines don't run for ever.
public struct LanguageMatchPolicy: Equatable, Sendable {
    public var lockProbability = 0.95
    public var minWords = 4
    public var contraryLines = 2
    public var doubtfulLines = 2
    public var giveUpWords = 30
    public init() {}
}

/// Which language (half) each voice speaks, and so which engine hears it. Pure: the caller says what each engine heard
/// and how sure the words' language is. Speaker numbers are the ones caption lines carry.
///
/// Space: O(voices + words heard while a voice is being matched or checked, at most `giveUpWords` per lane).
public struct SpeakerLanguages: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// No language yet: both engines hear this voice.
        case matching
        /// Only this half's engine hears them.
        case locked(FaceToFaceHalf)
        /// Locked to this half, but their last lines were unclear: both engines hear them again until it's sure.
        case checking(FaceToFaceHalf)
    }

    public enum Change: Equatable, Sendable {
        case locked(speaker: Int, FaceToFaceHalf)
        case checking(speaker: Int)
        case kept(speaker: Int, FaceToFaceHalf)
        case rematched(speaker: Int, from: FaceToFaceHalf, to: FaceToFaceHalf)
    }

    /// Before a voice has any words, the caption language's engine is shown: what one-way captions show.
    public static let defaultLane: FaceToFaceHalf = .partner

    private struct WordKey: Hashable, Sendable { let lane: FaceToFaceHalf; let tenths: Int }

    private struct Voice: Equatable, Sendable {
        var state: State = .matching
        /// Words heard while matching or checking, one per engine and start time (a revision replaces).
        var words: [WordKey: TimedWord] = [:]
        /// The language the words lean toward so far, while matching.
        var leader: FaceToFaceHalf?
        /// Which half's engine is shown for audio from `since` on, oldest first. The first lock covers everything
        /// before it (the matching lines).
        var history: [(since: Double, half: FaceToFaceHalf)] = []
        var contrary = 0
        var doubtful = 0
        var checkingSince = -Double.infinity

        static func == (a: Voice, b: Voice) -> Bool {
            a.state == b.state && a.words == b.words && a.leader == b.leader && a.contrary == b.contrary
                && a.doubtful == b.doubtful && a.checkingSince == b.checkingSince
                && a.history.map(\.since) == b.history.map(\.since) && a.history.map(\.half) == b.history.map(\.half)
        }
    }

    public let policy: LanguageMatchPolicy
    private var voices: [Int: Voice] = [:]

    public init(policy: LanguageMatchPolicy = LanguageMatchPolicy()) { self.policy = policy }

    /// Nil until the voice has been heard.
    public func state(of speaker: Int) -> State? { voices[speaker]?.state }

    /// The half each voice belongs to: locked (or being checked) voices only.
    public var sides: FaceToFaceSides {
        var sides = FaceToFaceSides()
        for (speaker, voice) in voices {
            switch voice.state {
            case .locked(let h), .checking(let h): sides.assign(speaker: speaker, to: h)
            case .matching: break
            }
        }
        return sides
    }

    /// The half a line belongs to. Lines from before the split (no engine lane) have none: speaker numbers restart
    /// with each captioning session, so their number may now be someone else's.
    public func half(of line: CaptionLine) -> FaceToFaceHalf? {
        guard line.lane != nil, !line.isSoundLabel else { return nil }
        return sides.half(ofSpeaker: line.speaker)
    }

    /// Whether the voice has ever been given a language (it has a half, now or before a correction).
    public func isMatched(_ speaker: Int) -> Bool { !(voices[speaker]?.history.isEmpty ?? true) }

    /// Which engines hear this voice. Unknown or unmatched voices, and voices being checked: both.
    public func lanes(for speaker: Int?) -> Set<FaceToFaceHalf> {
        guard let speaker, let voice = voices[speaker], case .locked(let h) = voice.state else { return [.owner, .partner] }
        return [h]
    }

    /// Whose engine's words are shown for this voice's audio at `time`: the half it was locked to then (the first lock
    /// also covers the lines matched before it), else the language its words lean toward, else the caption language.
    public func shownLane(for speaker: Int?, at time: Double?) -> FaceToFaceHalf {
        guard let speaker, let voice = voices[speaker] else { return Self.defaultLane }
        if let first = voice.history.first {
            guard let time else { return voice.history.last!.half }
            return voice.history.last(where: { $0.since <= time })?.half ?? first.half
        }
        return voice.leader ?? Self.defaultLane
    }

    /// An engine (`lane`) heard `words` from this voice. `classify` gives how sure the words' language is, per half.
    /// Matching and checking count every engine's words, volatile or final; a locked voice is judged one finished line
    /// at a time, from its own engine only (the other engine's words at a turn's edge aren't evidence).
    @discardableResult
    public mutating func heard(speaker: Int, lane: FaceToFaceHalf, words: [TimedWord], isFinal: Bool,
                               classify: (String) -> [FaceToFaceHalf: Double]) -> Change? {
        var voice = voices[speaker] ?? Voice()
        defer { voices[speaker] = voice }
        switch voice.state {
        case .matching:
            collect(words, lane: lane, after: -.infinity, into: &voice)
            let (count, best, p) = judge(voice, classify)
            voice.leader = best
            if count >= policy.minWords, p >= policy.lockProbability {
                return lock(&voice, speaker: speaker, to: best)
            }
            if count >= policy.giveUpWords {
                return lock(&voice, speaker: speaker, to: p > 0.5 ? best : Self.defaultLane)
            }
            return nil

        case .locked(let half):
            guard isFinal, lane == half, words.count >= policy.minWords else { return nil }
            let scores = classify(Self.text(words))
            let other = half.other
            let end = words.map(\.end).max() ?? 0
            if (scores[half] ?? 0) >= policy.lockProbability {
                voice.contrary = 0
                voice.doubtful = 0
                return nil
            }
            voice.doubtful += 1
            if (scores[other] ?? 0) >= policy.lockProbability {
                voice.contrary += 1
                if voice.contrary >= policy.contraryLines {
                    // Only this engine heard those lines: they stay shown, and the other engine takes over from here.
                    return move(&voice, speaker: speaker, from: half, since: end)
                }
            } else {
                voice.contrary = 0
            }
            if voice.doubtful >= policy.doubtfulLines {
                voice.state = .checking(half)
                voice.checkingSince = end
                voice.words = [:]
                voice.doubtful = 0
                voice.contrary = 0
                return .checking(speaker: speaker)
            }
            return nil

        case .checking(let half):
            collect(words, lane: lane, after: voice.checkingSince, into: &voice)
            let (count, best, p) = judge(voice, classify)
            if count >= policy.minWords, p >= policy.lockProbability, best != half {
                return move(&voice, speaker: speaker, from: half, since: voice.checkingSince)
            }
            if (count >= policy.minWords && p >= policy.lockProbability) || count >= policy.giveUpWords {
                voice.state = .locked(half)
                voice.words = [:]
                return .kept(speaker: speaker, half)
            }
            return nil
        }
    }

    private func collect(_ words: [TimedWord], lane: FaceToFaceHalf, after: Double, into voice: inout Voice) {
        for w in words where w.start >= after {
            voice.words[WordKey(lane: lane, tenths: Int((w.start * 10).rounded()))] = w
        }
    }

    /// Words counted per engine (the same speech heard by both is counted once), the likelier half, and how sure.
    private func judge(_ voice: Voice, _ classify: (String) -> [FaceToFaceHalf: Double]) -> (Int, FaceToFaceHalf, Double) {
        let count = [FaceToFaceHalf.owner, .partner].map { lane in voice.words.keys.filter { $0.lane == lane }.count }.max() ?? 0
        let ordered = voice.words.sorted { ($0.value.start, $0.key.lane == .owner ? 0 : 1) < ($1.value.start, $1.key.lane == .owner ? 0 : 1) }
        let scores = classify(Self.text(ordered.map(\.value)))
        let owner = scores[.owner] ?? 0, partner = scores[.partner] ?? 0
        return owner > partner ? (count, .owner, owner) : (count, .partner, partner)
    }

    private func lock(_ voice: inout Voice, speaker: Int, to half: FaceToFaceHalf) -> Change {
        voice.state = .locked(half)
        voice.history = [(-.infinity, half)]
        voice.words = [:]
        voice.leader = half
        return .locked(speaker: speaker, half)
    }

    private func move(_ voice: inout Voice, speaker: Int, from half: FaceToFaceHalf, since: Double) -> Change {
        voice.state = .locked(half.other)
        voice.history.append((since, half.other))
        voice.words = [:]
        voice.contrary = 0
        voice.doubtful = 0
        return .rematched(speaker: speaker, from: half, to: half.other)
    }

    private static func text(_ words: [TimedWord]) -> String { words.map(\.text).joined(separator: " ") }
}

/// The two halves' languages, and how sure some words are of each (Apple's NaturalLanguage, on the device). Engine
/// confidence can't do this: Parakeet Ultra writes Spanish almost perfectly, and Apple's Spanish engine writes English
/// as English (spike, #60), but the language of the words they write is the language that was spoken.
public struct LanguagePair: Sendable {
    public let owner: Locale
    public let partner: Locale

    public init(owner: Locale, partner: Locale) {
        self.owner = owner
        self.partner = partner
    }

    private static func language(_ locale: Locale) -> NLLanguage {
        NLLanguage(rawValue: locale.language.languageCode?.identifier ?? locale.identifier)
    }

    /// Per half, how likely the words are in its language. Even (0.5 each) when there are no words, or when both halves
    /// share a language, so the matcher never decides on it.
    public func probabilities(_ text: String) -> [FaceToFaceHalf: Double] {
        let a = Self.language(owner), b = Self.language(partner)
        guard a != b, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [.owner: 0.5, .partner: 0.5] }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [a, b]
        recognizer.processString(text)
        let h = recognizer.languageHypotheses(withMaximum: 2)
        let pa = h[a] ?? 0, pb = h[b] ?? 0
        guard pa + pb > 0 else { return [.owner: 0.5, .partner: 0.5] }
        return [.owner: pa / (pa + pb), .partner: pb / (pa + pb)]
    }
}

/// Which engines hear the audio right now, from the diarizer's latest speaker. Pure.
/// - A voice with a language: only that engine. Unknown, unmatched or being checked: both.
/// - When an engine starts listening it is first re-fed from just before that speaker's turn began, so the turn's first
///   words (said before the diarizer named the speaker, about 0.7 s in the spike) aren't lost.
/// - Silence, and scraps of another slot shorter than `minSegmentSeconds`, change nothing.
public struct VoiceRouter: Sendable {
    public var holdSeconds = 1.5
    public var leadSeconds = 0.6
    public var minSegmentSeconds = 0.3
    public private(set) var active: Set<FaceToFaceHalf> = [.owner, .partner]

    public init() {}

    /// Updates `active` for audio at `now` and returns, for each engine that just started listening, the session time
    /// to re-feed it from. `number` maps a diarizer slot to the speaker number lines carry (nil: not numbered yet).
    @discardableResult
    public mutating func route(now: Double, segments: [SpeakerSegment], number: (Int) -> Int?,
                               languages: SpeakerLanguages) -> [FaceToFaceHalf: Double] {
        guard let latest = segments.max(by: { $0.end < $1.end }), latest.end >= now - holdSeconds,
              latest.end - latest.start >= minSegmentSeconds else { return [:] }
        let want = languages.lanes(for: number(latest.speaker))
        var refeed: [FaceToFaceHalf: Double] = [:]
        for lane in want.subtracting(active) { refeed[lane] = max(0, latest.start - leadSeconds) }
        active = want
        return refeed
    }
}

/// How far one engine has been fed, in session seconds, when it only hears part of the conversation. Pure.
public struct LaneClock: Sendable {
    public struct Plan: Equatable, Sendable {
        /// The engine missed audio: move its clock here before feeding.
        public let skipTo: Double?
        /// Samples at the front it already had.
        public let dropFirst: Int
        public init(skipTo: Double?, dropFirst: Int) {
            self.skipTo = skipTo
            self.dropFirst = dropFirst
        }
    }

    public static let rate = 16_000.0
    public private(set) var fedUntil = 0.0

    public init() {}

    /// Plans feeding `count` samples that begin at session time `start`.
    public mutating func plan(start: Double, count: Int) -> Plan {
        let end = start + Double(count) / Self.rate
        if start > fedUntil + 0.5 / Self.rate {
            fedUntil = end
            return Plan(skipTo: start, dropFirst: 0)
        }
        let drop = min(count, max(0, Int(((fedUntil - start) * Self.rate).rounded())))
        fedUntil = max(fedUntil, end)
        return Plan(skipTo: nil, dropFirst: drop)
    }
}

/// The last few seconds of 16 kHz audio, so an engine that starts listening mid-turn can be given the turn's start.
/// Bounded: `seconds` of samples.
public struct AudioRing: Sendable {
    public let seconds: Double
    private var samples: [Float] = []
    private var startTime = 0.0

    public init(seconds: Double = 8) { self.seconds = seconds }

    public mutating func append(_ more: [Float], at time: Double) {
        if samples.isEmpty { startTime = time }
        samples.append(contentsOf: more)
        let excess = samples.count - Int(seconds * LaneClock.rate)
        if excess > 0 {
            samples.removeFirst(excess)
            startTime += Double(excess) / LaneClock.rate
        }
    }

    /// The kept audio between `from` and `to` (session seconds), and where it actually starts.
    public func samples(from: Double, to: Double) -> (from: Double, samples: [Float]) {
        let a = max(0, Int(((from - startTime) * LaneClock.rate).rounded()))
        let b = min(samples.count, Int(((to - startTime) * LaneClock.rate).rounded()))
        guard a < b else { return (from, []) }
        return (startTime + Double(a) / LaneClock.rate, Array(samples[a..<b]))
    }
}

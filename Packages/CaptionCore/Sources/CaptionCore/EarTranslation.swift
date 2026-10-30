import Foundation

/// Live Translation in your ear (#233): which words of the captions get spoken, and when. The owner's answer on #238
/// ("timing" B): the first phrase of what someone is saying goes sooner, once its words stop changing; the rest goes
/// when the engine finishes those words. Pure bookkeeping; the app translates each phrase and speaks it.
public struct EarPhrases: Sendable {
    public struct Phrase: Equatable, Sendable {
        public let lineID: Int
        public let text: String
        /// Which of the line's words it is, so the screen can follow the voice along the line.
        public let words: Range<Int>
        /// Spoken before the engine finished these words: it can turn out wrong, and can't be taken back.
        public let early: Bool
    }

    /// The spike (#237): the first 3 words of a line are final a median of 2.0 s before the line is, on 54 of 87 lines.
    public static let minimumEarlyWords = 3
    /// How long the first words must stay the same on screen before they're spoken early. Not measured on device yet
    /// (step D6 in #237): long enough to sit through one or two revisions of the engine's open words.
    public static let defaultHold: Double = 0.8

    private struct LineState: Sendable {
        var spoken = 0
        /// The open words not yet spoken, as last seen, and since when each prefix of them has stayed the same.
        var run: [String] = []
        var since: [Double] = []
    }

    public let speaksEarly: Bool
    public let minimumEarlyWords: Int
    public let hold: Double
    private var state: [Int: LineState] = [:]
    /// When the app should look again (on the same clock as `now`): words are holding still and will have held long
    /// enough by then. Nil when nothing is waiting.
    public private(set) var nextCheck: Double?

    public init(speaksEarly: Bool = true, minimumEarlyWords: Int = EarPhrases.minimumEarlyWords, hold: Double = EarPhrases.defaultHold) {
        self.speaksEarly = speaksEarly
        self.minimumEarlyWords = max(1, minimumEarlyWords)
        self.hold = hold
    }

    /// The phrases ready to speak now, oldest first; each word is handed out once.
    public mutating func take(from lines: [CaptionLine], now: Double) -> [Phrase] {
        if lines.isEmpty { reset(); return [] }
        var out: [Phrase] = []
        var next: Double?
        for line in lines where Self.isSpoken(line) {
            var s = state[line.id] ?? LineState()
            let words = Self.split(line.text)
            let committed = min(line.styledWords.count, words.count)
            if committed > s.spoken {
                out.append(Phrase(lineID: line.id, text: words[s.spoken..<committed].joined(separator: " "),
                                  words: s.spoken..<committed, early: false))
                s.spoken = committed
                s.run = []; s.since = []
            }
            // Early: only the first phrase of what's still open, and only when none of it went early already, so a
            // sentence isn't cut into scraps.
            if speaksEarly, !line.isFinal, s.spoken == committed, words.count > s.spoken {
                let open = Array(words[s.spoken...])
                let keys = open.map(Self.key)
                var same = 0
                while same < min(keys.count, s.run.count), keys[same] == s.run[same] { same += 1 }
                s.since = Array(s.since.prefix(same)) + Array(repeating: now, count: keys.count - same)
                s.run = keys
                let steady = s.since.prefix { now - $0 >= hold - 1e-9 }.count
                if steady >= minimumEarlyWords {
                    out.append(Phrase(lineID: line.id, text: open[0..<steady].joined(separator: " "),
                                      words: s.spoken..<(s.spoken + steady), early: true))
                    s.spoken += steady
                    s.run = []; s.since = []
                } else if s.since.count >= minimumEarlyWords {
                    let at = s.since[minimumEarlyWords - 1] + hold
                    next = min(next ?? at, at)
                }
            } else if line.isFinal {
                s.run = []; s.since = []
            }
            state[line.id] = s
        }
        nextCheck = next
        return out
    }

    /// Everything on screen now counts as spoken: turned on mid-conversation, it speaks only what comes next.
    public mutating func skip(_ lines: [CaptionLine]) {
        for line in lines where Self.isSpoken(line) {
            state[line.id] = LineState(spoken: Self.split(line.text).count)
        }
        nextCheck = nil
    }

    /// A new conversation.
    public mutating func reset() {
        state = [:]
        nextCheck = nil
    }

    /// Face to face (#60) has its own two-way screen; the ear is for one-way captions. Sound labels aren't speech.
    private static func isSpoken(_ line: CaptionLine) -> Bool { line.lane == nil && !line.isSoundLabel }

    private static func split(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }

    /// A revision that only changes case or punctuation hasn't changed the word.
    private static func key(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .punctuationCharacters)
    }
}

/// "behind" A (#238): when people talk faster than the voice, it speaks a little faster to catch up and never skips.
public enum EarPace {
    /// Never past this, so the voice stays easy to follow.
    public static let maximumSpeed: Double = 1.3
    private static let stepPerPhrase: Double = 0.1

    /// How much faster than normal to say the next phrase, with `waiting` more phrases queued behind it.
    public static func speed(waiting: Int) -> Double {
        min(maximumSpeed, 1 + stepPerPhrase * Double(max(0, waiting)))
    }
}

/// "headphones" A (#238): any headphones, Bluetooth or wired; never the iPhone's speaker. Takes
/// `AVAudioSession.Port` raw values, so it's tested without a device.
public enum EarRoute {
    private static let inTheEar: Set<String> = ["Headphones", "BluetoothA2DPOutput", "BluetoothLE", "BluetoothHFP", "USBAudio"]

    /// Whether the voice can play now: there's an output, and every output is in someone's ears.
    public static func canSpeak(outputs: [String]) -> Bool {
        !outputs.isEmpty && outputs.allSatisfy(inTheEar.contains)
    }
}

/// What "Speak it in my ear" is doing, for its note in Settings and for whether anything is spoken.
public enum EarState: Equatable, Sendable {
    case off
    /// On, but the translation language has no voice on this device (Serbian): captions only ("novoice" A).
    case noVoice
    /// On, with a voice, but no headphones connected: nothing is spoken, captions carry on.
    case noHeadphones
    case speaking

    public init(on: Bool, hasVoice: Bool, headphones: Bool) {
        self = !on ? .off : !hasVoice ? .noVoice : !headphones ? .noHeadphones : .speaking
    }

    public var speaks: Bool { self == .speaking }
}

/// "screen" A (#238): the line being spoken firms up as the voice says it. The translation shown isn't word for word
/// with what was said, so the share of the line said so far is laid over the shown words.
public enum EarProgress {
    /// How many of the `shown` translated words to draw firm, with the voice `share` (0...1) of the way through the
    /// phrase covering `phrase` of the line's `lineWords` words.
    public static func firmWords(shown: Int, lineWords: Int, phrase: Range<Int>, share: Double) -> Int {
        guard lineWords > 0, shown > 0 else { return max(0, shown) }
        let s = min(1, max(0, share))
        let said = Double(min(phrase.lowerBound, lineWords)) + s * Double(min(phrase.count, max(0, lineWords - phrase.lowerBound)))
        return min(shown, max(0, Int((Double(shown) * said / Double(lineWords)).rounded())))
    }
}

/// How the iPhone's audio is set up for listening (ADR 0021). With the ear on ("mic" C, #238): play and record, the
/// headphones over A2DP only (no call profile, so the voice keeps its quality), never the speaker, and the iPhone's own
/// mic even when a wired headset has one. Off, it's what it always was.
public struct MicSessionSetup: Equatable, Sendable {
    public enum Category: Sendable { case record, playAndRecord }
    public enum Mode: Sendable { case `default`, measurement }

    public let category: Category
    public let mode: Mode
    public let defaultToSpeaker: Bool
    public let allowsBluetoothA2DP: Bool
    public let prefersBuiltInMic: Bool

    public init(category: Category, mode: Mode, defaultToSpeaker: Bool, allowsBluetoothA2DP: Bool, prefersBuiltInMic: Bool) {
        self.category = category
        self.mode = mode
        self.defaultToSpeaker = defaultToSpeaker
        self.allowsBluetoothA2DP = allowsBluetoothA2DP
        self.prefersBuiltInMic = prefersBuiltInMic
    }

    public init(micMode: MicMode, speaksIntoEar: Bool) {
        let mode: Mode = micMode == .raw ? .measurement : .default
        if speaksIntoEar {
            self.init(category: .playAndRecord, mode: mode, defaultToSpeaker: false, allowsBluetoothA2DP: true, prefersBuiltInMic: true)
        } else if micMode == .voiceProcessing {
            self.init(category: .playAndRecord, mode: mode, defaultToSpeaker: true, allowsBluetoothA2DP: false, prefersBuiltInMic: false)
        } else {
            self.init(category: .record, mode: mode, defaultToSpeaker: false, allowsBluetoothA2DP: false, prefersBuiltInMic: false)
        }
    }
}

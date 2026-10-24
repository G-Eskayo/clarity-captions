import FluidAudio
import Foundation

/// One recognized word with its audio span, in seconds since the first fed sample (the same clock as the diarizer).
public struct TimedWord: Sendable, Equatable {
    public let text: String
    public let start: Double
    public let end: Double
    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Parakeet's sub-word tokens to words, using FluidAudio's own merger (`▁` starts a word), shifted from window time
/// to session time.
public enum ParakeetWords {
    public static func words(from tokens: [TokenTiming], windowStart: Double) -> [TimedWord] {
        buildWordTimings(from: tokens).map {
            TimedWord(text: $0.word, start: windowStart + $0.startTime, end: windowStart + $0.endTime)
        }
    }
}

/// Committed tail-window decoding (design §2). Parakeet is an offline model, so the app re-decodes the recent audio
/// every hop and this decides which words are settled. A word is final when two consecutive decodes agree on it in
/// the same place after the last final word and it ends `stabilityMargin` before the newest audio
/// (LocalAgreement-2). Finals only ever grow, as a prefix. Pure: no model, no clock.
///
/// Space O(words in one window). Time O(words in the window) per decode.
public struct TailCommitter: Sendable {
    public struct Config: Sendable {
        /// Audio decoded before the commit point, so the first open word has acoustic context.
        public var leftContext = 1.0
        public var stabilityMargin = 0.6
        /// Uncommitted audio that forces a commit, under the encoder's 15 s input.
        public var maxUncommitted = 12.0
        /// What a forced commit (or silence) leaves open.
        public var forceKeep = 2.0
        /// Longest window ever asked for.
        public var maxWindow = 14.5
        public init() {}
    }

    public let config: Config
    /// End of the last final word (or of silence let go). Words centred before it belong to the past.
    public private(set) var commitPoint = 0.0
    /// The last decode's open words, to agree with.
    private var pending: [TimedWord] = []
    /// The newest final word: a re-decode of it with shifted timing must not pass as a new word.
    private var lastFinal: TimedWord?

    public init(config: Config = Config()) { self.config = config }

    /// Where the next decode's window should start, for audio heard up to `audioEnd`.
    public func windowStart(audioEnd: Double) -> Double {
        max(0, commitPoint - config.leftContext, audioEnd - config.maxWindow)
    }

    /// Takes one decode of `[windowStart, audioEnd]` (word times relative to `windowStart`) and returns the words
    /// that just became final and the words still open.
    public mutating func ingest(decode: [TimedWord], windowStart: Double, audioEnd: Double) -> (final: [TimedWord], volatile: [TimedWord]) {
        let open = openWords(decode, windowStart: windowStart)
        var count = 0
        while count < open.count, count < pending.count, open[count].text == pending[count].text,
              open[count].end <= audioEnd - config.stabilityMargin {
            count += 1
        }
        if audioEnd - commitPoint >= config.maxUncommitted {
            while count < open.count, open[count].end <= audioEnd - config.forceKeep { count += 1 }
        }
        let final = Array(open[..<count])
        let rest = Array(open[count...])
        if let last = final.last { commitPoint = last.end; lastFinal = last }
        if rest.isEmpty || audioEnd - commitPoint >= config.maxUncommitted {
            // Nothing open (silence), or still too much: let go of audio no open word starts in.
            commitPoint = max(commitPoint, min(audioEnd - config.forceKeep, rest.first?.start ?? .infinity))
        }
        pending = rest
        return (final, rest)
    }

    /// On stop: the last decode's open words all become final.
    public mutating func finish(decode: [TimedWord], windowStart: Double) -> [TimedWord] {
        let open = openWords(decode, windowStart: windowStart)
        if let last = open.last { commitPoint = last.end; lastFinal = last }
        pending = []
        return open
    }

    private func openWords(_ decode: [TimedWord], windowStart: Double) -> [TimedWord] {
        decode.compactMap { word in
            let absolute = TimedWord(text: word.text, start: windowStart + word.start, end: windowStart + word.end)
            if (absolute.start + absolute.end) / 2 < commitPoint { return nil }
            if let lastFinal, absolute.text == lastFinal.text, absolute.start < lastFinal.end { return nil }
            return absolute
        }
    }
}

/// How long to wait between Parakeet decodes (design §2, D7). Slow decodes stretch the hop instead of queueing work;
/// serious heat doubles it.
public enum AdaptiveHop {
    public static let floor = 0.5
    public static let ceiling = 1.5

    public static func next(decodeTimes: [Double], thermal: ProcessInfo.ThermalState) -> Double {
        let recent = decodeTimes.suffix(5).filter { $0.isFinite && $0 >= 0 }.sorted()
        let median = recent.isEmpty ? 0 : (recent.count % 2 == 1
            ? recent[recent.count / 2]
            : (recent[recent.count / 2 - 1] + recent[recent.count / 2]) / 2)
        let hop = min(ceiling, max(floor, 1.3 * median))
        return thermal == .serious ? hop * 2 : hop
    }
}

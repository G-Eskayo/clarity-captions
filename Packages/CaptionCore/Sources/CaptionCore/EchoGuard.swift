// Moved from the #233 spike (Packages/EarSpike, PR #237) so the app can use it.
import Foundation

/// Tells a caption of the app's own spoken translation (picked up by the phone's mic, #233) from real speech.
/// A finished caption line is echo when it overlaps a time the app was speaking, plus a short room tail, **and** most
/// of its words are words the app said. Time alone would drop the other person's words spoken over the voice; words
/// alone would drop someone repeating a phrase later. "Words the app said" also counts letters: the caption engine
/// hears a foreign voice as sound-alike nonsense whose word breaks move, so letter trigrams back up whole words.
/// Times are seconds on one clock (audio time or uptime).
public struct EchoGuard: Sendable {
    private struct Utterance: Sendable {
        let words: Set<String>; let trigrams: Set<String>; let start: Double; let end: Double
    }
    private var spoken: [Utterance] = []
    public let tail: Double
    public let threshold: Double
    /// Share of the caption's letter trigrams the app said. 0.35: 71 of 105 simulated echoes, 1 false echo in 600
    /// real lines (echo-fingerprint-mac.json), tuned on that same set.
    public let letterThreshold: Double

    public init(tail: Double = 0.8, threshold: Double = 0.6, letterThreshold: Double = 0.35) {
        self.tail = tail
        self.threshold = threshold
        self.letterThreshold = letterThreshold
    }

    public var count: Int { spoken.count }

    /// The app said `text` out loud from `start` to `end`. `heardAs` is what the caption engine made of the app's own
    /// rendered voice before it played: in the other person's language that's sound-alike nonsense, not `text`.
    public mutating func spoke(_ text: String, heardAs: String? = nil, from start: Double, to end: Double) {
        let words = Set(Self.words(text)).union(Self.words(heardAs ?? ""))
        let trigrams = Self.trigrams(text).union(Self.trigrams(heardAs ?? ""))
        spoken.append(Utterance(words: words, trigrams: trigrams, start: start, end: end))
    }

    /// Drops what ended before `time` (minus the tail): it can't overlap anything new.
    public mutating func forget(before time: Double) {
        spoken.removeAll { $0.end + tail < time }
    }

    public func isEcho(_ caption: String, from start: Double, to end: Double) -> Bool {
        let words = Self.words(caption)
        guard words.count >= 2 else { return false }
        let letters = Self.trigrams(caption)
        return spoken.contains { u in
            start <= u.end + tail && end >= u.start
                && (Self.share(of: words, in: u.words) >= threshold
                    || Self.share(of: Array(letters), in: u.trigrams) >= letterThreshold)
        }
    }

    /// The share of the caption's words that are among the spoken words, 0...1.
    public static func similarity(caption: String, spoken: String) -> Double {
        share(of: words(caption), in: Set(words(spoken)))
    }

    /// The share of the caption's letter trigrams (spaces dropped) that are among the spoken ones, 0...1.
    public static func soundsLike(caption: String, spoken: String) -> Double {
        share(of: Array(trigrams(caption)), in: trigrams(spoken))
    }

    static func trigrams(_ text: String) -> Set<String> {
        let letters = Array(words(text).joined())
        guard letters.count >= 3 else { return [] }
        return Set((0...(letters.count - 3)).map { String(letters[$0..<($0 + 3)]) })
    }

    private static func share(of words: [String], in spoken: Set<String>) -> Double {
        guard !words.isEmpty else { return 0 }
        return Double(words.filter(spoken.contains).count) / Double(words.count)
    }

    /// Lowercased words with accents and punctuation removed, so "¿Dónde?" and "donde" agree.
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

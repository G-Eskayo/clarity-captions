import Foundation

/// Tells a caption of the app's own spoken translation (picked up by the phone's mic, #233) from real speech.
/// A finished caption line is echo when it overlaps a time the app was speaking, plus a short room tail, **and** most
/// of its words are words the app said. Time alone would drop the other person's words spoken over the voice; words
/// alone would drop someone repeating a phrase later. Times are seconds on one clock (audio time or uptime).
public struct EchoGuard: Sendable {
    private struct Utterance: Sendable { let words: Set<String>; let start: Double; let end: Double }
    private var spoken: [Utterance] = []
    public let tail: Double
    public let threshold: Double

    public init(tail: Double = 0.8, threshold: Double = 0.6) {
        self.tail = tail
        self.threshold = threshold
    }

    public var count: Int { spoken.count }

    /// The app said `text` out loud from `start` to `end`.
    public mutating func spoke(_ text: String, from start: Double, to end: Double) {
        spoken.append(Utterance(words: Set(Self.words(text)), start: start, end: end))
    }

    /// Drops what ended before `time` (minus the tail): it can't overlap anything new.
    public mutating func forget(before time: Double) {
        spoken.removeAll { $0.end + tail < time }
    }

    public func isEcho(_ caption: String, from start: Double, to end: Double) -> Bool {
        let words = Self.words(caption)
        guard words.count >= 2 else { return false }
        return spoken.contains { u in
            start <= u.end + tail && end >= u.start && Self.share(of: words, in: u.words) >= threshold
        }
    }

    /// The share of the caption's words that are among the spoken words, 0...1.
    public static func similarity(caption: String, spoken: String) -> Double {
        share(of: words(caption), in: Set(words(spoken)))
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

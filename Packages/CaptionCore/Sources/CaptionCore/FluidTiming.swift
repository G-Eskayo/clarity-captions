import Foundation

/// Every fade's timing in one place (owner, 2026-10-20: "I want it all to be more fluid"). Still fades only, never
/// slides (spec "Round 2"). The app draws them with SwiftUI's smooth curve, which carries on from wherever a fade is
/// when it's interrupted instead of jumping.
public enum FluidTiming {
    /// Dims, questions, hints, the tour's words.
    public static func fade(reduceMotion: Bool) -> Double { reduceMotion ? 0.2 : 0.35 }
    /// Small things: [ Copy ], a selection clearing, a word changing inside its brackets.
    public static func quick(reduceMotion: Bool) -> Double { reduceMotion ? 0.12 : 0.22 }

    /// A page change: the next page starts fading in while the last one is still fading out, so the screen is never
    /// blank in between (round 2 faded out fully, then in).
    public struct Page: Equatable, Sendable {
        public let out: Double
        public let inDelay: Double
        public let `in`: Double
        public var total: Double { max(out, inDelay + `in`) }
    }

    public static func page(reduceMotion: Bool) -> Page {
        reduceMotion ? Page(out: 0.15, inDelay: 0.05, in: 0.2) : Page(out: 0.24, inDelay: 0.1, in: 0.32)
    }

    /// A dim with words on it ([ Save ] / [ New ], [ Share ] / [ Delete ]). Going away, the words leave first and the
    /// dim lifts more slowly, so the text under it comes up gradually; coming back, the dim lands first and the words
    /// follow. Fading both together made the dim seem to vanish in one frame while the words lingered (owner, "choppy").
    public struct Dim: Equatable, Sendable {
        public let dim: Double
        public let words: Double
        public let wordsInDelay: Double
        public let dimOutDelay: Double
    }

    public static func dim(reduceMotion: Bool) -> Dim {
        reduceMotion ? Dim(dim: 0.2, words: 0.12, wordsInDelay: 0.08, dimOutDelay: 0.04)
                     : Dim(dim: 0.45, words: 0.2, wordsInDelay: 0.18, dimOutDelay: 0.08)
    }

    /// A single small word changing (the status row, the word inside [ ]): out, then in. A crossfade of two words in
    /// one spot reads as a smear at that size.
    public static func wordSwap(reduceMotion: Bool) -> (out: Double, inDelay: Double, in: Double) {
        reduceMotion ? (0.08, 0.06, 0.1) : (0.12, 0.1, 0.18)
    }

    /// The Start pill's label waits this long before fading in as the circle sweeps back into a pill, so a half-grown
    /// pill never shows a clipped "rt captions".
    public static let pillLabelInDelay: Double = 0.3

    /// [ ✔ ] stays this long, then eases into [ Saved ].
    public static let saveCheckHold: Double = 0.7
    /// The whole [ Save ] → [ ✔ ] → [ Saved ] moment; the tour's "Saved." waits for it (#121).
    public static let saveMoment: Double = 1.05
}

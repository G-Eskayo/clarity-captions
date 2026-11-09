import Foundation
import NaturalLanguage

/// Owner's note on PR #231: a Spanish speaker beside her, a French speaker on the call, and people speaking several
/// languages on one call. Each finished line goes to the translator for the language its words are in, among the
/// languages its side can be in (`MacTranslation.languages(for:)`, all set up beforehand):
///
/// - **Sure** (4+ words, 99% sure: the face-to-face rule measured in #60 and #208, `LanguageMatchPolicy`): that
///   language. Her language: left alone, wherever the line came from. A language nobody set up: shown as said, since
///   nothing downloads mid-call.
/// - **Unsure** (a short line, mixed words): the language its voice was last sure of, else the side's own From.
/// - Her own lines (a headset's mic on a call), lines whose side isn't known, unfinished lines, sound labels and lines
///   with no letters: never translated.
///
/// Each finished line is worked out once (the translate loop asks on every update); a revised line again. Voices are
/// remembered per stream, since each stream has its own speaker model and its own numbers.
///
/// Space: O(finished lines + voices) for the session.
public struct MacTranslationRouter {
    /// A text's likeliest language (a BCP 47 language code such as "fr" or "zh-Hans") and how sure it is, 0...1.
    public typealias Guess = (String) -> (code: String, probability: Double)?

    /// Apple's NaturalLanguage, on the device: nothing to download.
    public static func naturalLanguage(_ text: String) -> (code: String, probability: Double)? {
        guard text.contains(where: \.isLetter) else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, p) = recognizer.languageHypotheses(withMaximum: 1).first else { return nil }
        return (language.rawValue, p)
    }

    private enum Verdict: Equatable {
        case language(Locale)
        /// Sure of a language not set up for this side.
        case other
    }

    private struct VoiceKey: Hashable { let side: MacAudioSide; let speaker: Int }

    public let translation: MacTranslation
    private let guess: Guess
    private let minWords: Int
    private let sureProbability: Double
    private var voices: [VoiceKey: Verdict] = [:]
    private var decided: [Int: (text: String, side: MacAudioSide, pair: MacTranslation.Pair?)] = [:]

    public init(_ translation: MacTranslation, policy: LanguageMatchPolicy = LanguageMatchPolicy(),
                guess: @escaping Guess = MacTranslationRouter.naturalLanguage) {
        self.translation = translation
        self.guess = guess
        minWords = policy.minWords
        sureProbability = policy.lockProbability
    }

    /// The translator for one line, or nil when it is shown as said.
    public mutating func pair(for line: CaptionLine, side: MacAudioSide) -> MacTranslation.Pair? {
        guard line.isFinal, !line.isSoundLabel else { return nil }
        let text = line.text
        if let d = decided[line.id], d.text == text, d.side == side { return d.pair }
        let p = decide(text, side: side, speaker: line.speaker)
        decided[line.id] = (text, side, p)
        return p
    }

    /// The lines a pair's translator takes, in order. A line whose side isn't known is left alone: better untranslated
    /// than her own words translated by mistake.
    public mutating func lines(_ lines: [CaptionLine], for pair: MacTranslation.Pair,
                               side: (CaptionLine) -> MacAudioSide?) -> [CaptionLine] {
        lines.filter { line in
            guard let s = side(line), let p = self.pair(for: line, side: s) else { return false }
            return MacTranslation.samePair(p, pair)
        }
    }

    private mutating func decide(_ text: String, side: MacAudioSide, speaker: Int?) -> MacTranslation.Pair? {
        let languages = translation.languages(for: side)
        guard let own = languages.first, text.contains(where: \.isLetter) else { return nil }
        let key = speaker.map { VoiceKey(side: side, speaker: $0) }
        let verdict: Verdict
        if let sure = sureVerdict(text, among: languages) {
            verdict = sure
            if let key { voices[key] = sure }
        } else {
            verdict = key.flatMap { voices[$0] } ?? .language(own)
        }
        guard case .language(let from) = verdict, !MacTranslation.sameLanguage(from, translation.into) else { return nil }
        return MacTranslation.Pair(from: from, into: translation.into)
    }

    /// Sure of the words' language, or nil.
    private func sureVerdict(_ text: String, among languages: [Locale]) -> Verdict? {
        guard Self.wordCount(text) >= minWords, let g = guess(text), !g.code.isEmpty,
              g.probability.isFinite, g.probability >= sureProbability, g.probability <= 1 else { return nil }
        let said = Locale(identifier: g.code)
        guard said.language.languageCode != nil else { return .other }
        return languages.first { MacTranslation.sameLanguage($0, said) }.map(Verdict.language) ?? .other
    }

    /// Words as the language sees them, so Japanese and Chinese (no spaces) count properly.
    static func wordCount(_ text: String) -> Int {
        var n = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in n += 1 }
        return n
    }
}

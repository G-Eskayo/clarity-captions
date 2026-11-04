import Accelerate
import Foundation

// #247 part 1: how each speaker sounds (pitch and pace), measured from the audio the app already captures. Pure, no
// AVFoundation, so it is tested with made-up signals and can move into CaptionCore unchanged.

/// The voice's pitch (fundamental), frame by frame: YIN (de Cheveigné & Kawahara 2002), 25 ms window, 10 ms hop.
public enum PitchTracker {
    public static let minimumHz = 60.0
    public static let maximumHz = 400.0
    public static let hopSeconds = 0.01
    static let windowSeconds = 0.025
    static let threshold = 0.15
    /// Quieter than this (about -50 dBFS) is not judged.
    static let quietRMS: Float = 0.003

    /// One value per 10 ms: the pitch in Hz, or nil where it's quiet, unvoiced (noise, "s", "f") or out of range.
    public static func track(_ input: [Float], sampleRate: Double) -> [Double?] {
        guard sampleRate >= 4000, sampleRate.isFinite else { return [] }
        // Above 16 kHz, average down (a crude low-pass) to keep the cost flat: a voice's pitch is far below 8 kHz.
        let factor = max(1, Int(sampleRate / 16000))
        let rate = sampleRate / Double(factor)
        let x = clean(input, decimate: factor)
        let w = Int(windowSeconds * rate), tauMax = Int((rate / minimumHz).rounded(.up))
        let tauMin = Int((rate / maximumHz).rounded(.down))
        let hop = max(1, Int(hopSeconds * rate))
        guard x.count >= w + tauMax else { return [] }
        var frames: [Double?] = []
        frames.reserveCapacity((x.count - w - tauMax) / hop + 1)
        var d = [Double](repeating: 0, count: tauMax + 1)
        var start = 0
        while start + w + tauMax <= x.count {
            defer { start += hop }
            let loud: Bool = x.withUnsafeBufferPointer { p in
                var energy: Float = 0
                vDSP_svesq(p.baseAddress! + start, 1, &energy, vDSP_Length(w))
                return (energy / Float(w)).squareRoot() >= quietRMS
            }
            guard loud else { frames.append(nil); continue }
            // Difference function and its cumulative-mean normalisation, from a lag of 1 (so a whistle above the
            // range is seen as one, not as its own subharmonic).
            x.withUnsafeBufferPointer { p in
                let base = p.baseAddress! + start
                var running = 0.0
                d[0] = 1
                for tau in 1...tauMax {
                    var s: Float = 0
                    vDSP_distancesq(base, 1, base + tau, 1, &s, vDSP_Length(w))
                    running += Double(s)
                    d[tau] = running > 0 ? Double(s) * Double(tau) / running : 1
                }
            }
            var found: Int?
            var tau = 2
            while tau < tauMax {
                if d[tau] < threshold {
                    while tau + 1 < tauMax && d[tau + 1] < d[tau] { tau += 1 }
                    found = tau
                    break
                }
                tau += 1
            }
            guard let t = found, t >= tauMin else { frames.append(nil); continue }
            // Parabolic interpolation around the dip.
            let a = d[t - 1], b = d[t], c = d[t + 1]
            let shift = (a - 2 * b + c) != 0 ? 0.5 * (a - c) / (a - 2 * b + c) : 0
            let hz = rate / (Double(t) + max(-0.5, min(0.5, shift)))
            frames.append(hz >= minimumHz && hz <= maximumHz && hz.isFinite ? hz : nil)
        }
        return frames
    }

    static func clean(_ input: [Float], decimate factor: Int) -> [Float] {
        let safe = input.map { $0.isFinite ? max(-1, min(1, $0)) : 0 }
        guard factor > 1 else { return safe }
        return stride(from: 0, to: safe.count - factor + 1, by: factor).map { i in
            var s: Float = 0
            for k in 0..<factor { s += safe[i + k] }
            return s / Float(factor)
        }
    }
}

/// Speaking pace: syllable nuclei per second of speech, pauses left out (articulation rate). Loudness peaks that
/// stand at least 2 dB above the dips on either side and are voiced, after de Jong & Wempe (2009).
public enum SyllableRate {
    public struct Result: Equatable, Sendable {
        public let syllables: Int
        public let speechSeconds: Double
        public var perSecond: Double? { syllables > 0 && speechSeconds > 0.3 ? Double(syllables) / speechSeconds : nil }
    }

    static let frameSeconds = 0.01
    /// Within this many dB of the loudest moment counts as speech.
    static let speechRangeDb = 25.0
    static let floorDb = -50.0
    static let prominenceDb = 2.0
    /// A gap shorter than this is part of talking; longer is a pause.
    static let pauseSeconds = 0.3

    public static func measure(_ input: [Float], sampleRate: Double, pitch: [Double?]? = nil) -> Result {
        let none = Result(syllables: 0, speechSeconds: 0)
        guard sampleRate >= 4000, sampleRate.isFinite else { return none }
        let n = Int(frameSeconds * sampleRate)
        guard n > 0, input.count >= n * 3 else { return none }
        let x = PitchTracker.clean(input, decimate: 1)
        var db: [Double] = stride(from: 0, to: x.count - n + 1, by: n).map { i in
            var s: Float = 0
            for j in i..<(i + n) { s += x[j] * x[j] }
            return 20 * log10(Double((s / Float(n)).squareRoot()) + 1e-9)
        }
        // Smooth over 30 ms.
        db = db.indices.map { i in
            let lo = max(0, i - 1), hi = min(db.count - 1, i + 1)
            return db[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
        guard let loudest = db.max(), loudest > floorDb else { return none }
        let cut = max(floorDb, loudest - speechRangeDb)
        let voiced = pitch ?? PitchTracker.track(input, sampleRate: sampleRate)

        // Speech time: frames above the cut, with gaps shorter than a pause bridged.
        let longestGap = Int(pauseSeconds / frameSeconds)
        var speechFrames = 0, gap = 0, seen = false
        for l in db.map({ $0 >= cut }) {
            if l {
                if seen && gap <= longestGap { speechFrames += gap }
                speechFrames += 1; gap = 0; seen = true
            } else if seen { gap += 1 }
        }

        var count = 0
        for i in 1..<(db.count - 1) where db[i] >= cut && db[i] > db[i - 1] && db[i] >= db[i + 1] {
            // Prominence: the deepest dip before reaching something louder, on each side.
            var left = db[i], j = i - 1
            while j >= 0 && db[j] <= db[i] { left = min(left, db[j]); j -= 1 }
            var right = db[i], k = i + 1
            while k < db.count && db[k] <= db[i] { right = min(right, db[k]); k += 1 }
            // A tie (a flat plateau) is counted once, at its first frame.
            if k < db.count && db[k] == db[i] { continue }
            guard db[i] - left >= prominenceDb, db[i] - right >= prominenceDb else { continue }
            let near = (max(0, i - 2)...min(voiced.count - 1, i + 2))
            guard !voiced.isEmpty, near.lowerBound <= near.upperBound, near.contains(where: { voiced[$0] != nil }) else { continue }
            count += 1
        }
        return Result(syllables: count, speechSeconds: Double(speechFrames) * frameSeconds)
    }
}

/// Syllables in a line of text, by rule of thumb: vowel groups in Latin, Greek and Cyrillic script (English drops a
/// silent final e), one per character in Chinese, Japanese and Korean. Nil for text it can't judge, such as Hebrew
/// or Arabic written without vowels, or no words at all.
public enum TextSyllables {
    public static func count(_ text: String, language: String? = nil) -> Int? {
        let english = language.map { $0.hasPrefix("en") } ?? false
        var total = 0
        var any = false
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }) {
            let letters = word.filter(\.isLetter)
            guard !letters.isEmpty else { continue }
            if letters.unicodeScalars.allSatisfy(isSyllabic) { total += letters.count; any = true; continue }
            guard letters.unicodeScalars.allSatisfy(isAlphabetic) else { return nil }
            let chars = Array(letters)
            var groups = 0
            var inVowel = false
            for (i, c) in chars.enumerated() {
                let v = vowels.contains(c) || (c == "y" && i > 0)
                if v && !inVowel { groups += 1 }
                inVowel = v
            }
            if english, groups > 1, chars.last == "e", chars.count >= 3 {
                let before = chars[chars.count - 2]
                if !vowels.contains(before) && !(before == "l" && !vowels.contains(chars[chars.count - 3])) { groups -= 1 }
            }
            total += max(1, groups)
            any = true
        }
        return any ? total : nil
    }

    static let vowels: Set<Character> = Set("aeiouáéíóúàèìòùâêîôûäëïöüåæøœãõıаеёиоуыэюяαεηιουωάέήίόύώ")

    static func isAlphabetic(_ u: Unicode.Scalar) -> Bool {
        (0x0041...0x024F).contains(u.value) || (0x0370...0x03FF).contains(u.value) || (0x0400...0x04FF).contains(u.value)
    }

    /// Kana, CJK ideographs and Hangul syllables: about one syllable each.
    static func isSyllabic(_ u: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(u.value) || (0x4E00...0x9FFF).contains(u.value) || (0x3400...0x4DBF).contains(u.value)
            || (0xAC00...0xD7AF).contains(u.value)
    }
}

/// What the voice in your ear is matched to.
public struct SpeakerTraits: Codable, Equatable, Sendable {
    public let pitchHz: Double
    public let syllablesPerSecond: Double
    public init(pitchHz: Double, syllablesPerSecond: Double) {
        self.pitchHz = pitchHz; self.syllablesPerSecond = syllablesPerSecond
    }
    var isUsable: Bool {
        pitchHz.isFinite && syllablesPerSecond.isFinite && pitchHz > 0 && syllablesPerSecond > 0
    }
}

/// One speaker's voice, built up as they talk. Audio is judged in 2-second pieces (a syllable cut at a piece's edge
/// costs at most one), and only the last 30 s or so count, so a long talk stays small in memory.
public struct SpeakerProfile: Sendable {
    public static let pieceSeconds = 2.0
    public static let minimumSpeechSeconds = 1.5
    static let minimumPitchFrames = 50
    public static let maximumPitchFrames = 3000
    static let rememberedSpeechSeconds = 30.0

    private var pending: [Float] = []
    private var rate: Double = 0
    private var pitches: [Double] = []
    private var syllables = 0.0
    private var speechSeconds = 0.0
    private var lineSyllables = 0.0
    private var lineSeconds = 0.0

    public init() {}

    public var storedPitchFrames: Int { pitches.count }

    public mutating func add(_ samples: [Float], sampleRate: Double) {
        guard sampleRate >= 4000, sampleRate.isFinite else { return }
        if sampleRate != rate { pending.removeAll(); rate = sampleRate }
        pending += samples
        let piece = Int(Self.pieceSeconds * rate)
        while pending.count >= piece {
            judge(Array(pending[0..<piece]))
            pending.removeFirst(piece)
        }
    }

    private mutating func judge(_ piece: [Float]) {
        let f0 = PitchTracker.track(piece, sampleRate: rate)
        let pace = SyllableRate.measure(piece, sampleRate: rate, pitch: f0)
        pitches += f0.compactMap { $0 }
        if pitches.count > Self.maximumPitchFrames { pitches.removeFirst(pitches.count - Self.maximumPitchFrames) }
        syllables += Double(pace.syllables)
        speechSeconds += pace.speechSeconds
        if speechSeconds > Self.rememberedSpeechSeconds {
            let keep = Self.rememberedSpeechSeconds / speechSeconds
            syllables *= keep; speechSeconds *= keep
        }
    }

    /// A finished caption line of theirs and how long they spoke it (pauses left out): pace from the words, which
    /// is steadier than counting loudness peaks. Used once there's a second of it.
    public mutating func addLine(_ text: String, speechSeconds seconds: Double, language: String? = nil) {
        guard seconds.isFinite, seconds > 0.2, let n = TextSyllables.count(text, language: language),
              Double(n) / seconds <= 12 else { return }
        lineSyllables += Double(n); lineSeconds += seconds
        if lineSeconds > Self.rememberedSpeechSeconds {
            let keep = Self.rememberedSpeechSeconds / lineSeconds
            lineSyllables *= keep; lineSeconds *= keep
        }
    }

    /// Nil until there's enough voiced speech to judge (about two seconds of talk).
    public var traits: SpeakerTraits? {
        guard speechSeconds >= Self.minimumSpeechSeconds, pitches.count >= Self.minimumPitchFrames else { return nil }
        let pace = lineSeconds >= 1 ? lineSyllables / lineSeconds : speechSeconds > 0 && syllables > 0 ? syllables / speechSeconds : 0
        guard pace > 0 else { return nil }
        // The median in semitones is the median in Hz; a laugh or a squeak doesn't pull it.
        let sorted = pitches.sorted()
        return SpeakerTraits(pitchHz: sorted[sorted.count / 2], syllablesPerSecond: pace)
    }
}

/// A measured point: what was set (rate, pitch multiplier) and what came out (syllables per second, Hz).
public struct CalibrationPoint: Codable, Equatable, Sendable {
    public let input: Double
    public let value: Double
    public init(_ input: Double, _ value: Double) { self.input = input; self.value = value }

    /// Linear between measured points, held at the ends.
    public static func value(at x: Double, in curve: [CalibrationPoint]) -> Double? {
        let c = curve.filter { $0.input.isFinite && $0.value.isFinite }.sorted { $0.input < $1.input }
        guard let first = c.first, let last = c.last, x.isFinite else { return nil }
        if x <= first.input { return first.value }
        if x >= last.input { return last.value }
        let i = c.firstIndex { $0.input >= x }!
        let a = c[i - 1], b = c[i]
        return a.value + (b.value - a.value) * (x - a.input) / (b.input - a.input)
    }

    /// The setting that gives `y`, assuming more input gives more output; clamped to the measured range.
    public static func input(for y: Double, in curve: [CalibrationPoint]) -> Double? {
        let c = curve.filter { $0.input.isFinite && $0.value.isFinite }.sorted { $0.value < $1.value }
        guard let first = c.first, let last = c.last, y.isFinite else { return nil }
        if y <= first.value { return first.input }
        if y >= last.value { return last.input }
        let i = c.firstIndex { $0.value >= y }!
        let a = c[i - 1], b = c[i]
        return b.value == a.value ? a.input : a.input + (b.input - a.input) * (y - a.value) / (b.value - a.value)
    }
}

/// One installed voice, measured once at setup (when the voice is warmed up in Settings): its own pitch and pace,
/// and how `AVSpeechUtterance.rate` and `pitchMultiplier` really move them.
public struct VoiceCalibration: Codable, Equatable, Sendable {
    public let id: String
    public let pitchHz: Double
    public let syllablesPerSecond: Double
    public let rateCurve: [CalibrationPoint]
    public let pitchCurve: [CalibrationPoint]
    public init(id: String, pitchHz: Double, syllablesPerSecond: Double, rateCurve: [CalibrationPoint],
                pitchCurve: [CalibrationPoint]) {
        self.id = id; self.pitchHz = pitchHz; self.syllablesPerSecond = syllablesPerSecond
        self.rateCurve = rateCurve; self.pitchCurve = pitchCurve
    }
}

/// What to set on the utterance for one speaker.
public struct MatchedVoice: Codable, Equatable, Sendable {
    public let voiceID: String?
    public let pitchMultiplier: Float
    public let rate: Float
    public init(voiceID: String?, pitchMultiplier: Float, rate: Float) {
        self.voiceID = voiceID; self.pitchMultiplier = pitchMultiplier; self.rate = rate
    }

    /// With the voice catching up (EarPace, #238) on top: the same 1.3x cap the app has today.
    public func rate(catchUp: Double) -> Float {
        min(VoiceMatch.maximumRateWithCatchUp, rate * Float(max(1, catchUp.isFinite ? catchUp : 1)))
    }
}

public enum VoiceMatch {
    /// AVSpeechUtteranceDefaultSpeechRate.
    public static let defaultRate: Float = 0.5
    /// About ±4 semitones: further and Apple's voices start to sound processed.
    public static let pitchMultiplierRange: ClosedRange<Float> = 0.8...1.25
    public static let rateRange: ClosedRange<Float> = 0.42...0.6
    /// The app's catch-up cap today (default rate × EarPace.maximumSpeed).
    public static let maximumRateWithCatchUp: Float = 0.65
    public static let maximumShiftSemitones = 4.0
    /// Two speakers on one voice are kept at least this far apart, so they can be told apart.
    public static let minimumSemitonesApart = 2.0
    /// A second voice further than this from a speaker (a man's voice for a woman) isn't used just to sound different.
    public static let closeVoiceSemitones = 7.0

    static func semitones(_ a: Double, _ b: Double) -> Double { 12 * log2(a / b) }

    /// One setting per speaker, in the order given (first heard first). A nil speaker (not enough speech yet) and
    /// broken numbers get today's voice: `defaultVoiceID`, unchanged pitch and rate.
    public static func match(_ speakers: [SpeakerTraits?], voices: [VoiceCalibration], normalSyllablesPerSecond: Double,
                             defaultVoiceID: String? = nil) -> [MatchedVoice] {
        let fallback = MatchedVoice(voiceID: defaultVoiceID ?? voices.first?.id, pitchMultiplier: 1, rate: defaultRate)
        let usable = voices.filter { $0.pitchHz > 0 && $0.pitchHz.isFinite }
        var used: [String: [Double]] = [:]  // voice -> the shifts (semitones) its speakers have
        return speakers.map { speaker in
            guard let s = speaker, s.isUsable, !usable.isEmpty else { return fallback }
            let byDistance = usable.sorted { abs(semitones(s.pitchHz, $0.pitchHz)) < abs(semitones(s.pitchHz, $1.pitchHz)) }
            let voice = byDistance.first { used[$0.id] == nil && abs(semitones(s.pitchHz, $0.pitchHz)) <= closeVoiceSemitones }
                ?? byDistance[0]

            var shift = max(-maximumShiftSemitones, min(maximumShiftSemitones, semitones(s.pitchHz, voice.pitchHz)))
            for _ in 0..<4 {
                guard let clash = used[voice.id]?.first(where: { abs($0 - shift) < minimumSemitonesApart - 1e-9 }) else { break }
                let up = shift >= clash
                let moved = clash + (up ? minimumSemitonesApart : -minimumSemitonesApart)
                // At the edge of the range, go the other way.
                shift = abs(moved) <= maximumShiftSemitones ? moved : clash + (up ? -minimumSemitonesApart : minimumSemitonesApart)
            }
            used[voice.id, default: []].append(shift)
            let targetHz = voice.pitchHz * pow(2, shift / 12)
            let multiplier = CalibrationPoint.input(for: targetHz, in: voice.pitchCurve) ?? pow(2, shift / 12)

            var rate = defaultRate
            if normalSyllablesPerSecond > 0, normalSyllablesPerSecond.isFinite, voice.syllablesPerSecond > 0,
               let r = CalibrationPoint.input(for: voice.syllablesPerSecond * s.syllablesPerSecond / normalSyllablesPerSecond,
                                              in: voice.rateCurve) {
                rate = Float(r)
            }
            return MatchedVoice(voiceID: voice.id, pitchMultiplier: clamp(Float(multiplier), pitchMultiplierRange, else: 1),
                                rate: clamp(rate, rateRange, else: defaultRate))
        }
    }

    static func clamp(_ v: Float, _ r: ClosedRange<Float>, else fallback: Float) -> Float {
        v.isFinite ? min(r.upperBound, max(r.lowerBound, v)) : fallback
    }
}

import Foundation

// "Sound like the speaker" (#247, wired by PR #254, the owner's answers "wire" A and "setting" B): the voice in your
// ear set to each speaker's pitch and pace, from the shipped calibration table. Nothing here downloads, measures a
// voice on the device or plays anything: the table was measured once on a Mac (`ear-spike calibrate`), and a voice
// not in it, or not already installed, is never used.

/// Each speaker's pitch and pace, learned from the audio of their own finished lines. The engine feeds it the 16 kHz
/// audio it already makes for the diarizer, and each finished line with its settled speaker label; the ear reads the
/// traits when it speaks. Does nothing at all unless `isRecording` (the ear and "Sound like the speaker" both on).
/// Thread-safe: audio arrives on the audio thread, lines on the results task, reads on the main actor.
public final class SpeakerVoiceRecorder: @unchecked Sendable {
    public static let shared = SpeakerVoiceRecorder()
    public static let sampleRate = 16000.0
    /// Audio kept to cut finished lines from: a line is final a few seconds after it's said (#237).
    public static let keptSeconds = 20.0
    /// Speakers beyond this aren't profiled, so memory stays bounded whatever the diarizer says.
    public static let maximumSpeakers = 8
    /// A buffer this far off where the last one ended means the clock restarted: start the kept audio again.
    static let gapTolerance = 0.25

    private let lock = NSLock()
    private var recording = false
    private var ring: [Float] = []
    private var capacity: Int { Int(Self.keptSeconds * Self.sampleRate) }
    /// Samples written since the kept audio began, and the session time of the first one.
    private var written = 0
    private var origin: Double?
    /// Audio already given to a speaker ends here, so a revised or repeated line is never counted twice.
    private var consumedUntil = -Double.infinity
    private var profiles: [Int: SpeakerProfile] = [:]
    private var lang: String?
    private var sessionCount = 0

    public init() {}

    public var isRecording: Bool {
        get { lock.withLock { recording } }
        set { lock.withLock { recording = newValue; if !newValue { clearAudio() } } }
    }

    /// The caption language of the session (pace is judged against that language's normal).
    public var language: String? { lock.withLock { lang } }
    /// Goes up at every `begin`: speaker slots belong to one session.
    public var session: Int { lock.withLock { sessionCount } }
    /// For tests: how much audio is held.
    public var storedSamples: Int { lock.withLock { ring.isEmpty ? 0 : min(written, capacity) } }

    /// A new captioning session: everyone is forgotten.
    public func begin(language: String?) {
        lock.withLock {
            clearAudio()
            profiles = [:]
            consumedUntil = -.infinity
            lang = language
            sessionCount += 1
        }
    }

    /// 16 kHz mono audio starting at `audioTime` on the session clock.
    public func feed(_ samples: [Float], at audioTime: Double) {
        guard !samples.isEmpty, audioTime.isFinite else { return }
        lock.withLock {
            guard recording else { return }
            if ring.isEmpty { ring = [Float](repeating: 0, count: capacity) }
            if let origin {
                let expected = origin + Double(written) / Self.sampleRate
                if abs(audioTime - expected) > Self.gapTolerance { written = 0; self.origin = audioTime }
            } else {
                origin = audioTime
            }
            // Longer than what's kept: only its end matters.
            let skip = max(0, samples.count - capacity)
            written += skip
            for s in samples[skip...] {
                ring[written % capacity] = s.isFinite ? s : 0
                written += 1
            }
        }
    }

    /// A finished line: its audio goes to that speaker's profile, and its words give their pace.
    public func lineFinished(speaker: Int?, text: String, start: Double?, end: Double?) {
        guard let speaker, speaker >= 0, let start, let end, start.isFinite, end.isFinite, end > start,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let cut: (samples: [Float], whole: Bool, language: String?, profile: SpeakerProfile, session: Int)? = lock.withLock {
            guard recording, let origin, written > 0 else { return nil }
            guard profiles[speaker] != nil || profiles.count < Self.maximumSpeakers else { return nil }
            let oldest = origin + Double(max(0, written - capacity)) / Self.sampleRate
            let newest = origin + Double(written) / Self.sampleRate
            let from = max(start, consumedUntil, oldest), to = min(end, newest)
            guard to - from >= 0.1 else { return nil }
            let a = Int(((from - origin) * Self.sampleRate).rounded()), b = Int(((to - origin) * Self.sampleRate).rounded())
            let samples = (a..<b).map { ring[$0 % capacity] }
            consumedUntil = to
            // Pace needs the whole line's speaking time; a clipped one would read fast.
            let whole = from <= start + 0.05 && to >= end - 0.05
            return (samples, whole, lang, profiles[speaker] ?? SpeakerProfile(), sessionCount)
        }
        guard let cut else { return }
        // The heavy part (about 2.5 ms per second of audio) outside the lock, so the audio thread never waits on it.
        // Lines come one at a time from the results task, so no other line for this speaker is in flight.
        var profile = cut.profile
        profile.add(cut.samples, sampleRate: Self.sampleRate)
        if cut.whole {
            profile.addLine(text, speechSeconds: SyllableRate.measure(cut.samples, sampleRate: Self.sampleRate).speechSeconds,
                            language: cut.language)
        }
        lock.withLock {
            // A new session started meanwhile: this speaker belonged to the old one.
            guard sessionCount == cut.session, profiles[speaker] != nil || profiles.count < Self.maximumSpeakers else { return }
            profiles[speaker] = profile
        }
    }

    /// Nil until the speaker has said about two seconds.
    public func traits(for speaker: Int?) -> SpeakerTraits? {
        guard let speaker else { return nil }
        return lock.withLock { profiles[speaker]?.traits }
    }

    private func clearAudio() {
        ring = []
        written = 0
        origin = nil
    }
}

/// A voice for each speaker, chosen once their traits are ready and kept from then on, so a voice never jumps to
/// someone else as a profile keeps learning. A speaker not ready yet (a new speaker's first early phrase), a speaker
/// with no label, or a language with no calibrated voice gets the usual voice: `defaultVoiceID`, Apple's pitch and rate.
public struct EarVoiceChooser: Sendable {
    public let voices: [VoiceCalibration]
    public let normalSyllablesPerSecond: Double?
    public let defaultVoiceID: String?
    private var order: [Int] = []
    private var frozen: [SpeakerTraits] = []
    private var matched: [MatchedVoice] = []

    public init(voices: [VoiceCalibration], normalSyllablesPerSecond: Double?, defaultVoiceID: String?) {
        self.voices = voices
        self.normalSyllablesPerSecond = normalSyllablesPerSecond
        self.defaultVoiceID = defaultVoiceID
    }

    public var canMatch: Bool { !voices.isEmpty }

    public var usual: MatchedVoice { MatchedVoice(voiceID: defaultVoiceID, pitchMultiplier: 1, rate: VoiceMatch.defaultRate) }

    public mutating func voice(for speaker: Int?, traits: SpeakerTraits?) -> MatchedVoice {
        guard canMatch, let speaker else { return usual }
        if let i = order.firstIndex(of: speaker) { return matched[i] }
        guard let traits, traits.pitchHz.isFinite, traits.syllablesPerSecond.isFinite, traits.pitchHz > 0,
              traits.syllablesPerSecond > 0 else { return usual }
        order.append(speaker)
        frozen.append(traits)
        let normal = normalSyllablesPerSecond.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        // Earlier speakers' traits are frozen, so their answers don't change when someone new is added.
        matched = VoiceMatch.match(frozen, voices: voices, normalSyllablesPerSecond: normal, defaultVoiceID: defaultVoiceID)
        return matched[matched.count - 1]
    }
}

/// What "Sound like the speaker" is doing, for its note in Settings.
public enum EarMatchState: Equatable, Sendable {
    case off
    /// On, but the translation language has no calibrated voice on this device: everyone gets the usual voice.
    case oneVoice
    case matching

    public init(on: Bool, voices: Int) {
        self = !on ? .off : voices > 0 ? .matching : .oneVoice
    }
}

/// The calibration Seal ships: for each voice locale, its installed voices' own pitch and pace and how
/// `AVSpeechUtterance.pitchMultiplier` and `rate` really move them, and that language's normal pace. Apple's voices are
/// the same files on every device, so it's measured once (`ear-spike calibrate`, renders only) instead of on a phone.
public struct VoiceCalibrationTable: Codable, Sendable {
    public struct Language: Codable, Sendable {
        public let normalSyllablesPerSecond: Double
        public let voices: [VoiceCalibration]
    }

    public let measuredOn: String
    public let date: String
    public let languages: [String: Language]

    public init(json: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: json)
    }

    /// The table in the app. A table that won't decode is empty: everyone gets the usual voice, nothing breaks.
    public static let shipped: VoiceCalibrationTable = {
        (try? VoiceCalibrationTable(json: Data(shippedVoiceCalibrationsJSON.utf8)))
            ?? VoiceCalibrationTable(measuredOn: "", date: "", languages: [:])
    }()

    private init(measuredOn: String, date: String, languages: [String: Language]) {
        self.measuredOn = measuredOn; self.date = date; self.languages = languages
    }

    /// The calibrated voices for one voice locale (`AVSpeechSynthesisVoice.language`, "es-ES"), only those installed
    /// and usable. Other regions are left out, so speakers don't switch accent.
    public func voices(for code: String, installed: Set<String>) -> [VoiceCalibration] {
        (languages[code]?.voices ?? []).filter {
            installed.contains($0.id) && $0.pitchHz.isFinite && $0.pitchHz > 0 && !$0.pitchCurve.isEmpty
        }
    }

    /// Normal pace in the caption language ("en-US", "en_US", "en"): that locale, else the same language's first
    /// region in the table.
    public func normalPace(for language: String?) -> Double? {
        guard let language, !language.isEmpty else { return nil }
        let code = language.replacingOccurrences(of: "_", with: "-")
        let base = code.split(separator: "-").first.map(String.init) ?? code
        let entry = languages[code] ?? languages.keys.sorted().first { $0 == base || $0.hasPrefix(base + "-") }.flatMap { languages[$0] }
        return entry.flatMap { $0.normalSyllablesPerSecond.isFinite && $0.normalSyllablesPerSecond > 0 ? $0.normalSyllablesPerSecond : nil }
    }
}

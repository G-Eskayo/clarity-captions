@preconcurrency import AVFoundation
import EarSpikeKit
import Foundation

// #247 part 1: the voice in your ear set to each speaker's pitch and pace. Measures the voices (setup), the speakers
// (as the app would hear them, in its ~85 ms buffers), how close the matched voice comes, and the lag it adds.

/// A test speaker: an English voice set lower or higher, slower or quicker, so the right answer is known.
public struct TestSpeaker: Sendable {
    public let label: String
    public let voiceID: String
    public let rate: Float
    public let pitch: Float
    public init(_ label: String, _ voiceID: String, rate: Float, pitch: Float) {
        self.label = label; self.voiceID = voiceID; self.rate = rate; self.pitch = pitch
    }

    public static let standard: [TestSpeaker] = [
        .init("Speaker 1: low, slow (man)", "com.apple.voice.compact.en-GB.Daniel", rate: 0.45, pitch: 0.9),
        .init("Speaker 2: high, quick (woman)", "com.apple.voice.compact.en-US.Samantha", rate: 0.56, pitch: 1.1),
        .init("Speaker 3: like speaker 2, slower (woman)", "com.apple.eloquence.en-US.Sandy", rate: 0.48, pitch: 1.0),
        .init("Speaker 4: quick (man)", "com.apple.eloquence.en-US.Reed", rate: 0.58, pitch: 1.0),
    ]
}

public struct Rendered: Sendable {
    public let lag: SynthSample
    public let audio16k: [Float]
    public let buffer22k: AVAudioPCMBuffer
}

public struct VoiceCalibrationRun: Codable, Sendable {
    public let calibration: VoiceCalibration
    public let name: String
    public let seconds: Double      // how long measuring this voice took (setup, in Settings)
    public let pitchSpanSemitones: Double // how far pitchMultiplier 0.7...1.4 really moved it
    public let rateSpan: Double     // syllables/s at 0.6 over at 0.4
}

public struct SpeakerRun: Codable, Sendable {
    public let label: String
    public let truth: String        // how the test speaker was made
    public let audioSeconds: Double
    public let traits: SpeakerTraits?
    public let settledAfterSeconds: Double? // audio heard before the profile could judge the voice
    public let processingMsPerAudioSecond: Double
}

public struct MatchRun: Codable, Sendable {
    public let speaker: String
    public let defaultVoice: MatchedVoice
    public let matched: MatchedVoice
    public let matchedVoiceName: String?
    // How close each comes to the speaker: pitch in semitones off, pace as (voice pace / its normal) over (speaker
    // pace / normal) minus 1.
    public let defaultPitchOffSemitones: Double?
    public let matchedPitchOffSemitones: Double?
    public let defaultPaceOff: Double?
    public let matchedPaceOff: Double?
    public let defaultAudibleMs: [Double]
    public let matchedAudibleMs: [Double]
    /// The matched voice with Apple's default pitch and rate: separates the voice's own start-up from the settings.
    public let sameVoicePlainAudibleMs: [Double]
}

public enum VoiceMatchProbe {
    @MainActor
    public static func render(_ text: String, voiceID: String?, rate: Float? = nil, pitch: Float? = nil,
                              synth: AVSpeechSynthesizer) async throws -> Rendered {
        var bufs: [AVAudioPCMBuffer] = []
        let voice = voiceID.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
        let lag = await SynthLag.render(text, voice: voice, synth: synth, configure: { u in
            if let rate { u.rate = rate }
            if let pitch { u.pitchMultiplier = pitch }
        }, keep: { bufs.append(AudioFiles.copy($0)) })
        guard !bufs.isEmpty else { throw NSError(domain: "ear-spike", code: 1, userInfo: [NSLocalizedDescriptionKey: "no audio from \(voiceID ?? "default")"]) }
        let b16 = try AudioFiles.resample(bufs, to: 16000)
        return Rendered(lag: lag, audio16k: AudioFiles.samples(b16), buffer22k: try AudioFiles.resample(bufs, to: 22050))
    }

    static func pitch(_ audio: [Float]) -> Double? {
        let f = PitchTracker.track(audio, sampleRate: 16000).compactMap { $0 }.sorted()
        return f.isEmpty ? nil : f[f.count / 2]
    }

    public static func speechSeconds(_ audio: [Float]) -> Double { SyllableRate.measure(audio, sampleRate: 16000).speechSeconds }

    /// Syllables in the text over the time spent speaking it (pauses left out), summed over lines. Measured line by
    /// line: a long multi-sentence render came back cut short (6 and 10 lines both gave the same 13.1 s).
    public static func pace(_ lines: [(String, [Float])], language: String) -> Double? {
        var n = 0, t = 0.0
        for (text, audio) in lines {
            guard let c = TextSyllables.count(text, language: language) else { continue }
            let s = speechSeconds(audio)
            guard s > 0.2 else { continue }
            n += c; t += s
        }
        return t > 0 ? Double(n) / t : nil
    }

    @MainActor
    static func renderLines(_ lines: [String], voiceID: String?, rate: Float? = nil, pitch: Float? = nil,
                            synth: AVSpeechSynthesizer) async throws -> [(String, [Float])] {
        var out: [(String, [Float])] = []
        for l in lines { out.append((l, try await render(l, voiceID: voiceID, rate: rate, pitch: pitch, synth: synth).audio16k)) }
        return out
    }

    public static let rates: [Double] = [0.4, 0.45, 0.5, 0.55, 0.6]
    public static let pitches: [Double] = [0.7, 0.8, 0.9, 1, 1.1, 1.25, 1.4]

    /// Done once per voice when it's set up: how `rate` and `pitchMultiplier` really move it.
    @MainActor
    public static func calibrate(_ voice: AVSpeechSynthesisVoice, lines: [String], language: String,
                                 synth: AVSpeechSynthesizer) async throws -> VoiceCalibrationRun {
        let t0 = CFAbsoluteTimeGetCurrent()
        var rateCurve: [CalibrationPoint] = []
        for r in rates {
            let out = try await renderLines(lines, voiceID: voice.identifier, rate: Float(r), synth: synth)
            if let p = pace(out, language: language) { rateCurve.append(.init(r, p)) }
        }
        var pitchCurve: [CalibrationPoint] = []
        for m in pitches {
            let out = try await renderLines(lines, voiceID: voice.identifier, pitch: Float(m), synth: synth)
            if let f = pitch(out.flatMap(\.1)) { pitchCurve.append(.init(m, f)) }
        }
        let hz = CalibrationPoint.value(at: 1, in: pitchCurve) ?? 0
        let sps = CalibrationPoint.value(at: 0.5, in: rateCurve) ?? 0
        let span = (pitchCurve.first?.value).flatMap { lo in pitchCurve.last.map { 12 * log2($0.value / lo) } } ?? 0
        let rspan = (rateCurve.first?.value).flatMap { lo in rateCurve.last.map { $0.value / lo } } ?? 0
        return VoiceCalibrationRun(calibration: VoiceCalibration(id: voice.identifier, pitchHz: hz, syllablesPerSecond: sps,
                                                                 rateCurve: rateCurve, pitchCurve: pitchCurve),
                                   name: voice.name, seconds: CFAbsoluteTimeGetCurrent() - t0,
                                   pitchSpanSemitones: span, rateSpan: rspan)
    }

    /// Feeds a speaker's audio to a profile in the app's buffer size, as it would arrive from the mic.
    public static func profile(_ audio: [Float], lines: [(String, [Float])] = [], label: String,
                               truth: String) -> (SpeakerProfile, SpeakerRun) {
        var p = SpeakerProfile()
        let chunk = 1365 // ~85 ms at 16 kHz, the app's buffer
        var settled: Double?
        var spent = 0.0
        var at = 0
        while at < audio.count {
            let piece = Array(audio[at..<min(audio.count, at + chunk)])
            let t0 = CFAbsoluteTimeGetCurrent()
            p.add(piece, sampleRate: 16000)
            spent += CFAbsoluteTimeGetCurrent() - t0
            at += piece.count
            if settled == nil, p.traits != nil { settled = Double(at) / 16000 }
        }
        // Each finished caption line: its words and how long they took to say.
        let t0 = CFAbsoluteTimeGetCurrent()
        for (text, lineAudio) in lines { p.addLine(text, speechSeconds: speechSeconds(lineAudio), language: "en") }
        spent += CFAbsoluteTimeGetCurrent() - t0
        let seconds = Double(audio.count) / 16000
        return (p, SpeakerRun(label: label, truth: truth, audioSeconds: seconds, traits: p.traits,
                              settledAfterSeconds: settled, processingMsPerAudioSecond: spent * 1000 / seconds))
    }

    static func pitchOff(_ audio: [Float], _ t: SpeakerTraits) -> Double? { pitch(audio).map { 12 * log2($0 / t.pitchHz) } }

    static func paceOff(_ lines: [(String, [Float])], language: String, voiceNormal: Double, speaker: SpeakerTraits,
                        normal: Double) -> Double? {
        guard let p = pace(lines, language: language), voiceNormal > 0, normal > 0 else { return nil }
        return (p / voiceNormal) / (speaker.syllablesPerSecond / normal) - 1
    }

    /// Default vs matched for one speaker: closeness over the lines, and lag per line, alternating so a busy
    /// machine slows both alike.
    @MainActor
    public static func compare(speaker: String, traits: SpeakerTraits, defaultVoice: MatchedVoice, matched: MatchedVoice,
                               calibrations: [VoiceCalibration], normal: Double, lines: [String], language: String,
                               synth: AVSpeechSynthesizer) async throws -> MatchRun {
        var dLag: [Double] = [], mLag: [Double] = [], pLag: [Double] = []
        for (i, line) in lines.enumerated() {
            pLag.append(try await render(line, voiceID: matched.voiceID, synth: synth).lag.audibleMs)
            // Alternate which goes first, so a voice switch or a busy moment lands on both alike.
            if i % 2 == 0 {
                dLag.append(try await render(line, voiceID: defaultVoice.voiceID, synth: synth).lag.audibleMs)
                mLag.append(try await render(line, voiceID: matched.voiceID, rate: matched.rate, pitch: matched.pitchMultiplier, synth: synth).lag.audibleMs)
            } else {
                mLag.append(try await render(line, voiceID: matched.voiceID, rate: matched.rate, pitch: matched.pitchMultiplier, synth: synth).lag.audibleMs)
                dLag.append(try await render(line, voiceID: defaultVoice.voiceID, synth: synth).lag.audibleMs)
            }
        }
        let d = try await renderLines(lines, voiceID: defaultVoice.voiceID, synth: synth)
        let m = try await renderLines(lines, voiceID: matched.voiceID, rate: matched.rate, pitch: matched.pitchMultiplier, synth: synth)
        let normalOf = { (id: String?) in calibrations.first { $0.id == id }?.syllablesPerSecond ?? 0 }
        return MatchRun(speaker: speaker, defaultVoice: defaultVoice, matched: matched,
                        matchedVoiceName: matched.voiceID.flatMap { AVSpeechSynthesisVoice(identifier: $0)?.name },
                        defaultPitchOffSemitones: pitchOff(d.flatMap(\.1), traits), matchedPitchOffSemitones: pitchOff(m.flatMap(\.1), traits),
                        defaultPaceOff: paceOff(d, language: language, voiceNormal: normalOf(defaultVoice.voiceID),
                                                speaker: traits, normal: normal),
                        matchedPaceOff: paceOff(m, language: language, voiceNormal: normalOf(matched.voiceID),
                                                speaker: traits, normal: normal),
                        defaultAudibleMs: dLag, matchedAudibleMs: mLag, sameVoicePlainAudibleMs: pLag)
    }
}

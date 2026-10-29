import AVFoundation
import Foundation

/// What the face-to-face split (#60) captions in: each half's language and the recognizer for it (ADR 0025: Parakeet
/// for English, Apple's engine for other languages). The partner's half is the caption language (From), the owner's
/// half the language she reads (Into).
public struct FaceToFaceSetup: Sendable, Equatable {
    public let ownerLocale: Locale
    public let ownerRecognizer: SpeechRecognizerSetup
    public let partnerLocale: Locale
    public let partnerRecognizer: SpeechRecognizerSetup

    public init(ownerLocale: Locale, ownerRecognizer: SpeechRecognizerSetup, partnerLocale: Locale,
                partnerRecognizer: SpeechRecognizerSetup) {
        self.ownerLocale = ownerLocale
        self.ownerRecognizer = ownerRecognizer
        self.partnerLocale = partnerLocale
        self.partnerRecognizer = partnerRecognizer
    }

    func locale(_ half: FaceToFaceHalf) -> Locale { half == .owner ? ownerLocale : partnerLocale }
    func recognizer(_ half: FaceToFaceHalf) -> SpeechRecognizerSetup { half == .owner ? ownerRecognizer : partnerRecognizer }
}

/// The face-to-face side of `TranscriptionEngine` (#60, the owner's "voice first"): two language engines, one per
/// half, and the diarizer deciding which of them hears the audio. Measured feasible first
/// (docs/perf/face-to-face-spike.md).
///
/// - Every 16 kHz chunk goes into a short buffer, then to the engines `VoiceRouter` picks from the diarizer's latest
///   speaker: only the matched voice's engine, both for a voice not matched yet.
/// - An engine that starts listening is first given the turn so far from the buffer, as fast as it takes it.
/// - An engine that stops listening is told to settle, so its last words finish instead of hanging open, and then hears
///   nothing (Apple's engine is told where the next audio starts; Parakeet's window skips ahead). Not silence: silence
///   fed after a turn could cover the start of the next one, which can't be fed again.
/// - Every word either engine writes is evidence for `SpeakerLanguages`, which locks, corrects and checks the voices.
///
/// Not handled here: Parakeet's mid-session fallback to Apple (heat, memory) in either half.
final class FaceToFaceRouting: @unchecked Sendable {
    private final class Lane {
        let half: FaceToFaceHalf
        var backend: SpeechRecognizerBackend
        var converter: AVAudioConverter?
        var format: AVAudioFormat?
        var clock = LaneClock()
        /// Where this engine's audio resumed after recent skips (the last few).
        var skips: [Double] = []
        var smoother = SpeakerLabelSmoother()
        var lag = WordLagTracker()
        init(half: FaceToFaceHalf, backend: SpeechRecognizerBackend) {
            self.half = half
            self.backend = backend
        }
    }

    let setup: FaceToFaceSetup
    private let pair: LanguagePair
    private let lock = NSLock()
    private var lanes: [FaceToFaceHalf: Lane] = [:]
    private var ring = AudioRing()
    private var router = VoiceRouter()
    private var languages = SpeakerLanguages()
    /// Diarizer slot → the speaker number lines carry, shared by both engines' label smoothers.
    private var numbering: [Int: Int] = [:]
    private var log: [String] = []
    private let makeBackend: (SpeechRecognizerSetup, Locale) -> SpeechRecognizerBackend

    init(setup: FaceToFaceSetup, makeBackend: @escaping (SpeechRecognizerSetup, Locale) -> SpeechRecognizerBackend) {
        self.setup = setup
        self.pair = LanguagePair(owner: setup.ownerLocale, partner: setup.partnerLocale)
        self.makeBackend = makeBackend
    }

    /// "parakeet-ultra-pal6 + apple-speechanalyzer" (owner's half first).
    var engineName: String {
        lock.withLock { [FaceToFaceHalf.owner, .partner].compactMap { lanes[$0]?.backend.name }.joined(separator: " + ") }
    }

    var diagnostics: String {
        lock.withLock {
            let who = numbering.values.sorted().map { n -> String in
                let state: String
                switch languages.state(of: n) {
                case .none: state = "unheard"
                case .matching: state = "matching"
                case .locked(let h): state = h == .owner ? "owner" : "partner"
                case .checking(let h): state = "checking " + (h == .owner ? "owner" : "partner")
                }
                return "\(n + 1):\(state)"
            }
            let listening = router.active.map { $0 == .owner ? "owner" : "partner" }.sorted().joined(separator: "+")
            return "face to face: listening \(listening) · voices [\(who.joined(separator: ", "))]"
        }
    }

    /// Lock, check and correction events so far, for the developer panel and the integration test.
    var events: [String] { lock.withLock { log } }

    /// Loads both engines. Parakeet that won't load gives way to Apple's engine in the same language.
    func prepare() async throws {
        for half in [FaceToFaceHalf.partner, .owner] {
            var backend = makeBackend(setup.recognizer(half), setup.locale(half))
            do {
                try await backend.prepare()
            } catch where backend.choice == .parakeet {
                await backend.cancel()
                backend = makeBackend(.apple, setup.locale(half))
                try await backend.prepare()
            }
            backend.onTrigger = nil
            let lane = Lane(half: half, backend: backend)
            lock.withLock { lanes[half] = lane }
        }
    }

    /// Starts both engines; returns each one's pieces.
    func start() async throws -> [(FaceToFaceHalf, AsyncThrowingStream<RecognizedPiece, Error>)] {
        guard let side = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: LaneClock.rate, channels: 1, interleaved: false) else {
            throw TranscriptionError.converterUnavailable
        }
        var out: [(FaceToFaceHalf, AsyncThrowingStream<RecognizedPiece, Error>)] = []
        for half in [FaceToFaceHalf.partner, .owner] {
            guard let lane = lock.withLock({ lanes[half] }) else { throw TranscriptionError.converterUnavailable }
            if let format = lane.backend.analyzerFormat {
                guard let c = AVAudioConverter(from: side, to: format) else { throw TranscriptionError.converterUnavailable }
                lock.withLock { lane.converter = c; lane.format = format }
            }
            out.append((half, try await lane.backend.start()))
        }
        return out
    }

    /// One 16 kHz chunk of the session that begins at `time`. Called on the audio thread; never blocks on a model.
    func feed(_ samples: [Float], at time: Double, level: Double, segments: [SpeakerSegment]) {
        lock.withLock {
            ring.append(samples, at: time)
            let end = time + Double(samples.count) / LaneClock.rate
            let before = router.active
            let numbering = self.numbering
            let refeed = router.route(now: end, segments: segments, number: { numbering[$0] }, languages: languages)
            for (half, from) in refeed {
                guard let lane = lanes[half] else { continue }
                let back = ring.samples(from: max(from, lane.clock.fedUntil), to: time)
                if !back.samples.isEmpty { push(lane, back.samples, at: back.from, level: level) }
            }
            for (half, lane) in lanes {
                if router.active.contains(half) {
                    push(lane, samples, at: time, level: level)
                } else if before.contains(half) {
                    lane.backend.settle()
                }
            }
        }
    }

    private func push(_ lane: Lane, _ samples: [Float], at time: Double, level: Double) {
        let plan = lane.clock.plan(start: time, count: samples.count)
        guard plan.dropFirst < samples.count else { return }
        if let to = plan.skipTo {
            lane.backend.skip(to: to)
            lane.skips = Array((lane.skips + [to]).suffix(8))
        }
        let fresh = plan.dropFirst == 0 ? samples : Array(samples[plan.dropFirst...])
        if let converter = lane.converter, let format = lane.format {
            if let buffer = Self.convert(fresh, with: converter, to: format) { lane.backend.feed(buffer: buffer) }
        } else {
            lane.backend.feed(samples16k: fresh, level: level)
        }
    }

    private static func convert(_ samples: [Float], with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let src = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        src.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { p in src.floatChannelData![0].update(from: p.baseAddress!, count: samples.count) }
        let capacity = AVAudioFrameCount(Double(samples.count) * format.sampleRate / LaneClock.rate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return src
        }
        return error == nil ? out : nil
    }

    /// One piece from `half`'s engine: its speaker (numbered the same for both engines), lag, and the evidence it gives
    /// about each voice's language. Called from the one task that reads both engines, in arrival order.
    /// Returns the piece to show (the other half's voices' words taken out; an empty one when none are left, which takes
    /// back this engine's open words), its speaker, lag, and every voice's language after it.
    func receive(_ piece: RecognizedPiece, from half: FaceToFaceHalf, segments: [SpeakerSegment],
                 elapsed: Double?) -> (piece: RecognizedPiece, speaker: Int?, lag: Double?, languages: SpeakerLanguages) {
        lock.withLock {
            guard let lane = lanes[half] else { return (piece, nil, nil, languages) }
            let piece = FaceToFace.clamp(piece, skips: lane.skips)
            // Numbers first: a voice heard for the first time gets its number from this piece.
            if let start = piece.start, let end = piece.end {
                var probe = lane.smoother
                _ = probe.label(start: start, end: end, segments: segments, isFinal: piece.isFinal, numbering: &numbering)
            }
            // Each word goes to the voice the diarizer heard at that moment: one result can span a turn change (Apple
            // only ends a result at a long pause).
            var byVoice: [Int: [TimedWord]] = [:]
            for word in piece.words {
                guard let range = word.range,
                      let slot = SpeakerAligner.speaker(start: range.lowerBound, end: range.upperBound, segments: segments),
                      let voice = numbering[slot] else { continue }
                byVoice[voice, default: []].append(TimedWord(text: word.text, start: range.lowerBound, end: range.upperBound))
            }
            for (voice, words) in byVoice.sorted(by: { $0.key < $1.key }) {
                if let change = languages.heard(speaker: voice, lane: half, words: words, isFinal: piece.isFinal,
                                                classify: pair.probabilities) {
                    log.append("\(change) at \(String(format: "%.1f", words.map(\.end).max() ?? 0)) s")
                }
            }
            let numbering = self.numbering
            let shown = FaceToFace.keep(piece, lane: half, segments: segments, number: { numbering[$0] }, languages: languages)
                ?? RecognizedPiece(text: "", isFinal: piece.isFinal, words: [], start: piece.start, end: piece.end)
            var speaker: Int?
            if !shown.words.isEmpty, let start = shown.start, let end = shown.end {
                speaker = lane.smoother.label(start: start, end: end, segments: segments, isFinal: shown.isFinal, numbering: &self.numbering)
            }
            let lag = elapsed.flatMap { lane.lag.sample(elapsed: $0, audioEnds: shown.wordEnds) }
            return (shown, speaker, lag, languages)
        }
    }

    /// Flushes both engines: their last words come out final.
    func finish() async {
        for lane in lock.withLock({ Array(lanes.values) }) { await lane.backend.finish() }
    }

    /// Frees both engines (loaded but never started, or a failed start).
    func cancel() async {
        for lane in lock.withLock({ Array(lanes.values) }) { await lane.backend.cancel() }
    }
}

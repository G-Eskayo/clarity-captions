import AVFoundation
import FluidAudio
import NaturalLanguage
import Speech
import XCTest
@testable import CaptionCore

/// #60 feasibility spike, opt-in: CAPTION_F2F_SPIKE=1 swift test -c release --filter FaceToFaceSpike
/// Needs scripts/fetch-asr-models.sh and the bundled Sortformer model. Prints `F2F-SPIKE` lines; asserts nothing that
/// depends on timing, so it reports rather than gates.
///
/// Questions (owner's voice-first decision on #60):
/// 1. How long after a turn starts does the diarizer name the new speaker (the routing delay)?
/// 2. Do Seal's own engines tell the two languages apart from their confidence (the first-lines match)?
/// 3. With speech routed by speaker to one engine at a time (and the turn's start re-fed to the right engine once the
///    diarizer names the speaker), how far behind are the captions compared with one engine hearing everything?
final class FaceToFaceSpikeTests: XCTestCase {
    private var enabled: Bool { ProcessInfo.processInfo.environment["CAPTION_F2F_SPIKE"] == "1" }
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
    private var diarizerURL: URL { repo.appendingPathComponent("Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc") }
    private var parakeetURL: URL { repo.appendingPathComponent("Apps/Spike/Resources/Models/ParakeetUltra") }
    static let rate = 16_000.0
    static let spanish = Locale(identifier: "es-MX")

    // MARK: audio

    struct Turn { let voice: String; let language: String; let text: String; var start = 0.0; var end = 0.0 }

    static let script: [Turn] = [
        Turn(voice: "Paulina", language: "es", text: "Buenos días, ¿en qué le puedo ayudar hoy?"),
        Turn(voice: "Samantha", language: "en", text: "Good morning. I would like to buy a ticket to Madrid, please."),
        Turn(voice: "Paulina", language: "es", text: "Claro que sí. El próximo tren a Madrid sale a las tres y cuarto de la tarde."),
        Turn(voice: "Samantha", language: "en", text: "That works for me. How much does a return ticket cost?"),
        Turn(voice: "Paulina", language: "es", text: "Son cuarenta y dos euros, ida y vuelta. ¿Prefiere ventanilla o pasillo?"),
        Turn(voice: "Samantha", language: "en", text: "A window seat, please. I like to watch the countryside go by."),
        Turn(voice: "Paulina", language: "es", text: "Muy bien. Aquí tiene su billete. El andén número cinco está a la derecha."),
        Turn(voice: "Samantha", language: "en", text: "Thank you so much. Have a wonderful afternoon, and see you next time."),
    ]

    static func synth(voice: String, text: String) throws -> [Float] {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@16000", text]
        try p.run(); p.waitUntilExit()
        return try read(url)
    }

    static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let src = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: src)
        if file.processingFormat.sampleRate == rate, file.processingFormat.channelCount == 1,
           file.processingFormat.commonFormat == .pcmFormatFloat32 {
            return Array(UnsafeBufferPointer(start: src.floatChannelData![0], count: Int(src.frameLength)))
        }
        let conv = AVAudioConverter(from: file.processingFormat, to: target)!
        let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(src.frameLength) * rate / file.processingFormat.sampleRate) + 1024)!
        var given = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true; status.pointee = .haveData; return src
        }
        return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
    }

    /// The conversation: turns with `gap` seconds of silence between them, and each turn's audio time.
    static func conversation(gap: Double = 0.5) throws -> (audio: [Float], turns: [Turn]) {
        var audio = [Float](repeating: 0, count: Int(0.5 * rate))
        var turns: [Turn] = []
        for var t in script {
            let speech = try synth(voice: t.voice, text: t.text)
            t.start = Double(audio.count) / rate
            audio += speech
            t.end = Double(audio.count) / rate
            audio += [Float](repeating: 0, count: Int(gap * rate))
            turns.append(t)
        }
        return (audio, turns)
    }

    static func buffer(_ samples: ArraySlice<Float>) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count)))!
        b.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { p in b.floatChannelData![0].update(from: p.baseAddress!, count: samples.count) }
        return b
    }

    static func pct(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return .nan }
        let s = xs.sorted()
        return s[min(s.count - 1, Int(Double(s.count - 1) * p + 0.5))]
    }

    static func f(_ x: Double) -> String { String(format: "%.2f", x) }

    // MARK: 1. diarizer turn-detection delay

    func testDiarizerNamesTheNewSpeakerHowLongAfterATurnStarts() async throws {
        try XCTSkipUnless(enabled, "opt-in")
        let (audio, turns) = try Self.conversation()
        let d = LiveDiarizer(modelURL: diarizerURL)
        try await d.prepare()
        var polls: [(wall: Double, segments: [SpeakerSegment])] = []
        let chunk = Int(0.1 * Self.rate)
        let began = Date()
        var i = 0
        while i < audio.count {
            d.feed(Array(audio[i..<min(i + chunk, audio.count)]))
            i += chunk
            let fed = Double(i) / Self.rate
            let wall = Date().timeIntervalSince(began)
            if fed > wall { try await Task.sleep(nanoseconds: UInt64((fed - wall) * 1e9)) }
            polls.append((Date().timeIntervalSince(began), d.segments))
        }
        for _ in 0..<30 { try await Task.sleep(nanoseconds: 100_000_000); polls.append((Date().timeIntervalSince(began), d.segments)) }
        d.finish()
        let final = d.segments
        // Each voice's slot: whichever slot holds most of that voice's turns in the final segments.
        var slotOf: [String: Int] = [:]
        for voice in Set(turns.map(\.voice)) {
            var overlap: [Int: Double] = [:]
            for t in turns where t.voice == voice {
                for s in final { overlap[s.speaker, default: 0] += max(0, min(t.end, s.end) - max(t.start, s.start)) }
            }
            slotOf[voice] = overlap.max { $0.value < $1.value }?.key
        }
        print("F2F-SPIKE diarizer slots \(slotOf) :: \(d.diagnostics)")
        var delays: [Double] = []
        var wholeTurn: [Double] = []
        for (k, t) in turns.enumerated() {
            guard let slot = slotOf[t.voice] else { continue }
            // Named: a segment of the right slot covers 0.3 s into the turn.
            let probe = t.start + 0.3
            let named = polls.first { $0.segments.contains { $0.speaker == slot && $0.start <= probe && probe < $0.end } }
            // Settled: the right slot holds 80% of the turn's first 1.5 s.
            let span = min(1.5, t.end - t.start)
            let settled = polls.first { p in
                p.segments.filter { $0.speaker == slot }.reduce(0.0) { $0 + max(0, min(t.start + span, $1.end) - max(t.start, $1.start)) } >= 0.8 * span
            }
            let n = named.map { $0.wall - t.start }
            let s = settled.map { $0.wall - t.start }
            if let n { delays.append(n) }
            if let s { wholeTurn.append(s) }
            print("F2F-SPIKE turn \(k + 1) \(t.language) \(Self.f(t.start))-\(Self.f(t.end))s named after \(n.map(Self.f) ?? "never") s, settled after \(s.map(Self.f) ?? "never") s")
        }
        let wrong = final.filter { seg in
            turns.contains { t in slotOf[t.voice] != seg.speaker && min(t.end, seg.end) - max(t.start, seg.start) > 0.3 }
        }
        print("F2F-SPIKE diarizer named-delay median \(Self.f(Self.pct(delays, 0.5))) p95 \(Self.f(Self.pct(delays, 0.95))) max \(Self.f(delays.max() ?? .nan)); settled median \(Self.f(Self.pct(wholeTurn, 0.5))) max \(Self.f(wholeTurn.max() ?? .nan)); segments in the wrong voice's turn (>0.3 s): \(wrong.count) of \(final.count)")
        XCTAssertEqual(Set(slotOf.values).count, 2, "the two voices get two slots")
    }

    // MARK: 2. does each engine's confidence tell the languages apart?

    /// Mean word confidence from Parakeet (English) for a clip, and its words.
    static func parakeetConfidence(_ samples: [Float], manager: AsrManager) async throws -> (Double, String) {
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: Int(rate))
        let padded = samples.count >= minimum ? samples : samples + [Float](repeating: 0, count: minimum - samples.count)
        var state = TdtDecoderState.make(decoderLayers: AsrModelVersion.ultra.decoderLayers)
        let r = try await manager.transcribe(padded, decoderState: &state)
        let tokens = r.tokenTimings ?? []
        let conf = tokens.isEmpty ? 0 : tokens.map { Double($0.confidence) }.reduce(0, +) / Double(tokens.count)
        return (conf, r.text)
    }

    /// Mean confidence from Apple's SpeechTranscriber in `locale` for a clip, and its words.
    static func appleConfidence(_ samples: [Float], locale: Locale) async throws -> (Double, String) {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        try await SpeechModelInstaller.install(locale: locale) { _ in }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (seq, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let collect = Task { () -> [(String, Double)] in
            var out: [(String, Double)] = []
            for try await result in transcriber.results where result.isFinal {
                for run in result.text.runs {
                    let words = String(result.text[run.range].characters)
                    if !words.trimmingCharacters(in: .whitespaces).isEmpty {
                        out.append((words, run.transcriptionConfidence ?? 0))
                    }
                }
            }
            return out
        }
        try await analyzer.start(inputSequence: seq)
        let conv = AVAudioConverter(from: buffer(samples[...]).format, to: format)!
        let src = buffer(samples[...])
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(samples.count) * format.sampleRate / rate) + 1024)!
        var given = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true; status.pointee = .haveData; return src
        }
        input.yield(AnalyzerInput(buffer: out))
        input.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let runs = try await collect.value
        // Weight each run by its length, so one confident short word doesn't carry a garbled sentence.
        let weight = runs.map { Double($0.0.count) }.reduce(0, +)
        let conf = weight == 0 ? 0 : runs.map { Double($0.0.count) * $0.1 }.reduce(0, +) / weight
        return (conf, runs.map(\.0).joined())
    }

    func testEnginesConfidenceSeparatesTheTwoLanguages() async throws {
        try XCTSkipUnless(enabled, "opt-in")
        let models = try AsrModels.loadLocal(from: parakeetURL, version: .ultra)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        // Real recorded Spanish (FLEURS es_419 test clips on the Mini, #158's language run), else the synthetic turns.
        var clips: [(language: String, source: String, samples: [Float])] = []
        let fleurs = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("fleurs-eval/shards/es/shard-001")
        if let manifest = try? String(contentsOf: fleurs.appendingPathComponent("manifest.jsonl"), encoding: .utf8) {
            for line in manifest.split(separator: "\n").prefix(20) {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let file = obj["file"] as? String else { continue }
                clips.append(("es", "fleurs", try Self.read(fleurs.appendingPathComponent(file))))
            }
        }
        // English and Spanish TTS voices, several of each, short and long lines (the first line of a conversation).
        let english = ["Hi.", "Good morning, how are you?", "I would like to buy a ticket to Madrid, please.",
                       "That works for me. How much does a return ticket cost?", "Thank you so much."]
        let spanish = ["Hola.", "Buenos días, ¿cómo está?", "Quisiera comprar un billete a Madrid, por favor.",
                       "Me parece bien. ¿Cuánto cuesta un billete de ida y vuelta?", "Muchas gracias."]
        for v in ["Samantha", "Daniel", "Fred"] { for s in english { clips.append(("en", "tts-\(v)", try Self.synth(voice: v, text: s))) } }
        for v in ["Paulina", "Mónica"] { for s in spanish { clips.append(("es", "tts-\(v)", try Self.synth(voice: v, text: s))) } }

        func lid(_ text: String, _ lang: String) -> Double {
            let r = NLLanguageRecognizer()
            r.languageConstraints = [.english, .spanish]
            r.processString(text)
            return r.languageHypotheses(withMaximum: 2)[lang == "en" ? .english : .spanish] ?? 0
        }
        func wordCount(_ t: String) -> Int { t.split(whereSeparator: { $0 == " " }).count }
        var lids: [(lang: String, words: Int, p: Double, a: Double, both: Double)] = []
        var rows: [(lang: String, src: String, secs: Double, p: Double, a: Double)] = []
        for c in clips {
            let (p, pt) = try await Self.parakeetConfidence(c.samples, manager: manager)
            let (a, at) = try await Self.appleConfidence(c.samples, locale: Self.spanish)
            rows.append((c.language, c.source, Double(c.samples.count) / Self.rate, p, a))
            let lp = lid(pt, c.language), la = lid(at, c.language), lb = lid(pt + " " + at, c.language)
            lids.append((c.language, max(wordCount(pt), wordCount(at)), lp, la, lb))
            print("F2F-SPIKE lid \(c.language) \(c.source) words \(max(wordCount(pt), wordCount(at))) P(true language) from parakeet \(Self.f(lp)) apple-es \(Self.f(la)) both \(Self.f(lb))")
            print("F2F-SPIKE conf \(c.language) \(c.source) \(Self.f(Double(c.samples.count) / Self.rate))s parakeet-en \(Self.f(p)) apple-es \(Self.f(a)) :: en=\"\(pt)\" es=\"\(at)\"")
        }
        for lang in ["en", "es"] {
            let r = rows.filter { $0.lang == lang }
            print("F2F-SPIKE conf summary \(lang) n=\(r.count) parakeet-en min \(Self.f(r.map(\.p).min() ?? .nan)) median \(Self.f(Self.pct(r.map(\.p), 0.5))) max \(Self.f(r.map(\.p).max() ?? .nan)) | apple-es min \(Self.f(r.map(\.a).min() ?? .nan)) median \(Self.f(Self.pct(r.map(\.a), 0.5))) max \(Self.f(r.map(\.a).max() ?? .nan)) | margin(p-a) min \(Self.f(r.map { $0.p - $0.a }.min() ?? .nan)) max \(Self.f(r.map { $0.p - $0.a }.max() ?? .nan))")
        }
        for minWords in [1, 2, 3, 4, 6] {
            let r = lids.filter { $0.words >= minWords }
            let worst = r.map(\.both).min() ?? .nan
            let wrong = r.filter { $0.both < 0.5 }.count
            print("F2F-SPIKE lid summary words>=\(minWords) n=\(r.count) P(true) from both engines' words: min \(Self.f(worst)) p05 \(Self.f(Self.pct(r.map(\.both), 0.05))) median \(Self.f(Self.pct(r.map(\.both), 0.5))); wrong side \(wrong); parakeet-only min \(Self.f(r.map(\.p).min() ?? .nan)); apple-only min \(Self.f(r.map(\.a).min() ?? .nan))")
        }
        await manager.cleanup()
    }

    // MARK: 3. routed vs one-way caption lag

    final class Lane: @unchecked Sendable {
        let name: String
        let backend: SpeechRecognizerBackend
        private var converter: AVAudioConverter?
        private var format: AVAudioFormat?
        /// Session seconds fed so far (gaps are filled with silence, so the engine's clock stays on the session's).
        private(set) var fedUntil = 0.0
        var lags: [Double] = []
        var finals: [(text: String, start: Double, end: Double)] = []
        /// Every word end heard so far (volatile or final), to see how many words a turn has.
        private let lock = NSLock()
        private var wordEnds: Set<Double> = []
        func words(in range: ClosedRange<Double>) -> Int { lock.withLock { wordEnds.filter { range.contains($0) }.count } }
        private var lagTracker = WordLagTracker()
        var task: Task<Void, Never>?

        init(name: String, backend: SpeechRecognizerBackend) { self.name = name; self.backend = backend }

        func start(began: Date, keep: @escaping @Sendable (RecognizedPiece) -> Bool) async throws {
            try await backend.prepare()
            if let f = backend.analyzerFormat {
                format = f
                converter = AVAudioConverter(from: FaceToFaceSpikeTests.buffer([0][...]).format, to: f)
            }
            let pieces = try await backend.start()
            task = Task {
                do {
                    for try await piece in pieces {
                        self.lock.withLock { for e in piece.wordEnds { self.wordEnds.insert((e * 10).rounded() / 10) } }
                        guard keep(piece) else { continue }
                        let wall = Date().timeIntervalSince(began)
                        if let lag = self.lagTracker.sample(elapsed: wall, audioEnds: piece.wordEnds) { self.lags.append(lag) }
                        if piece.isFinal, let s = piece.start, let e = piece.end { self.finals.append((piece.text, s, e)) }
                    }
                } catch {}
            }
        }

        /// Feeds `samples` that begin at session time `at`, padding any gap since the last feed with silence.
        func feed(_ samples: ArraySlice<Float>, at: Double) {
            if at > fedUntil + 0.001 {
                let gap = [Float](repeating: 0, count: Int((at - fedUntil) * FaceToFaceSpikeTests.rate))
                push(gap[...])
                fedUntil = at
            }
            guard at >= fedUntil - 0.001 else { return }
            push(samples)
            fedUntil = at + Double(samples.count) / FaceToFaceSpikeTests.rate
        }

        private func push(_ samples: ArraySlice<Float>) {
            guard !samples.isEmpty else { return }
            if let converter, let format {
                let src = FaceToFaceSpikeTests.buffer(samples)
                let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(samples.count) * format.sampleRate / FaceToFaceSpikeTests.rate) + 1024)!
                var given = false
                var err: NSError?
                converter.convert(to: out, error: &err) { _, status in
                    if given { status.pointee = .noDataNow; return nil }
                    given = true; status.pointee = .haveData; return src
                }
                backend.feed(buffer: out)
            } else {
                backend.feed(samples16k: Array(samples), level: AudioLevel.rmsDBFS(Array(samples)))
            }
        }

        func finish() async { await backend.finish(); await task?.value }
    }

    enum Mode: String { case oneWayParakeet, oneWayApple, routed }

    /// Runs the conversation at real-time pace. `routed`: the diarizer's latest speaker decides which engine hears
    /// the audio; a voice with no language yet goes to both; when the diarizer names a speaker whose engine wasn't
    /// listening, the turn so far (kept in a short buffer) is re-fed to it at once. Languages lock on each voice's
    /// first turn, given the answer (part 2 measures whether the engines get it right; this part measures time).
    func run(_ mode: Mode, audio: [Float], turns: [Turn]) async throws -> (en: Lane?, es: Lane?, switches: Int, catchUp: [Double]) {
        let began = Date()
        let en = mode == .oneWayApple ? nil : Lane(name: "parakeet-en", backend: ParakeetBackend(modelURL: parakeetURL))
        let es = mode == .oneWayParakeet ? nil : Lane(name: "apple-es", backend: AppleSpeechBackend(locale: Self.spanish))
        let d = LiveDiarizer(modelURL: diarizerURL)
        try await d.prepare()
        // Only keep words said in the lane's own language (by the script's turn times), so lag counts what a reader
        // would be shown, not the other engine's garbled try at the wrong language.
        func inLanguage(_ lang: String) -> @Sendable (RecognizedPiece) -> Bool {
            { piece in
                guard let e = piece.end else { return false }
                return turns.contains { $0.language == lang && e > $0.start - 0.2 && e < $0.end + 0.6 }
            }
        }
        let all: @Sendable (RecognizedPiece) -> Bool = { _ in true }
        try await en?.start(began: began, keep: mode == .routed ? inLanguage("en") : all)
        try await es?.start(began: began, keep: mode == .routed ? inLanguage("es") : all)
        // The diarizer slot → language, locked on each voice's first turn once that turn's first final line is in.
        var language: [Int: String] = [:]
        var active: Set<String> = ["en", "es"]
        var switches = 0
        var catchUp: [Double] = []
        let chunk = Int(0.1 * Self.rate)
        var i = 0
        let wallStart = Date()
        while i < audio.count {
            let at = Double(i) / Self.rate
            let slice = audio[i..<min(i + chunk, audio.count)]
            d.feed(Array(slice))
            if mode == .routed {
                let segs = d.segments
                if let latest = segs.max(by: { $0.end < $1.end }), latest.end > at - 3 {
                    // Lock: once both engines have 4 words in this voice's turn, the script says which language
                    // (part 2 measures whether the words' language gets it right; this part measures time).
                    if language[latest.speaker] == nil,
                       let turn = turns.first(where: { latest.start < $0.end && latest.end > $0.start }),
                       (en?.words(in: turn.start...(turn.end + 0.3)) ?? 0) >= 4,
                       (es?.words(in: turn.start...(turn.end + 0.3)) ?? 0) >= 4 {
                        language[latest.speaker] = turn.language
                        print("F2F-SPIKE lock slot \(latest.speaker) → \(turn.language) at audio \(Self.f(at)) s, \(Self.f(at - turn.start)) s into its first turn")
                    }
                    let want: Set<String> = language[latest.speaker].map { [$0] } ?? ["en", "es"]
                    for lang in want where !active.contains(lang) {
                        // Newly named: re-feed this turn from its start, as fast as the engine takes it.
                        let lane = lang == "en" ? en! : es!
                        let from = max(lane.fedUntil, latest.start - 0.2)
                        let a = Int(from * Self.rate), b = i
                        if b > a { lane.feed(audio[a..<b], at: from) }
                        switches += 1
                        catchUp.append(at - latest.start)
                    }
                    active = want
                }
            }
            if active.contains("en") || mode == .oneWayParakeet { en?.feed(slice, at: at) }
            if active.contains("es") || mode == .oneWayApple { es?.feed(slice, at: at) }
            i += chunk
            let fed = Double(i) / Self.rate
            let wall = Date().timeIntervalSince(wallStart)
            if fed > wall { try await Task.sleep(nanoseconds: UInt64((fed - wall) * 1e9)) }
        }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        await en?.finish()
        await es?.finish()
        d.finish()
        return (en, es, switches, catchUp)
    }

    func testRoutedCaptionLagAgainstOneWay() async throws {
        try XCTSkipUnless(enabled, "opt-in")
        let (audio, turns) = try Self.conversation()
        print("F2F-SPIKE conversation \(Self.f(Double(audio.count) / Self.rate)) s, \(turns.count) turns")
        func report(_ mode: Mode, _ lane: Lane?, lang: String) {
            guard let lane else { return }
            let words = lane.finals.filter { f in turns.contains { $0.language == lang && f.end > $0.start - 0.2 && f.end < $0.end + 0.6 } }
            print("F2F-SPIKE lag \(mode.rawValue) \(lane.name) median \(Self.f(Self.pct(lane.lags, 0.5))) p95 \(Self.f(Self.pct(lane.lags, 0.95))) n=\(lane.lags.count) :: \(lang) finals: \(words.map(\.text).joined(separator: " | "))")
        }
        let p = try await run(.oneWayParakeet, audio: audio, turns: turns)
        report(.oneWayParakeet, p.en, lang: "en")
        let a = try await run(.oneWayApple, audio: audio, turns: turns)
        report(.oneWayApple, a.es, lang: "es")
        let r = try await run(.routed, audio: audio, turns: turns)
        report(.routed, r.en, lang: "en")
        report(.routed, r.es, lang: "es")
        print("F2F-SPIKE routed: \(r.switches) engine switches, turn start → engine re-fed after median \(Self.f(Self.pct(r.catchUp, 0.5))) max \(Self.f(r.catchUp.max() ?? .nan)) s")
    }

    // MARK: 4. the real engine, face to face

    /// At 48 kHz, so replay's 4096-frame reads are 85 ms, like the iPhone microphone's buffers (at 16 kHz they would be
    /// 256 ms, fed ahead of the wall clock, and every lag would read about 0.2 s short).
    static func writeWav(_ samples: [Float]) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("f2f-\(UUID()).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let src = buffer(samples[...])
        let conv = AVAudioConverter(from: src.format, to: format)!
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count * 3 + 4096))!
        var given = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true; status.pointee = .haveData; return src
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: out)
        return url
    }

    /// Caption lag through the real engine: one-way (one engine hears everything, as today) against face to face, per
    /// language, on the same replayed conversation. Lag counts the words of each language's own turns.
    func testCaptionLagFaceToFaceAgainstOneWay() async throws {
        try XCTSkipUnless(enabled, "opt-in")
        let (audio, turns) = try Self.conversation()
        let url = try Self.writeWav(audio)
        defer { try? FileManager.default.removeItem(at: url) }
        func language(_ end: Double?) -> String? {
            end.flatMap { e in turns.first { e > $0.start - 0.2 && e < $0.end + 0.6 }?.language }
        }
        func lags(_ engine: TranscriptionEngine, lane: FaceToFaceHalf?) async throws -> [String: [Double]] {
            var out: [String: [Double]] = [:]
            for try await u in try await engine.startReplaying(fileURL: url) {
                guard let lag = u.lagSeconds, let lang = language(u.endSeconds) else { continue }
                if let lane, u.lane != lane { continue }
                out[lang, default: []].append(lag)
            }
            return out
        }
        func line(_ name: String, _ l: [Double]) {
            print("F2F-LAG \(name) median \(Self.f(Self.pct(l, 0.5))) p95 \(Self.f(Self.pct(l, 0.95))) n=\(l.count)")
        }
        let parakeet = try await lags(TranscriptionEngine(diarizerModelURL: diarizerURL, recognizer: .parakeet(modelURL: parakeetURL)), lane: nil)
        line("one-way parakeet, English turns", parakeet["en"] ?? [])
        let apple = try await lags(TranscriptionEngine(locale: Self.spanish, diarizerModelURL: diarizerURL, recognizer: .apple), lane: nil)
        line("one-way apple es, Spanish turns", apple["es"] ?? [])
        let setup = FaceToFaceSetup(ownerLocale: Locale(identifier: "en-US"), ownerRecognizer: .parakeet(modelURL: parakeetURL),
                                    partnerLocale: Self.spanish, partnerRecognizer: .apple)
        var f2fOwner: [Double] = [], f2fPartner: [Double] = []
        let engine = TranscriptionEngine(diarizerModelURL: diarizerURL, faceToFace: setup)
        for try await u in try await engine.startReplaying(fileURL: url) {
            guard let lag = u.lagSeconds, let lang = language(u.endSeconds) else { continue }
            if u.lane == .owner, lang == "en" { f2fOwner.append(lag) }
            if u.lane == .partner, lang == "es" { f2fPartner.append(lag) }
        }
        line("face to face parakeet, English turns", f2fOwner)
        line("face to face apple es, Spanish turns", f2fPartner)
    }

    /// The whole engine in face-to-face mode on the spike's conversation: each voice ends up on its language's half,
    /// each half shows its own engine's words, and the lag per half.
    func testTheEngineRoutesARealConversationByVoice() async throws {
        try XCTSkipUnless(enabled, "opt-in")
        let (audio, turns) = try Self.conversation()
        let url = try Self.writeWav(audio)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = TranscriptionEngine(
            diarizerModelURL: diarizerURL,
            faceToFace: FaceToFaceSetup(ownerLocale: Locale(identifier: "en-US"), ownerRecognizer: .parakeet(modelURL: parakeetURL),
                                        partnerLocale: Self.spanish, partnerRecognizer: .apple))
        var stream = CaptionStream()
        var languages = SpeakerLanguages()
        var lags: [FaceToFaceHalf: [Double]] = [:]
        for try await u in try await engine.startReplaying(fileURL: url) {
            stream.apply(text: u.text, isFinal: u.isFinal, speaker: u.speaker,
                         range: u.startSeconds.flatMap { s in u.endSeconds.map { s...$0 } }, lane: u.lane)
            if let l = u.languages { languages = l }
            if let lag = u.lagSeconds, let lane = u.lane { lags[lane, default: []].append(lag) }
            if u.isFinal || ProcessInfo.processInfo.environment["F2F_DEBUG"] == "2", ProcessInfo.processInfo.environment["F2F_DEBUG"] != nil {
                print("F2F-PIECE \(u.lane.map { "\($0)" } ?? "-") \(u.startSeconds.map(Self.f) ?? "?")-\(u.endSeconds.map(Self.f) ?? "?") spk \(u.speaker.map(String.init) ?? "-") lag \(u.lagSeconds.map(Self.f) ?? "-") :: \(u.text)")
            }
        }
        print("F2F-ENGINE turns: " + turns.map { "\($0.language) \(Self.f($0.start))-\(Self.f($0.end))" }.joined(separator: ", "))
        print("F2F-ENGINE \(engine.engineName) events: \(engine.faceToFaceEvents.joined(separator: " | "))")
        let shown = FaceToFace.shown(stream.lines, languages: languages)
        for half in [FaceToFaceHalf.owner, .partner] {
            let said = FaceToFace.lines(saidOn: half, in: shown, half: { languages.half(of: $0) }).map(\.text)
            print("F2F-ENGINE said on \(half): \(said.joined(separator: " | "))")
            let l = lags[half] ?? []
            print("F2F-ENGINE lag \(half) median \(Self.f(Self.pct(l, 0.5))) p95 \(Self.f(Self.pct(l, 0.95))) n=\(l.count)")
        }
        let unplaced = shown.filter { languages.half(of: $0) == nil }.map(\.text)
        print("F2F-ENGINE no half: \(unplaced.joined(separator: " | "))")
        let ownerWords = FaceToFace.lines(saidOn: .owner, in: shown, half: { languages.half(of: $0) }).map(\.text).joined(separator: " ").lowercased()
        let partnerWords = FaceToFace.lines(saidOn: .partner, in: shown, half: { languages.half(of: $0) }).map(\.text).joined(separator: " ").lowercased()
        XCTAssertTrue(ownerWords.contains("ticket"), ownerWords)
        XCTAssertTrue(ownerWords.contains("countryside"), ownerWords)
        XCTAssertTrue(partnerWords.contains("billete"), partnerWords)
        XCTAssertTrue(partnerWords.contains("ventanilla"), partnerWords)
        XCTAssertFalse(ownerWords.contains("billete"), "no Spanish on the owner's side as said")
        XCTAssertFalse(partnerWords.contains("countryside"), "no English on the partner's side as said")
        XCTAssertEqual(turns.count, 8)
    }
}

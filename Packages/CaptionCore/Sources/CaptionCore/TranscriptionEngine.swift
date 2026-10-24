import AVFoundation
import CoreMedia
import Foundation
import Speech

public struct CaptionUpdate: Sendable {
    public let text: String
    public let isFinal: Bool
    /// Seconds of audio already fed in minus the audio time this result covers up to --
    /// i.e. how far behind live speech this caption is. Nil if the result carried no time range.
    public let lagSeconds: Double?
    /// 0-based speaker slot for this caption, nil if the diarizer has no overlap with it yet.
    public let speaker: Int?
    /// Audio-time span this caption covers, in seconds; nil if the result carried no time range.
    public let startSeconds: Double?
    public let endSeconds: Double?
    /// Spike-only: live diarizer health line.
    public let diagnostics: String
    /// Emphasis level per word in the text (split on whitespace), empty if unavailable.
    public let wordEmphasis: [EmphasisLevel]
    /// The recognizer behind this caption, and why it left Parakeet if it did (beta report, ADR 0025).
    public var engine = ""
    public var engineFallback: FallbackReason?
}

/// Audio seconds fed to the analyzer so far; written on the audio thread, read on the results task.
final class FedAudioClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    func add(_ seconds: Double) { lock.lock(); value += seconds; lock.unlock() }
    var seconds: Double { lock.lock(); defer { lock.unlock() }; return value }
}

/// Wall-clock reference for latency measurement. Set once when feeding begins;
/// provides elapsed wall-clock time since that moment.
final class FedWallTime: @unchecked Sendable {
    private let lock = NSLock()
    private var startTime: Date?

    func set(_ time: Date) {
        lock.lock(); defer { lock.unlock() }
        if startTime == nil { startTime = time }
    }

    func elapsedSinceStart() -> Double? {
        lock.lock(); defer { lock.unlock() }
        return startTime.map { Date().timeIntervalSince($0) }
    }
}

/// How the phone treats the microphone signal. Spike experiment: which one hears a person 5 ft away
/// over room noise, and which gives the diarizer separable voices?
public enum MicMode: String, CaseIterable, Sendable {
    /// `.measurement`: the system turns OFF its noise/gain processing. Raw, quiet.
    case raw
    /// Default recording processing.
    case standard
    /// Voice-processing I/O: noise suppression, echo cancel, gain control. Enables the system Voice Isolation picker.
    case voiceProcessing
}

public enum TranscriptionError: Error {
    case noCompatibleAudioFormat
    case converterUnavailable
}

/// Which recognizer a TranscriptionEngine starts with (ADR 0025). The app picks it with EngineFallbackPolicy.
public enum SpeechRecognizerSetup: Sendable, Equatable {
    case apple
    /// Parakeet from this bundled folder; Apple's engine takes over if it can't load or has to stop.
    case parakeet(modelURL: URL)
}

/// Live microphone -> a speech recognizer behind `SpeechRecognizerBackend` (ADR 0001, ADR 0025), with the 16 kHz side
/// path for the diarizer, the sound labeler and loudness.
public final class TranscriptionEngine {
    private let audioEngine = AVAudioEngine()
    private let locale: Locale
    private let micMode: MicMode
    private let setup: SpeechRecognizerSetup
    private let diarizer: LiveDiarizer
    private let soundLabeler = SoundLabeler()
    private var soundLabelerStream: AsyncStream<SoundLabelKind>?
    private var audioLevelStreamValue: AsyncStream<Double>?
    private var audioLevelContinuation: AsyncStream<Double>.Continuation?
    /// Spike-only: how long each startup step took, for the developer panel. Measured, not guessed.
    public private(set) var startupReport = ""
    private var loudnessTracker = LoudnessWordTracker()
    private var loudnessBaseline = LoudnessBaseline()
    private var loudnessTimeSeries: [(audioTime: Double, level: Double)] = []
    private let loudnessLock = NSLock()
    private let prepareLock = NSLock()
    private var prepareTask: Task<SpeechRecognizerBackend, Error>?
    private var preparedLaps: [String] = []
    /// Set by `stop()`: a load still running then frees what it made instead of keeping it.
    private var stopped = false

    /// The live recognizer and the converter that feeds it, swapped together on a mid-session fallback.
    private struct Route {
        var backend: SpeechRecognizerBackend?
        var converter: AVAudioConverter?
        var format: AVAudioFormat?
        var started = false
    }
    private let routeLock = NSLock()
    private var route = Route()
    private var inFormat: AVAudioFormat?
    /// Each backend's piece stream, in order: a fallback adds Apple's after Parakeet's has flushed.
    private var pieceStreams: AsyncStream<AsyncThrowingStream<RecognizedPiece, Error>>.Continuation?
    private var switching = false
    private var lastDecodeSeconds: Double?

    /// The recognizer captions are on now ("parakeet-ultra-pal6" / "apple-speechanalyzer"): beta report, diagnostics.
    /// Stays set after Stop, so the report written at the end of a session still names it.
    public var engineName: String { routeLock.withLock { lastEngineName } }
    private var lastEngineName = ""
    /// The error behind a load fallback, for the developer panel.
    public private(set) var fallbackDetail: String?
    /// Why this engine isn't on Parakeet, if it isn't: chosen so at the start (`startReason`) or fell back.
    public private(set) var fallbackReason: FallbackReason?
    /// Called once when Parakeet falls back to Apple, so the app can count it toward the daily pin.
    public var onFallback: (@Sendable (FallbackReason) -> Void)?
    private var fallbackCounted = false

    /// `diarizerModelURL` has no default on purpose: the app must say where its bundled speaker model
    /// lives, so there is no accidental network path (ADR 0014). The same goes for Parakeet's folder.
    public init(locale: Locale = Locale(identifier: "en-US"), micMode: MicMode = .standard, diarizerModelURL: URL,
                recognizer: SpeechRecognizerSetup = .apple, startReason: FallbackReason? = nil) {
        self.fallbackReason = startReason
        self.locale = locale
        self.micMode = micMode
        self.setup = recognizer
        self.diarizer = LiveDiarizer(modelURL: diarizerModelURL)
    }

    /// Starts live captioning. If anything fails part-way, everything already opened is released before the
    /// error is thrown, so a failed start can never leave a speech recognizer or the microphone held.
    public func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
        do { return try await startSession() } catch {
            await stop()
            throw error
        }
    }

    /// Loads everything Start needs except the microphone (#119): runs during the launch animation, so Start is
    /// instant. Reports steps 1-3 (speech model, speaker model, sound classifier). Never opens the
    /// microphone or asks for permission. Safe to call more than once: every caller waits for the same load.
    public func prepare(onStep: @escaping @Sendable (Int) -> Void) async throws {
        _ = try await loadPrepared(onStep: onStep)
    }

    private func loadPrepared(onStep: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> SpeechRecognizerBackend {
        let task: Task<SpeechRecognizerBackend, Error> = prepareLock.withLock {
            if let prepareTask { return prepareTask }
            let task = Task { try await self.load(onStep: onStep) }
            prepareTask = task
            return task
        }
        return try await task.value
    }

    private func makeBackend() -> SpeechRecognizerBackend {
        switch setup {
        case .apple: return AppleSpeechBackend(locale: locale)
        case .parakeet(let url):
            let backend = ParakeetBackend(modelURL: url)
            backend.onDecode = { [weak self] seconds in self?.lastDecodeSeconds = seconds }
            return backend
        }
    }

    private func load(onStep: @escaping @Sendable (Int) -> Void) async throws -> SpeechRecognizerBackend {
        let clock = ContinuousClock()
        var mark = clock.now
        var laps: [String] = []
        func lap(_ name: String) {
            let now = clock.now
            let d = now - mark
            laps.append("\(name) \(String(format: "%.1f", Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18))s")
            mark = now
        }
        var backend = makeBackend()
        do {
            try await backend.prepare()
        } catch where backend.choice == .parakeet {
            // Design §5: the model is missing or won't load. Apple's engine for this launch, captions keep flowing.
            await backend.cancel()
            fallbackDetail = String(describing: error)
            recordFallback(.loadFailed)
            backend = AppleSpeechBackend(locale: locale)
            try await backend.prepare()
        }
        lap(backend.name); onStep(1)
        // Ready before the first audio, so both clocks start at the same first sample.
        do {
            try await diarizer.prepare()
            lap("speaker model"); onStep(2)
            try await soundLabelerAsync { try self.soundLabeler.prepare() }
            lap("sound classifier")
        } catch {
            await backend.cancel()
            throw error
        }
        soundLabelerStream = soundLabeler.stream()
        if prepareLock.withLock({ stopped }) {
            // Stopped while loading (released in the background, or a failed start): never keep a recognizer.
            await backend.cancel()
            throw CancellationError()
        }
        routeLock.withLock { route.backend = backend; lastEngineName = backend.name }
        preparedLaps = laps
        onStep(3)
        return backend
    }

    private func recordFallback(_ reason: FallbackReason) {
        guard !fallbackCounted else { return }
        fallbackCounted = true
        fallbackReason = reason
        onFallback?(reason)
    }

    private func startSession() async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
        let clock = ContinuousClock()
        var mark = clock.now
        let alreadyLoaded = prepareLock.withLock { prepareTask != nil }
        let backend = try await loadPrepared()
        var laps = preparedLaps
        if alreadyLoaded { laps = ["loaded before Start (\(laps.joined(separator: ", ")))"] }
        func lap(_ name: String) {
            let now = clock.now
            let d = now - mark
            laps.append("\(name) \(String(format: "%.1f", Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18))s")
            mark = now
        }
        lap(alreadyLoaded ? "waited for the load" : "load")

        let (alStream, alCont) = AsyncStream.makeStream(of: Double.self)
        self.audioLevelStreamValue = alStream
        self.audioLevelContinuation = alCont
        let fed = FedAudioClock()

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        switch micMode {
        case .raw: try session.setCategory(.record, mode: .measurement)
        case .standard: try session.setCategory(.record, mode: .default)
        case .voiceProcessing: try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        }
        try session.setActive(true)
        #endif
        // Must happen before the tap format is read.
        if micMode == .voiceProcessing { try audioEngine.inputNode.setVoiceProcessingEnabled(true) }

        let input = audioEngine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        let pieces = try await open(backend, inFormat: inFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { buffer, _ in
            self.processBuffer(buffer, inFormat: inFormat, fed: fed)
        }
        audioEngine.prepare()
        let wallTime = FedWallTime()
        try audioEngine.start()
        wallTime.set(Date())
        lap("audio start")
        startupReport = laps.joined(separator: " · ")
        return makeResultStream(pieces: pieces, wallTime: wallTime)
    }

    /// Builds the converter for `backend`, starts it, and opens the stream of piece streams.
    private func open(_ backend: SpeechRecognizerBackend, inFormat: AVAudioFormat) async throws -> AsyncStream<AsyncThrowingStream<RecognizedPiece, Error>> {
        self.inFormat = inFormat
        guard AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) != nil else {
            throw TranscriptionError.converterUnavailable
        }
        var converter: AVAudioConverter?
        if let format = backend.analyzerFormat {
            guard let c = AVAudioConverter(from: inFormat, to: format) else { throw TranscriptionError.converterUnavailable }
            converter = c
        }
        backend.onTrigger = { [weak self] trigger in self?.handle(trigger) }
        let first = try await backend.start()
        let (streams, continuation) = AsyncStream.makeStream(of: AsyncThrowingStream<RecognizedPiece, Error>.self)
        continuation.yield(first)
        pieceStreams = continuation
        routeLock.withLock { route = Route(backend: backend, converter: converter, format: backend.analyzerFormat, started: true) }
        return streams
    }

    /// A trigger from the running backend or the app (design §5).
    public func handle(_ trigger: FallbackTrigger) {
        let running = routeLock.withLock { route.backend?.choice ?? .apple }
        guard EngineFallbackPolicy.action(for: trigger, running: running) == .switchToApple,
              let reason = EngineFallbackPolicy.reason(for: trigger) else { return }
        Task { await self.switchToApple(reason: reason) }
    }

    /// Mid-session switch: the microphone, diarizer, sound labeler and clock stay up; only the recognizer changes.
    /// Parakeet flushes its words as final first; audio during Apple's warm-up (about 1 s) goes uncaptioned.
    private func switchToApple(reason: FallbackReason) async {
        let old: SpeechRecognizerBackend? = routeLock.withLock {
            guard !switching, route.started, route.backend?.choice == .parakeet, !prepareLock.withLock({ stopped }) else { return nil }
            switching = true
            let old = route.backend
            route.backend = nil
            return old
        }
        guard let old, let inFormat else { return }
        recordFallback(reason)
        await old.finish()
        let apple = AppleSpeechBackend(locale: locale)
        do {
            try await apple.prepare()
            guard let format = apple.analyzerFormat, let converter = AVAudioConverter(from: inFormat, to: format) else {
                throw TranscriptionError.converterUnavailable
            }
            let stream = try await apple.start()
            let keep = routeLock.withLock { () -> Bool in
                switching = false
                if prepareLock.withLock({ stopped }) { return false }
                route = Route(backend: apple, converter: converter, format: format, started: true)
                lastEngineName = apple.name
                return true
            }
            if keep { pieceStreams?.yield(stream) } else { await apple.cancel() }
        } catch {
            routeLock.withLock { switching = false }
            await apple.cancel()
            pieceStreams?.yield(AsyncThrowingStream { $0.finish(throwing: error) })
        }
    }

    /// Replays audio from a file at real-time pace for latency measurement.
    /// The same processing pipeline as live mic input: same resamplers, recognizer, diarizer, lag calculation.
    public func startReplaying(fileURL: URL) async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
        let backend = try await loadPrepared()
        let fed = FedAudioClock()
        let audioFile = try AVAudioFile(forReading: fileURL)
        let inFormat = audioFile.processingFormat
        let pieces = try await open(backend, inFormat: inFormat)

        return AsyncThrowingStream { (continuation: AsyncThrowingStream<CaptionUpdate, Error>.Continuation) in
            let task = Task {
                do {
                    let wallTime = FedWallTime()
                    wallTime.set(Date())
                    let resultTask = Task {
                        for try await update in self.makeResultStream(pieces: pieces, wallTime: wallTime) { continuation.yield(update) }
                    }
                    // Read the file in 4096-frame chunks and feed it at real-time pace.
                    let bufferSize = AVAudioFrameCount(4096)
                    while audioFile.framePosition < audioFile.length {
                        let buffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: bufferSize)!
                        try audioFile.read(into: buffer)
                        if buffer.frameLength == 0 { break }
                        self.processBuffer(buffer, inFormat: inFormat, fed: fed)
                        if let elapsedWall = wallTime.elapsedSinceStart(), fed.seconds > elapsedWall {
                            try await Task.sleep(nanoseconds: UInt64((fed.seconds - elapsedWall) * 1e9))
                        }
                    }
                    await self.finishRecognizer()
                    _ = try await resultTask.value
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, inFormat: AVAudioFormat, fed: FedAudioClock) {
        let (backend, converter, format) = routeLock.withLock { (route.backend, route.converter, route.format) }
        // 16 kHz mono Float32 for the diarizer, the sound labeler, loudness, and Parakeet.
        if let diarFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
           let dOut = convert(buffer, with: diarConverter(from: inFormat, to: diarFormat), to: diarFormat),
           let ch = dOut.floatChannelData {
            let samples = Array(UnsafeBufferPointer(start: ch[0], count: Int(dOut.frameLength)))
            diarizer.feed(samples)
            soundLabeler.feed(samples, atAudioTime: fed.seconds)
            let level = recordLoudness(samples: samples, atAudioTime: fed.seconds)
            if format == nil { backend?.feed(samples16k: samples, speech: level > Self.speechFloorDBFS) }
        }
        if let backend, let converter, let format, let out = convert(buffer, with: converter, to: format) {
            backend.feed(buffer: out)
        }
        fed.add(Double(buffer.frameLength) / inFormat.sampleRate)
    }

    /// Louder than this is treated as possible speech by Parakeet's silence gate and watchdog (BetaFeedback's quiet line).
    static let speechFloorDBFS = -50.0

    private var diarConverterCache: AVAudioConverter?
    private func diarConverter(from inFormat: AVAudioFormat, to diarFormat: AVAudioFormat) -> AVAudioConverter? {
        if let c = diarConverterCache, c.inputFormat == inFormat { return c }
        diarConverterCache = AVAudioConverter(from: inFormat, to: diarFormat)
        return diarConverterCache
    }

    private func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }

    private func makeResultStream(pieces: AsyncStream<AsyncThrowingStream<RecognizedPiece, Error>>, wallTime: FedWallTime) -> AsyncThrowingStream<CaptionUpdate, Error> {
        return AsyncThrowingStream { [weak self] continuation in
            let task = Task {
                do {
                    var lagTracker = WordLagTracker()
                    var labels = SpeakerLabelSmoother()     // one per session (#91)
                    for await stream in pieces {
                        for try await piece in stream {
                            guard let self else { break }
                            let speaker = (piece.start.flatMap { st in piece.end.map { (st, $0) } })
                                .flatMap { labels.label(start: $0.0, end: $0.1, segments: self.diarizer.segments, isFinal: piece.isFinal) }
                            let lag = wallTime.elapsedSinceStart().flatMap { lagTracker.sample(elapsed: $0, audioEnds: piece.wordEnds) }
                            var update = CaptionUpdate(text: piece.text, isFinal: piece.isFinal, lagSeconds: lag, speaker: speaker,
                                                       startSeconds: piece.start, endSeconds: piece.end,
                                                       diagnostics: self.diagnostics, wordEmphasis: self.wordEmphasis(piece.words))
                            update.engine = self.engineName
                            update.engineFallback = self.fallbackReason
                            continuation.yield(update)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private var diagnostics: String {
        var parts = [engineName]
        if let fallbackReason { parts.append("fallback: \(fallbackReason.rawValue)" + (fallbackDetail.map { " (\($0))" } ?? "")) }
        if let lastDecodeSeconds { parts.append(String(format: "decode %.2fs", lastDecodeSeconds)) }
        parts.append(diarizer.diagnostics)
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Records the loudness level for a buffer of audio samples at a given audio time.
    @discardableResult
    private func recordLoudness(samples: [Float], atAudioTime audioTime: Double) -> Double {
        let level = AudioLevel.rmsDBFS(samples)
        loudnessLock.lock(); defer { loudnessLock.unlock() }
        loudnessTimeSeries.append((audioTime: audioTime, level: level))
        loudnessBaseline.update(level)
        audioLevelContinuation?.yield(level)
        return level
    }

    /// Computes the average loudness for a word's audio time range.
    /// Returns nil if no measurements exist for that range.
    private func averageLoudness(for range: ClosedRange<Double>) -> Double? {
        loudnessLock.lock(); defer { loudnessLock.unlock() }
        let overlapping = loudnessTimeSeries.filter { $0.audioTime >= range.lowerBound && $0.audioTime <= range.upperBound }
        guard !overlapping.isEmpty else { return nil }
        return overlapping.map(\.level).reduce(0, +) / Double(overlapping.count)
    }

    private func wordEmphasis(_ words: [RecognizedWord]) -> [EmphasisLevel] {
        let (baseline, fallback) = loudnessLock.withLock { (loudnessBaseline.median, loudnessTimeSeries.last?.level ?? -60) }
        return WordEmphasis.levels(for: words, baseline: baseline, loudness: averageLoudness(for:), fallback: fallback)
    }

    /// Flushes the live recognizer (its last words come out final) and closes the piece streams.
    private func finishRecognizer() async {
        let backend = routeLock.withLock { () -> SpeechRecognizerBackend? in
            defer { route = Route() }
            return route.started ? route.backend : nil
        }
        await backend?.finish()
        pieceStreams?.finish()
        pieceStreams = nil
    }

    /// Releases the microphone, the recognizer and the helpers. Safe to call more than once.
    public func stop() async {
        prepareLock.withLock { stopped = true }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        let unstarted = routeLock.withLock { route.started ? nil : route.backend }
        if let unstarted {
            routeLock.withLock { route = Route() }
            await unstarted.cancel()   // loaded ahead but never started (#119)
        }
        await finishRecognizer()
        diarizer.finish()
        soundLabeler.finish()
        audioLevelContinuation?.finish()   // left open, it kept the session waiting after Stop (#89)
        audioLevelContinuation = nil
    }

    /// Loads the speaker model once and discards it, so Core ML's one-time Neural Engine preparation
    /// happens during first run instead of the first time someone taps Start.
    public static func warmUp(diarizerModelURL: URL) async throws {
        try await LiveDiarizer(modelURL: diarizerModelURL).prepare()
    }

    /// Loads Parakeet once and discards it, so Core ML's first compile for this phone (35 s on a Mac) happens
    /// during first run instead of behind the first Start (design §1, risk "first load").
    public static func warmUp(parakeetModelURL: URL) async throws {
        let backend = ParakeetBackend(modelURL: parakeetModelURL)
        try await backend.prepare()
        await backend.cancel()
    }

    /// Helper to run a throwing closure on a background task context.
    private func soundLabelerAsync(_ body: @escaping () throws -> Void) async throws {
        try await Task.detached(priority: .userInitiated) { try body() }.value
    }

    /// Returns the stream of recognized sound labels.
    public func soundLabelsStream() -> AsyncStream<SoundLabelKind> {
        soundLabelerStream ?? AsyncStream { $0.finish() }
    }

    /// Returns the stream of room audio levels (RMS dBFS) sampled at buffer boundaries.
    public func audioLevelStream() -> AsyncStream<Double> {
        audioLevelStreamValue ?? AsyncStream { $0.finish() }
    }
}

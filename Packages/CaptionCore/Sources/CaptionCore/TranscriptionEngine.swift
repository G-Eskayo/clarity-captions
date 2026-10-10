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

/// Live microphone -> on-device SpeechAnalyzer/SpeechTranscriber (ADR 0001).
/// Spike-grade: no diarization yet, no interruption/route-change handling yet.
public final class TranscriptionEngine {
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private let locale: Locale
    private let micMode: MicMode
    private let diarizer: LiveDiarizer
    private let soundLabeler = SoundLabeler()
    private var soundLabelerStream: AsyncStream<SoundLabelKind>?
    private var audioLevelStreamValue: AsyncStream<Double>?
    private var audioLevelContinuation: AsyncStream<Double>.Continuation?
    private let contextualStrings: [String]
    /// Spike-only: how long each startup step took, for the developer panel. Measured, not guessed.
    public private(set) var startupReport = ""
    private var loudnessTracker = LoudnessWordTracker()
    private var loudnessBaseline = LoudnessBaseline()
    private var loudnessTimeSeries: [(audioTime: Double, level: Double)] = []
    private let loudnessLock = NSLock()
    /// What `prepare` loads ahead of Start (#119): the speech model, the speaker model, the sound classifier and the
    /// analyzer, everything except the microphone.
    private struct Prepared {
        let transcriber: SpeechTranscriber
        let analyzer: SpeechAnalyzer
        let format: AVAudioFormat
    }
    private let prepareLock = NSLock()
    private var prepareTask: Task<Prepared, Error>?
    private var preparedLaps: [String] = []
    private var analyzerStarted = false
    /// Set by `stop()`: a load still running then frees what it made instead of keeping it.
    private var stopped = false

    /// `diarizerModelURL` has no default on purpose: the app must say where its bundled speaker model
    /// lives, so there is no accidental network path (ADR 0014).
    public init(locale: Locale = Locale(identifier: "en-US"), micMode: MicMode = .standard, diarizerModelURL: URL, contextualStrings: [String] = []) {
        self.locale = locale
        self.micMode = micMode
        self.diarizer = LiveDiarizer(modelURL: diarizerModelURL)
        self.contextualStrings = contextualStrings
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
    /// instant. Reports steps 1-3 (speech model, speaker model, sound classifier and analyzer). Never opens the
    /// microphone or asks for permission. Safe to call more than once: every caller waits for the same load.
    public func prepare(onStep: @escaping @Sendable (Int) -> Void) async throws {
        _ = try await loadPrepared(onStep: onStep)
    }

    private func loadPrepared(onStep: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> Prepared {
        let task: Task<Prepared, Error> = prepareLock.withLock {
            if let prepareTask { return prepareTask }
            let task = Task { try await self.load(onStep: onStep) }
            prepareTask = task
            return task
        }
        return try await task.value
    }

    private func load(onStep: @escaping @Sendable (Int) -> Void) async throws -> Prepared {
        let clock = ContinuousClock()
        var mark = clock.now
        var laps: [String] = []
        func lap(_ name: String) {
            let now = clock.now
            let d = now - mark
            laps.append("\(name) \(String(format: "%.1f", Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18))s")
            mark = now
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        try await ensureModelInstalled(for: transcriber)
        lap("speech model"); onStep(1)
        // Ready before the first audio, so both clocks start at the same first sample.
        try await diarizer.prepare()
        lap("speaker model"); onStep(2)
        try await soundLabelerAsync { try self.soundLabeler.prepare() }
        lap("sound classifier")
        soundLabelerStream = soundLabeler.stream()

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // Load the model before the first word, not on it.
        try await analyzer.prepareToAnalyze(in: format)
        lap("analyzer")
        if prepareLock.withLock({ stopped }) {
            // Stopped while loading (released in the background, or a failed start): never keep a recognizer.
            await analyzer.cancelAndFinishNow()
            throw CancellationError()
        }
        self.analyzer = analyzer
        preparedLaps = laps
        onStep(3)
        return Prepared(transcriber: transcriber, analyzer: analyzer, format: format)
    }

    private func startSession() async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
        let clock = ContinuousClock()
        var mark = clock.now
        let alreadyLoaded = prepareLock.withLock { prepareTask != nil }
        let prepared = try await loadPrepared()
        var laps = preparedLaps
        if alreadyLoaded { laps = ["loaded before Start (\(laps.joined(separator: ", ")))"] }
        func lap(_ name: String) {
            let now = clock.now
            let d = now - mark
            laps.append("\(name) \(String(format: "%.1f", Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18))s")
            mark = now
        }
        lap(alreadyLoaded ? "waited for the load" : "load")
        let transcriber = prepared.transcriber, analyzer = prepared.analyzer, format = prepared.format

        let (alStream, alCont) = AsyncStream.makeStream(of: Double.self)
        self.audioLevelStreamValue = alStream
        self.audioLevelContinuation = alCont

        let fed = FedAudioClock()
        let (sequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputBuilder = builder

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
        guard let converter = AVAudioConverter(from: inFormat, to: format),
              let diarFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let diarConverter = AVAudioConverter(from: inFormat, to: diarFormat) else {
            throw TranscriptionError.converterUnavailable
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { buffer, _ in
            self.processBuffer(buffer, inFormat: inFormat, converter: converter, diarConverter: diarConverter, format: format, diarFormat: diarFormat, fed: fed, builder: builder)
        }
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            try await analyzer.setContext(context)
        }
        audioEngine.prepare()
        let wallTime = FedWallTime()
        try audioEngine.start()
        wallTime.set(Date())
        try await analyzer.start(inputSequence: sequence)
        analyzerStarted = true
        lap("audio start")
        startupReport = laps.joined(separator: " · ")

        return makeResultStream(transcriber: transcriber, fed: fed, wallTime: wallTime)
    }

    /// Replays audio from a file at real-time pace for latency measurement.
    /// The same processing pipeline as live mic input: same resamplers, analyzers, diarizer, lag calculation.
    public func startReplaying(fileURL: URL) async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        try await ensureModelInstalled(for: transcriber)
        try await diarizer.prepare()
        try await soundLabelerAsync { try self.soundLabeler.prepare() }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        let fed = FedAudioClock()
        let (sequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputBuilder = builder

        let audioFile = try AVAudioFile(forReading: fileURL)
        let inFormat = audioFile.processingFormat
        guard let converter = AVAudioConverter(from: inFormat, to: format),
              let diarFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let diarConverter = AVAudioConverter(from: inFormat, to: diarFormat) else {
            throw TranscriptionError.converterUnavailable
        }

        try await analyzer.prepareToAnalyze(in: format)
        soundLabelerStream = soundLabeler.stream()

        return AsyncThrowingStream { (continuation: AsyncThrowingStream<CaptionUpdate, Error>.Continuation) in
            let task = Task {
                do {
                    // Read file in 4096-frame chunks at the input format's sample rate.
                    let bufferSize = AVAudioFrameCount(4096)
                    var position: AVAudioFramePosition = 0
                    let wallTime = FedWallTime()

                    // Start the result stream task in the background.
                    let resultTask = Task {
                        var lagTracker = WordLagTracker()
                        var labels = SpeakerLabelSmoother()
                        for try await result in transcriber.results {
                            let starts = result.text.runs.compactMap { $0.audioTimeRange?.start.seconds }
                            let ends = result.text.runs.compactMap { $0.audioTimeRange?.end.seconds }
                            let end = ends.max()
                            let speaker = (starts.min().flatMap { st in end.map { (st, $0) } })
                                .flatMap { labels.label(start: $0.0, end: $0.1, segments: self.diarizer.segments, isFinal: result.isFinal) }
                            let lag = wallTime.elapsedSinceStart().flatMap { elapsed in lagTracker.sample(elapsed: elapsed, audioEnds: ends) }
                            let wordEmphasis = self.wordEmphasisFromResultText(result.text)
                            continuation.yield(CaptionUpdate(text: String(result.text.characters), isFinal: result.isFinal, lagSeconds: lag, speaker: speaker, startSeconds: starts.min(), endSeconds: end, diagnostics: self.diarizer.diagnostics, wordEmphasis: wordEmphasis))
                        }
                    }

                    // Feed audio from the file at real-time pace.
                    try await analyzer.start(inputSequence: sequence)
                    wallTime.set(Date())
                    audioFile.framePosition = position
                    while position < audioFile.length {
                        let buffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: bufferSize)!
                        try audioFile.read(into: buffer)
                        if buffer.frameLength == 0 { break }

                        self.processBuffer(buffer, inFormat: inFormat, converter: converter, diarConverter: diarConverter, format: format, diarFormat: diarFormat, fed: fed, builder: builder)

                        // Sleep to maintain real-time pace: fed time vs. wall clock time.
                        if let elapsedWall = wallTime.elapsedSinceStart() {
                            let targetWall = fed.seconds
                            if targetWall > elapsedWall {
                                try await Task.sleep(nanoseconds: UInt64((targetWall - elapsedWall) * 1e9))
                            }
                        }

                        position += Int64(buffer.frameLength)
                    }

                    builder.finish()
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    _ = try await resultTask.value
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, inFormat: AVAudioFormat, converter: AVAudioConverter, diarConverter: AVAudioConverter, format: AVAudioFormat, diarFormat: AVAudioFormat, fed: FedAudioClock, builder: AsyncStream<AnalyzerInput>.Continuation) {
        let ratio = format.sampleRate / inFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        // Same tap buffer, second path: 16 kHz mono Float32 for the diarizer and sound labeler.
        let dCap = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / inFormat.sampleRate) + 1024
        if let dOut = AVAudioPCMBuffer(pcmFormat: diarFormat, frameCapacity: dCap) {
            var dSupplied = false
            var dError: NSError?
            diarConverter.convert(to: dOut, error: &dError) { _, status in
                if dSupplied { status.pointee = .noDataNow; return nil }
                dSupplied = true
                status.pointee = .haveData
                return buffer
            }
            if dError == nil, let ch = dOut.floatChannelData {
                let samples = Array(UnsafeBufferPointer(start: ch[0], count: Int(dOut.frameLength)))
                diarizer.feed(samples)
                soundLabeler.feed(samples, atAudioTime: fed.seconds)
                recordLoudness(samples: samples, atAudioTime: fed.seconds)
            }
        }
        if error == nil {
            fed.add(Double(out.frameLength) / format.sampleRate)
            builder.yield(AnalyzerInput(buffer: out))
        }
    }

    private func makeResultStream(transcriber: SpeechTranscriber, fed: FedAudioClock, wallTime: FedWallTime) -> AsyncThrowingStream<CaptionUpdate, Error> {
        return AsyncThrowingStream { [weak self] continuation in
            let task = Task {
                do {
                    var lagTracker = WordLagTracker()
                    var labels = SpeakerLabelSmoother()     // one per session (#91)
                    for try await result in transcriber.results {
                        let starts = result.text.runs.compactMap { $0.audioTimeRange?.start.seconds }
                        let ends = result.text.runs.compactMap { $0.audioTimeRange?.end.seconds }
                        let end = ends.max()
                        let speaker = (starts.min().flatMap { st in end.map { (st, $0) } })
                            .flatMap { labels.label(start: $0.0, end: $0.1, segments: self?.diarizer.segments ?? [], isFinal: result.isFinal) }
                        let lag = wallTime.elapsedSinceStart().flatMap { elapsed in lagTracker.sample(elapsed: elapsed, audioEnds: ends) }
                        let wordEmphasis = self?.wordEmphasisFromResultText(result.text) ?? []
                        continuation.yield(CaptionUpdate(text: String(result.text.characters), isFinal: result.isFinal, lagSeconds: lag, speaker: speaker, startSeconds: starts.min(), endSeconds: end, diagnostics: self?.diarizer.diagnostics ?? "", wordEmphasis: wordEmphasis))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Records the loudness level for a buffer of audio samples at a given audio time.
    private func recordLoudness(samples: [Float], atAudioTime audioTime: Double) {
        let level = AudioLevel.rmsDBFS(samples)
        loudnessLock.lock(); defer { loudnessLock.unlock() }
        loudnessTimeSeries.append((audioTime: audioTime, level: level))
        loudnessBaseline.update(level)
        audioLevelContinuation?.yield(level)
    }

    /// Computes the average loudness for a word's audio time range.
    /// Returns nil if no measurements exist for that range.
    private func averageLoudness(for range: ClosedRange<Double>) -> Double? {
        loudnessLock.lock(); defer { loudnessLock.unlock() }
        let overlapping = loudnessTimeSeries.filter { $0.audioTime >= range.lowerBound && $0.audioTime <= range.upperBound }
        guard !overlapping.isEmpty else { return nil }
        return overlapping.map(\.level).reduce(0, +) / Double(overlapping.count)
    }

    /// Helper to compute word emphasis from a finalized result's runs.
    private func wordEmphasisFromResultText(_ resultText: AttributedString) -> [EmphasisLevel] {
        var result: [EmphasisLevel] = []
        loudnessLock.lock(); let baseline = loudnessBaseline.median; loudnessLock.unlock()

        for run in resultText.runs {
            let substr = resultText[run.range]
            let text = String(describing: substr)
            let words = text.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }

            guard let timeRange = run.audioTimeRange else {
                result.append(contentsOf: Array(repeating: .normal, count: words.count))
                continue
            }

            let audioRange = timeRange.start.seconds...timeRange.end.seconds
            let loudness = averageLoudness(for: audioRange) ?? (loudnessTimeSeries.last?.level ?? -60)
            let emphasis = EmphasisMapper.level(wordDBFS: loudness, baseline: baseline)
            result.append(contentsOf: Array(repeating: emphasis, count: words.count))
        }
        return result
    }

    /// Releases the microphone, the speech analyzer and the helpers. Safe to call more than once.
    public func stop() async {
        prepareLock.withLock { stopped = true }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputBuilder?.finish()
        inputBuilder = nil
        if let analyzer {
            self.analyzer = nil
            if analyzerStarted {
                do { try await analyzer.finalizeAndFinishThroughEndOfInput() }
                catch { await analyzer.cancelAndFinishNow() }   // never leave a recognizer allocated
            } else {
                await analyzer.cancelAndFinishNow()   // loaded ahead but never started (#119)
            }
        }
        diarizer.finish()
        soundLabeler.finish()
        audioLevelContinuation?.finish()   // left open, it kept the session waiting after Stop (#89)
        audioLevelContinuation = nil
    }

    /// The one-time, system-provisioned model fetch noted in CONTEXT.md "On-device only".
    private func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        try await SpeechModelInstaller.install(locale: locale) { _ in }
    }

    /// Loads the speaker model once and discards it, so Core ML's one-time Neural Engine preparation
    /// happens during first run instead of the first time someone taps Start.
    public static func warmUp(diarizerModelURL: URL) async throws {
        try await LiveDiarizer(modelURL: diarizerModelURL).prepare()
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

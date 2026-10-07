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

struct MicrophoneNotRestored: Error, CustomStringConvertible {
    let description = "Microphone was not restored after interruption"
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
    private let contextualStrings: [String]
    /// Spike-only: how long each startup step took, for the developer panel. Measured, not guessed.
    public private(set) var startupReport = ""
    private var loudnessTracker = LoudnessWordTracker()
    private var loudnessBaseline = LoudnessBaseline()
    private var loudnessTimeSeries: [(audioTime: Double, level: Double)] = []
    private let loudnessLock = NSLock()
    private var interruptionCont: AsyncStream<InterruptionEvent>.Continuation?
    private var interruptionStream: AsyncStream<InterruptionEvent>?
    private var resultContinuation: AsyncThrowingStream<CaptionUpdate, Error>.Continuation?
    private var interruptionObserverTask: Task<Void, Never>?
    // Tap state for reinstalling on engine configuration changes (ADR 0021).
    private var tapState: TapState?

    private struct TapState {
        let inFormat: AVAudioFormat
        let format: AVAudioFormat
        let diarFormat: AVAudioFormat
        let fed: FedAudioClock
        let builder: AsyncStream<AnalyzerInput>.Continuation
    }

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

    private func startSession() async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
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
        lap("speech model")
        // Ready before the first audio, so both clocks start at the same first sample.
        try await diarizer.prepare()
        lap("speaker model")
        try await soundLabelerAsync { try self.soundLabeler.prepare() }
        lap("sound classifier")
        soundLabelerStream = soundLabeler.stream()

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
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

        // Set the built-in mic as the preferred input (ADR 0021).
        if let inputs = session.availableInputs,
           let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(builtInMic)
        }

        // Set up interruption event stream for ADR 0020/0021.
        let (istream, icont) = AsyncStream.makeStream(of: InterruptionEvent.self)
        interruptionStream = istream
        interruptionCont = icont

        // Observe AVAudioSession interruptions (ADR 0021).
        interruptionObserverTask = Task { [weak self] in
            let notificationCenter = NotificationCenter.default
            var currentWatchdog: InterruptionWatchdog?

            for await notification in notificationCenter.notifications(named: AVAudioSession.interruptionNotification) {
                guard let self else { break }
                guard let dict = notification.userInfo else { continue }
                guard let rawType = dict[AVAudioSession.interruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType) else { continue }

                switch type {
                case .began:
                    icont.yield(.began(reason: "Something else is using the microphone"))
                    // Start a watchdog to enforce the 30-second timeout (ADR 0021).
                    let watchdog = InterruptionWatchdog(timeoutSeconds: 30)
                    currentWatchdog = watchdog
                    Task { [weak self] in
                        let result = await watchdog.wait()
                        // If the watchdog times out, finish the results stream with an error.
                        if result == .timedOut {
                            self?.resultContinuation?.finish(throwing: MicrophoneNotRestored())
                        }
                    }

                case .ended:
                    // Attempt to restore the microphone (ADR 0021).
                    let shouldResume = Self.shouldResumeAfterInterruption(
                        optionsRawValue: dict[AVAudioSession.interruptionOptionKey] as? UInt
                    )

                    if shouldResume {
                        do {
                            try session.setActive(true)
                            // Re-assert the built-in mic on every route change (ADR 0021).
                            if let inputs = session.availableInputs,
                               let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) {
                                try session.setPreferredInput(builtInMic)
                            }
                            audioEngine.prepare()
                            try audioEngine.start()
                            // Signal the watchdog that we resumed successfully.
                            if let watchdog = currentWatchdog {
                                _ = await watchdog.resume()
                            }
                            icont.yield(.ended)
                        } catch {
                            // If we can't restore, let the watchdog timeout handle it.
                        }
                    }
                    currentWatchdog = nil

                @unknown default:
                    break
                }
            }
        }

        // Observe AVAudioSession route changes to re-assert the built-in mic (ADR 0021).
        Task { [weak self] in
            let notificationCenter = NotificationCenter.default
            for await _ in notificationCenter.notifications(named: AVAudioSession.routeChangeNotification) {
                guard let self else { break }
                do {
                    if let inputs = session.availableInputs,
                       let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) {
                        try session.setPreferredInput(builtInMic)
                    }
                } catch {
                    // Route change handling is best-effort; continue if it fails.
                }
            }
        }

        // Observe AVAudioEngine configuration changes (e.g., Bluetooth device connect/disconnect)
        // to reinstall the tap with the potentially new input format (ADR 0021).
        Task { [weak self] in
            let notificationCenter = NotificationCenter.default
            for await _ in notificationCenter.notifications(named: AVAudioEngine.configurationChangeNotification) {
                guard let self else { break }
                self.reinstallTap()
            }
        }
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
        // Save tap state for reinstalling on engine configuration changes (ADR 0021).
        self.tapState = TapState(inFormat: inFormat, format: format, diarFormat: diarFormat, fed: fed, builder: builder)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { buffer, _ in
            self.processBuffer(buffer, inFormat: inFormat, converter: converter, diarConverter: diarConverter, format: format, diarFormat: diarFormat, fed: fed, builder: builder)
        }
        // Load the model before the first word, not on it.
        try await analyzer.prepareToAnalyze(in: format)
        lap("analyzer")
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
                        for try await result in transcriber.results {
                            let starts = result.text.runs.compactMap { $0.audioTimeRange?.start.seconds }
                            let ends = result.text.runs.compactMap { $0.audioTimeRange?.end.seconds }
                            let end = ends.max()
                            let speaker = (starts.min().flatMap { st in end.map { (st, $0) } })
                                .flatMap { SpeakerAligner.speaker(start: $0.0, end: $0.1, segments: self.diarizer.segments) }
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
            self?.resultContinuation = continuation
            let task = Task {
                do {
                    var lagTracker = WordLagTracker()
                    for try await result in transcriber.results {
                        let starts = result.text.runs.compactMap { $0.audioTimeRange?.start.seconds }
                        let ends = result.text.runs.compactMap { $0.audioTimeRange?.end.seconds }
                        let end = ends.max()
                        let speaker = (starts.min().flatMap { st in end.map { (st, $0) } })
                            .flatMap { SpeakerAligner.speaker(start: $0.0, end: $0.1, segments: self?.diarizer.segments ?? []) }
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

    /// Reinstalls the audio tap with the current input format when engine configuration changes.
    /// Handles format changes from Bluetooth device connect/disconnect, etc. (ADR 0021).
    private func reinstallTap() {
        guard let state = tapState else { return }
        let input = audioEngine.inputNode

        // Remove the old tap.
        input.removeTap(onBus: 0)

        // Get the current input format (may have changed).
        let newInFormat = input.outputFormat(forBus: 0)

        // Check if format changed; if not, reinstalling with the same format is safe.
        // If format changed, we need new converters.
        let formatChanged = newInFormat != state.inFormat

        let inFormatToUse = newInFormat
        var converterToUse: AVAudioConverter?
        var diarConverterToUse: AVAudioConverter?

        // Create new converters if format changed.
        if formatChanged {
            guard let converter = AVAudioConverter(from: newInFormat, to: state.format),
                  let diarConverter = AVAudioConverter(from: newInFormat, to: state.diarFormat) else {
                // If we can't create converters, tap remains removed; audio stops until stop() or
                // another configuration change that allows reconversion.
                return
            }
            converterToUse = converter
            diarConverterToUse = diarConverter
            // Update saved state with the new format.
            self.tapState = TapState(inFormat: newInFormat, format: state.format, diarFormat: state.diarFormat, fed: state.fed, builder: state.builder)
        } else {
            // Format is the same, we can't reuse the old converters (they were captured in the old closure),
            // so create new ones with the same formats.
            guard let converter = AVAudioConverter(from: inFormatToUse, to: state.format),
                  let diarConverter = AVAudioConverter(from: inFormatToUse, to: state.diarFormat) else {
                return
            }
            converterToUse = converter
            diarConverterToUse = diarConverter
        }

        // Install the new tap with the converters.
        guard let converter = converterToUse, let diarConverter = diarConverterToUse else { return }
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormatToUse) { buffer, _ in
            self.processBuffer(
                buffer,
                inFormat: inFormatToUse,
                converter: converter,
                diarConverter: diarConverter,
                format: state.format,
                diarFormat: state.diarFormat,
                fed: state.fed,
                builder: state.builder
            )
        }
    }

    /// Releases the microphone, the speech analyzer and the helpers. Safe to call more than once.
    public func stop() async {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputBuilder?.finish()
        inputBuilder = nil
        interruptionCont?.finish()
        interruptionCont = nil
        resultContinuation = nil
        interruptionObserverTask?.cancel()
        interruptionObserverTask = nil
        tapState = nil
        if let analyzer {
            self.analyzer = nil
            do { try await analyzer.finalizeAndFinishThroughEndOfInput() }
            catch { await analyzer.cancelAndFinishNow() }   // never leave a recognizer allocated
        }
        diarizer.finish()
        soundLabeler.finish()
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

    /// Returns the stream of interruption events (began/ended).
    public func interruptionEvents() -> AsyncStream<InterruptionEvent> {
        interruptionStream ?? AsyncStream { $0.finish() }
    }

    /// Decodes the AVAudioSession interruption options raw value to determine if we should resume.
    /// Pure function for testability (ADR 0021).
    #if os(iOS)
    static func shouldResumeAfterInterruption(optionsRawValue: UInt?) -> Bool {
        guard let rawValue = optionsRawValue else { return false }
        let options = AVAudioSession.InterruptionOptions(rawValue: rawValue)
        return options.contains(.shouldResume)
    }
    #else
    static func shouldResumeAfterInterruption(optionsRawValue: UInt?) -> Bool {
        return false
    }
    #endif
}

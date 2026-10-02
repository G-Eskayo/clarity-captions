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
    /// Spike-only: live diarizer health line.
    public let diagnostics: String
}

/// Audio seconds fed to the analyzer so far; written on the audio thread, read on the results task.
final class FedAudioClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    func add(_ seconds: Double) { lock.lock(); value += seconds; lock.unlock() }
    var seconds: Double { lock.lock(); defer { lock.unlock() }; return value }
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

    /// `diarizerModelURL` has no default on purpose: the app must say where its bundled speaker model
    /// lives, so there is no accidental network path (ADR 0014).
    public init(locale: Locale = Locale(identifier: "en-US"), micMode: MicMode = .standard, diarizerModelURL: URL) {
        self.locale = locale
        self.micMode = micMode
        self.diarizer = LiveDiarizer(modelURL: diarizerModelURL)
    }

    public func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        try await ensureModelInstalled(for: transcriber)
        // Ready before the first audio, so both clocks start at the same first sample.
        try await diarizer.prepare()

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
        let diarizer = self.diarizer
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { buffer, _ in
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
            // Same tap buffer, second path: 16 kHz mono Float32 for the diarizer.
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
                    diarizer.feed(Array(UnsafeBufferPointer(start: ch[0], count: Int(dOut.frameLength))))
                }
            }
            if error == nil {
                fed.add(Double(out.frameLength) / format.sampleRate)
                builder.yield(AnalyzerInput(buffer: out))
            }
        }
        // Load the model before the first word, not on it.
        try await analyzer.prepareToAnalyze(in: format)
        audioEngine.prepare()
        try audioEngine.start()
        try await analyzer.start(inputSequence: sequence)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await result in transcriber.results {
                        let starts = result.text.runs.compactMap { $0.audioTimeRange?.start.seconds }
                        let ends = result.text.runs.compactMap { $0.audioTimeRange?.end.seconds }
                        let end = ends.max()
                        let speaker = (starts.min().flatMap { st in end.map { (st, $0) } })
                            .flatMap { SpeakerAligner.speaker(start: $0.0, end: $0.1, segments: diarizer.segments) }
                        let lag = end.map { max(0, fed.seconds - $0) }
                        continuation.yield(CaptionUpdate(text: String(result.text.characters), isFinal: result.isFinal, lagSeconds: lag, speaker: speaker, diagnostics: diarizer.diagnostics))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stop() async {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        diarizer.finish()
        analyzer = nil
    }

    /// The one-time, system-provisioned model fetch noted in CONTEXT.md "On-device only".
    private func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}

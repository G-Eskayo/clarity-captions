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
}

/// Audio seconds fed to the analyzer so far; written on the audio thread, read on the results task.
final class FedAudioClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    func add(_ seconds: Double) { lock.lock(); value += seconds; lock.unlock() }
    var seconds: Double { lock.lock(); defer { lock.unlock() }; return value }
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

    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    public func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        try await ensureModelInstalled(for: transcriber)

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
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        #endif

        let input = audioEngine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inFormat, to: format) else {
            throw TranscriptionError.converterUnavailable
        }
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
                        let end = result.text.runs.compactMap { $0.audioTimeRange?.end.seconds }.max()
                        let lag = end.map { max(0, fed.seconds - $0) }
                        continuation.yield(CaptionUpdate(text: String(result.text.characters), isFinal: result.isFinal, lagSeconds: lag))
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

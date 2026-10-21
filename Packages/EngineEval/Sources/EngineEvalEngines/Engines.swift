import AVFoundation
import CaptionCore
import EngineEvalKit
import FluidAudio
import Foundation
import Speech
import WhisperKit

/// A speech engine that takes an audio file (#145). The live app uses `CaptioningEngine`, which is shaped for the
/// microphone (start/stop, sound labels, audio levels); the model is the same, files make runs repeatable.
public protocol FileTranscriber: AnyObject {
    var engine: String { get }
    var model: String { get }
    var version: String { get }
    func load() async throws
    func transcribe(_ url: URL) async throws -> String
}

public enum EngineID: String, CaseIterable, Sendable {
    case apple, parakeetV2 = "parakeet-v2", parakeetUltra = "parakeet-ultra", whisperkit
    /// Diagnostic variant: WhisperKit with its no-speech and first-token gates off (short clips come back empty
    /// under the defaults). Not part of the default engine list.
    case whisperkitNoGate = "whisperkit-nogate"

    public static var defaults: [EngineID] { [.apple, .parakeetV2, .parakeetUltra, .whisperkit] }
}

public struct EngineVersions: Sendable {
    public var fluidAudio: String
    public var whisperKit: String
    public var os: String

    public init(fluidAudio: String, whisperKit: String,
                os: String = ProcessInfo.processInfo.operatingSystemVersionString) {
        self.fluidAudio = fluidAudio; self.whisperKit = whisperKit; self.os = os
    }
}

public func makeTranscriber(_ id: EngineID, modelsDir: URL, versions: EngineVersions,
                            whisperModel: String = WhisperKitFileTranscriber.defaultModel) -> FileTranscriber {
    switch id {
    case .apple: return AppleSpeechFileTranscriber(osVersion: versions.os)
    case .parakeetV2: return ParakeetFileTranscriber(version: .v2, name: "parakeet-tdt-0.6b-v2-coreml",
                                                     modelsDir: modelsDir, fluidAudio: versions.fluidAudio)
    case .parakeetUltra: return ParakeetFileTranscriber(version: .ultra, name: "parakeet-ultra-coreml",
                                                        modelsDir: modelsDir, fluidAudio: versions.fluidAudio)
    case .whisperkit: return WhisperKitFileTranscriber(model: whisperModel, modelsDir: modelsDir,
                                                       packageVersion: versions.whisperKit)
    case .whisperkitNoGate: return WhisperKitFileTranscriber(model: whisperModel, modelsDir: modelsDir,
                                                             packageVersion: versions.whisperKit, gates: false)
    }
}

// MARK: - Apple SpeechAnalyzer / SpeechTranscriber

/// Today's engine (ADR 0001). Same transcriber options as the app's TranscriptionEngine (`fastResults`, no
/// transcription options), en-US, final results only. The asset installs through CaptionCore's
/// SpeechModelInstaller, the app's own AssetInventory path.
public final class AppleSpeechFileTranscriber: FileTranscriber {
    public let engine = "apple-speechanalyzer"
    public let model = "SpeechTranscriber en-US"
    public let version: String
    private let locale = Locale(identifier: "en-US")

    public init(osVersion: String) { version = "macOS \(osVersion)" }

    public func load() async throws {
        try await SpeechModelInstaller.install(locale: locale) { _ in }
        guard await SpeechModelInstaller.isInstalled(locale: locale) else {
            throw NSError(domain: "EngineEval", code: 1, userInfo: [NSLocalizedDescriptionKey: "en-US speech asset not installed"])
        }
    }

    public func transcribe(_ url: URL) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.fastResults],
                                            attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collect = Task { () throws -> String in
            var parts: [String] = []
            for try await result in transcriber.results where result.isFinal {
                parts.append(String(result.text.characters))
            }
            return parts.joined(separator: " ")
        }
        do {
            let file = try AVAudioFile(forReading: url)
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collect.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
        return try await collect.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Parakeet via FluidAudio (Core ML, Neural Engine)

public final class ParakeetFileTranscriber: FileTranscriber {
    public let engine = "parakeet-fluidaudio"
    public let model: String
    public let version: String
    private let asrVersion: AsrModelVersion
    private let modelsDir: URL
    private var manager: AsrManager?
    private var decoderLayers = 2
    private let converter = AudioConverter()

    public init(version: AsrModelVersion, name: String, modelsDir: URL, fluidAudio: String) {
        asrVersion = version; model = name; self.modelsDir = modelsDir
        self.version = "FluidAudio \(fluidAudio)"
    }

    public func load() async throws {
        let dir = modelsDir.appendingPathComponent("fluidaudio").appendingPathComponent(model)
        let models = try await AsrModels.downloadAndLoad(to: dir, version: asrVersion)
        let m = AsrManager(config: .default)
        try await m.loadModels(models)
        decoderLayers = asrVersion.decoderLayers
        manager = m
    }

    public func transcribe(_ url: URL) async throws -> String {
        try await transcribe(samples: try converter.resampleAudioFile(url))
    }

    /// 16 kHz mono samples; clips under FluidAudio's 1 s minimum get trailing silence.
    public func transcribe(samples: [Float]) async throws -> String {
        try await transcribeWithTimings(samples: samples).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func transcribeWithTimings(samples: [Float]) async throws -> ASRResult {
        guard let manager else { throw NSError(domain: "EngineEval", code: 2) }
        var state = TdtDecoderState.make(decoderLayers: decoderLayers)  // fresh per clip: clips are independent
        let padded = SilencePadding.padded(samples, toAtLeast: ASRConstants.minimumRequiredSamples(forSampleRate: 16000))
        return try await manager.transcribe(padded, decoderState: &state)
    }
}

// MARK: - WhisperKit (argmax-oss-swift)

public final class WhisperKitFileTranscriber: FileTranscriber {
    public static let defaultModel = "openai_whisper-large-v3-v20240930_turbo"
    public let engine: String
    public let model: String
    public let version: String
    private let modelsDir: URL
    private var kit: WhisperKit?
    /// English, transcribe, WhisperKit's default decoding (temperature 0 with its standard fallback); with
    /// `gates: false` the no-speech and first-token log-prob gates are off.
    private let options: DecodingOptions

    public init(model: String, modelsDir: URL, packageVersion: String, gates: Bool = true) {
        self.model = model; self.modelsDir = modelsDir
        engine = gates ? "whisperkit" : "whisperkit-nogate"
        options = gates
            ? DecodingOptions(verbose: false, task: .transcribe, language: "en", detectLanguage: false)
            : DecodingOptions(verbose: false, task: .transcribe, language: "en", detectLanguage: false,
                              firstTokenLogProbThreshold: nil, noSpeechThreshold: nil)
        version = "argmax-oss-swift \(packageVersion), language en, "
            + (gates ? "default decoding" : "default decoding but noSpeechThreshold and firstTokenLogProbThreshold off")
    }

    public func load() async throws {
        let base = modelsDir.appendingPathComponent("whisperkit")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        kit = try await WhisperKit(WhisperKitConfig(model: model, downloadBase: base, verbose: false,
                                                    logLevel: .error, prewarm: true, load: true, download: true))
    }

    public func transcribe(_ url: URL) async throws -> String {
        guard let kit else { throw NSError(domain: "EngineEval", code: 3) }
        let results = try await kit.transcribe(audioPath: url.path, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func transcribe(samples: [Float]) async throws -> String {
        guard let kit else { throw NSError(domain: "EngineEval", code: 3) }
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

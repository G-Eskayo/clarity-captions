import AVFoundation
import EngineEvalKit
import FluidAudio
import Foundation
import Speech
import WhisperKit

// Streaming latency (#145): how soon after a word is said does it show up correctly?
// Apple SpeechAnalyzer streams natively, so it is fed in real time (100 ms buffers, wall clock since the first
// buffer, the same clock as the app's FedWallTime / CaptionUpdate.lagSeconds). Parakeet and WhisperKit aren't
// natively streaming in the way the app would use them, so they run the standard growing window
// (GrowingWindow.simulate) with measured compute. Scoring happens in scripts/engine-eval/edacc_eval/latency.py.

public struct StreamLine: Codable {
    public var kind = "stream"
    public let clipID: String
    public let engine: String
    public let model: String
    public let method: String
    public let audioSeconds: Double
    public let updates: [StreamUpdate]

    enum CodingKeys: String, CodingKey {
        case kind, clipID = "clip_id", engine, model, method, audioSeconds = "audio_seconds", updates
    }
}

public struct TimingLine: Codable {
    public var kind = "timing"
    public let clipID: String
    public let engine: String
    public let model: String
    public let words: [TimedWord]

    enum CodingKeys: String, CodingKey { case kind, clipID = "clip_id", engine, model, words }
}

public protocol StreamingLatencyEngine: AnyObject {
    var engine: String { get }
    var model: String { get }
    var method: String { get }
    func load() async throws
    func stream(samples: [Float]) async throws -> [StreamUpdate]
}

private func seconds(_ d: Duration) -> Double {
    Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

private final class UpdateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [StreamUpdate] = []
    func add(_ u: StreamUpdate) { lock.lock(); items.append(u); lock.unlock() }
    var all: [StreamUpdate] { lock.lock(); defer { lock.unlock() }; return items }
}

/// Apple SpeechAnalyzer fed live: the app's options (volatile + fast results), the app's display rule
/// (finals accumulate, the latest volatile result replaces the tail).
public final class AppleLiveLatency: StreamingLatencyEngine {
    public let engine = "apple-speechanalyzer"
    public let model = "SpeechTranscriber en-US"
    public let method = "native streaming, fed in real time (100 ms buffers), volatile + final results"
    private let chunk: Double
    private let locale = Locale(identifier: "en-US")

    public init(chunk: Double = 0.1) { self.chunk = chunk }

    public func load() async throws {
        try await AppleSpeechFileTranscriber(osVersion: "").load()
    }

    public func stream(samples: [Float]) async throws -> [StreamUpdate] {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1,
                                            interleaved: false),
              let converter = AVAudioConverter(from: srcFormat, to: format) else {
            throw NSError(domain: "EngineEval", code: 10, userInfo: [NSLocalizedDescriptionKey: "no audio format"])
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)  // like the app: model ready before the first word
        let (sequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let log = UpdateLog()
        let clock = ContinuousClock()
        let t0 = clock.now
        let collect = Task {
            var display = DisplayedText()
            for try await result in transcriber.results {
                let shown = display.apply(String(result.text.characters), isFinal: result.isFinal)
                log.add(StreamUpdate(t: seconds(clock.now - t0), text: shown))
            }
        }
        try await analyzer.start(inputSequence: sequence)
        let per = Int(chunk * 16_000)
        var k = 0
        while k * per < samples.count {
            let slice = Array(samples[(k * per)..<min((k + 1) * per, samples.count)])
            // A buffer is available once its last sample has been "spoken".
            try await Task.sleep(until: t0 + .seconds(Double(k * per + slice.count) / 16_000), clock: .continuous)
            if let buf = convert(slice, from: srcFormat, with: converter, to: format) {
                builder.yield(AnalyzerInput(buffer: buf))
            }
            k += 1
        }
        builder.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await collect.value
        return log.all
    }

    private func convert(_ samples: [Float], from src: AVAudioFormat, with converter: AVAudioConverter,
                         to dst: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let input = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let ratio = dst.sampleRate / src.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: AVAudioFrameCount(Double(samples.count) * ratio) + 1024)
        else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return input
        }
        return error == nil ? out : nil
    }
}

/// Parakeet (FluidAudio) on the growing window. FluidAudio 0.17.5's own SlidingWindowAsrManager only emits a
/// window once 11 s of chunk + 2 s of right context exist, a 13 s floor, so it isn't a fair live-caption mode.
public final class ParakeetWindowLatency: StreamingLatencyEngine {
    public let engine = "parakeet-fluidaudio"
    public let model: String
    public let method: String
    private let inner: ParakeetFileTranscriber
    private let hop: Double

    public init(version: AsrModelVersion, name: String, modelsDir: URL, hop: Double) {
        model = name; self.hop = hop
        method = "growing window, re-decode all audio so far, hop \(hop) s, simulated clock + measured compute"
        inner = ParakeetFileTranscriber(version: version, name: name, modelsDir: modelsDir, fluidAudio: "")
    }

    public func load() async throws { try await inner.load() }

    public func stream(samples: [Float]) async throws -> [StreamUpdate] {
        let duration = Double(samples.count) / 16_000
        return try await GrowingWindow.simulate(duration: duration, hop: hop) { a in
            let n = min(samples.count, Int((a * 16_000).rounded()))
            let start = ContinuousClock.now
            let text = try await inner.transcribe(samples: Array(samples[0..<n]))
            return (text, seconds(ContinuousClock.now - start))
        }
    }

    /// Offline decode of the whole clip with token times: the reference for "when was each word said".
    public func wordTimes(samples: [Float]) async throws -> [TimedWord] {
        let r = try await inner.transcribeWithTimings(samples: samples)
        return WordTiming.group((r.tokenTimings ?? []).map { ($0.token, $0.startTime, $0.endTime) })
    }
}

public final class WhisperKitWindowLatency: StreamingLatencyEngine {
    public let engine = "whisperkit"
    public let model: String
    public let method: String
    private let inner: WhisperKitFileTranscriber
    private let hop: Double

    public init(model: String, modelsDir: URL, hop: Double) {
        self.model = model; self.hop = hop
        method = "growing window, re-decode all audio so far, hop \(hop) s, simulated clock + measured compute"
        inner = WhisperKitFileTranscriber(model: model, modelsDir: modelsDir, packageVersion: "")
    }

    public func load() async throws { try await inner.load() }

    public func stream(samples: [Float]) async throws -> [StreamUpdate] {
        let duration = Double(samples.count) / 16_000
        return try await GrowingWindow.simulate(duration: duration, hop: hop) { a in
            let n = min(samples.count, Int((a * 16_000).rounded()))
            let start = ContinuousClock.now
            let text = try await inner.transcribe(samples: Array(samples[0..<n]))
            return (text, seconds(ContinuousClock.now - start))
        }
    }
}

/// Runs the latency sample: every clip up to `maxClipSeconds` in the shard, every engine, resumable by
/// (kind, clip, engine, model).
public struct LatencyRunner {
    public let shardDir: URL
    public let out: URL
    public let maxClipSeconds: Double
    public let status: StatusFile?

    public init(shardDir: URL, out: URL, maxClipSeconds: Double, status: StatusFile?) {
        self.shardDir = shardDir; self.out = out; self.maxClipSeconds = maxClipSeconds; self.status = status
    }

    private func doneKeys() -> Set<String> {
        guard let data = try? Data(contentsOf: out) else { return [] }
        var keys = Set<String>()
        for raw in data.split(separator: UInt8(ascii: "\n")) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(raw)) as? [String: Any],
                  let kind = obj["kind"] as? String, let clip = obj["clip_id"] as? String,
                  let engine = obj["engine"] as? String, let model = obj["model"] as? String else { continue }
            keys.insert("\(kind)|\(clip)|\(engine)|\(model)")
        }
        return keys
    }

    private func append<T: Encodable>(_ line: T) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try enc.encode(line)
        data.append(UInt8(ascii: "\n"))
        if !FileManager.default.fileExists(atPath: out.path) {
            try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: out.path, contents: nil)
        }
        let fh = try FileHandle(forWritingTo: out)
        defer { try? fh.close() }
        // A crash mid-write leaves a partial line; start on a fresh one.
        let end = try fh.seekToEnd()
        if end > 0 {
            try fh.seek(toOffset: end - 1)
            if fh.readData(ofLength: 1) != Data([UInt8(ascii: "\n")]) { try fh.write(contentsOf: Data([UInt8(ascii: "\n")])) }
            try fh.seekToEnd()
        }
        try fh.write(contentsOf: data)
        try fh.synchronize()
    }

    public func run(_ engine: StreamingLatencyEngine, clips: [ManifestClip], timing: ParakeetWindowLatency? = nil) async throws {
        let sample = clips.filter { $0.audioSeconds <= maxClipSeconds }
        var done = doneKeys()
        let pending = sample.filter { !done.contains("stream|\($0.clipID)|\(engine.engine)|\(engine.model)") }
        print("LATENCY-START \(engine.engine) \(engine.model): \(pending.count) of \(sample.count) clips to run")
        if pending.isEmpty { return }
        try await engine.load()
        let converter = AudioConverter()
        var finished = sample.count - pending.count
        for clip in pending {
            do {
                let samples = try converter.resampleAudioFile(shardDir.appendingPathComponent(clip.file))
                if let timing, !done.contains("timing|\(clip.clipID)|\(timing.engine)|\(timing.model)") {
                    let words = try await timing.wordTimes(samples: samples)
                    try append(TimingLine(clipID: clip.clipID, engine: timing.engine, model: timing.model, words: words))
                    done.insert("timing|\(clip.clipID)|\(timing.engine)|\(timing.model)")
                }
                let ups = try await engine.stream(samples: samples)
                try append(StreamLine(clipID: clip.clipID, engine: engine.engine, model: engine.model,
                                      method: engine.method, audioSeconds: clip.audioSeconds, updates: ups))
                finished += 1
            } catch {
                print("LATENCY-ERROR \(engine.engine) \(clip.clipID): \(error)")
            }
            status?.update(engine: "latency \(engine.engine) \(engine.model)", done: finished, total: sample.count,
                           eta: nil, note: engine.method)
        }
        print("LATENCY-DONE \(engine.engine) \(engine.model): \(finished)/\(sample.count)")
    }
}

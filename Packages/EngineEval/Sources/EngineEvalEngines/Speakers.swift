import AVFoundation
import CaptionCore
import EngineEvalKit
import FluidAudio
import Foundation

/// `engine-eval speakers` (#271): one recording through the app's live speaker path (`SpeakerPathReplay`), written as
/// one JSON object for scripts/engine-eval/speaker_eval to score. One process per recording, so the peak memory it
/// reports is that recording's alone.
public enum SpeakerEval {
    public enum Failure: Error, CustomStringConvertible {
        case notSixteenKMono(Double, UInt32)
        public var description: String {
            switch self {
            case .notSixteenKMono(let sr, let ch): "audio must be 16 kHz mono (got \(sr) Hz, \(ch) channels)"
            }
        }
    }

    /// Streams a 16 kHz mono file a second at a time.
    final class FileSource {
        let file: AVAudioFile
        let buffer: AVAudioPCMBuffer
        init(_ url: URL) throws {
            file = try AVAudioFile(forReading: url)
            let f = file.processingFormat
            guard f.sampleRate == SpeakerPathReplay.sampleRate, f.channelCount == 1 else {
                throw Failure.notSixteenKMono(f.sampleRate, f.channelCount)
            }
            buffer = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: 16_000)!
        }
        func next() throws -> [Float]? {
            guard file.framePosition < file.length else { return nil }
            try file.read(into: buffer, frameCount: 16_000)
            guard buffer.frameLength > 0 else { return nil }
            return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        }
    }

    /// The kernel's own high-water mark of this process's footprint (sampling between buffers can miss a spike).
    static func lifetimePeakFootprint() -> UInt64? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        return rc == 0 ? info.ri_lifetime_max_phys_footprint : nil
    }

    static func stats(_ xs: [Double]) -> [String: Double] {
        guard !xs.isEmpty else { return [:] }
        let s = xs.sorted()
        func q(_ p: Double) -> Double { s[min(s.count - 1, Int((p * Double(s.count - 1)).rounded()))] }
        return ["mean": s.reduce(0, +) / Double(s.count), "p50": q(0.5), "p95": q(0.95), "p99": q(0.99), "max": s.last!]
    }

    public static func run(audio: URL, phrasesFile: URL, model: URL, modelLabel: String, recording: String,
                           fluidAudio: String, out: URL) async throws {
        let phrases = try JSONDecoder().decode([SpeakerReplayPhrase].self, from: Data(contentsOf: phrasesFile))
        let source = try FileSource(audio)
        let before = MemoryFootprint.current() ?? 0
        var peak = before
        var loaded: UInt64?
        let wall0 = Date()
        let r = try await SpeakerPathReplay.run(next: source.next, phrases: phrases, modelURL: model, onChunk: { _ in
            let now = MemoryFootprint.current() ?? 0
            if loaded == nil { loaded = now }
            peak = max(peak, now)
        })
        let wall = Date().timeIntervalSince(wall0)
        let mb = { (b: UInt64) in Double(b) / 1_048_576 }
        let doc: [String: Any] = [
            "recording": recording, "model": modelLabel, "model_path": model.path, "fluidaudio": fluidAudio,
            "host": ProcessInfo.processInfo.hostName, "finished_at": ISO8601DateFormatter().string(from: Date()),
            "audio_seconds": r.audioSeconds, "load_seconds": r.loadSeconds, "wall_seconds": wall,
            "chunk_ms": stats(r.chunkMillis), "chunk_audio_ms": Double(SpeakerPathReplay.appChunk) / 16.0,
            "footprint_mb": ["before": mb(before), "first_chunk": mb(loaded ?? before), "peak": mb(peak),
                             "lifetime_peak": mb(lifetimePeakFootprint() ?? peak)],
            "phrases": phrases.count,
            "emissions": r.emissions.map { e -> [String: Any] in
                ["now": e.now, "phrase": e.phrase, "final": e.isFinal, "label": e.label as Any, "raw": e.rawSlot as Any]
            },
            "segments": r.finalSegments.map { ["speaker": $0.speaker, "start": $0.start, "end": $0.end] },
        ]
        let data = try JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys])
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = out.appendingPathExtension("part")
        try data.write(to: tmp)
        _ = try? FileManager.default.removeItem(at: out)
        try FileManager.default.moveItem(at: tmp, to: out)   // a crash never leaves a half result that looks done
        print(String(format: "SPEAKER-EVAL-RESULT %@ %@ audio %.0fs wall %.0fs (x%.0f) peak %.0f MB emissions %d",
                     recording, modelLabel, r.audioSeconds, wall, r.audioSeconds / max(wall, 0.001), mb(peak),
                     r.emissions.count))
    }
}

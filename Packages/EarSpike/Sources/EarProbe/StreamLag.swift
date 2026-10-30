@preconcurrency import AVFoundation
import CoreMedia
import EarSpikeKit
import Foundation
import Speech

/// One finished caption line from a live-paced stream: what the translator would get, and when.
public struct LineTiming: Codable, Sendable {
    public let text: String
    public let audioEndS: Double       // end of the line's speech, audio time
    public let finalAtS: Double        // when the finished line arrived, same clock (wall time since the first buffer)
    public let finishLagMs: Double     // finalAt - audioEnd: end of speech to finished line
    public let headStart3Ms: Double?   // how much sooner the first 3 words were already right for good
    public let headStart5Ms: Double?
    public let afterInputEnded: Bool   // forced out by the end of the stream, not by the engine's own endpointing
}

/// Apple's SpeechTranscriber fed in real time like the app (#145, Latency.swift): 100 ms buffers, volatile + fast
/// results, audio time ranges. Each final's lag is measured from the end of its own audio.
public enum StreamLag {
    public static func run(_ audio: AVAudioPCMBuffer, locale: Locale, chunk: Double = 0.1) async throws -> [LineTiming] {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults],
                                            attributeOptions: [.audioTimeRange])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw NSError(domain: "EarSpike", code: 1, userInfo: [NSLocalizedDescriptionKey: "no analyzer format"])
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        let (sequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let clock = ContinuousClock()
        let t0 = clock.now
        func now() -> Double { let d = clock.now - t0; return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }
        let inputEnd = Double(audio.frameLength) / audio.format.sampleRate

        let collect = Task { () throws -> [LineTiming] in
            var lines: [LineTiming] = []
            var volatile: [(t: Double, text: String)] = []
            for try await result in transcriber.results {
                let t = now()
                let text = String(result.text.characters)
                guard result.isFinal else { volatile.append((t, text)); continue }
                defer { volatile.removeAll() }
                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                let end = CMTimeGetSeconds(CMTimeRangeGetEnd(result.range))
                func head(_ n: Int) -> Double? { PhraseTiming.stableAt(updates: volatile, final: text, words: n).map { (t - $0) * 1000 } }
                lines.append(LineTiming(text: text, audioEndS: end, finalAtS: t, finishLagMs: (t - end) * 1000,
                                        headStart3Ms: head(3), headStart5Ms: head(5), afterInputEnded: t > inputEnd + 0.05))
            }
            return lines
        }
        try await analyzer.start(inputSequence: sequence)
        let converter = AVAudioConverter(from: audio.format, to: format)!
        let per = AVAudioFrameCount(chunk * audio.format.sampleRate)
        var offset: AVAudioFrameCount = 0
        while offset < audio.frameLength {
            let n = min(per, audio.frameLength - offset)
            let slice = AVAudioPCMBuffer(pcmFormat: audio.format, frameCapacity: n)!
            slice.frameLength = n
            memcpy(slice.floatChannelData![0], audio.floatChannelData![0] + Int(offset), Int(n) * 4)
            offset += n
            // A buffer is available once its last sample has been "spoken".
            try await Task.sleep(until: t0 + .seconds(Double(offset) / audio.format.sampleRate), clock: .continuous)
            let out = AVAudioPCMBuffer(pcmFormat: format,
                                       frameCapacity: AVAudioFrameCount(Double(n) * format.sampleRate / audio.format.sampleRate) + 1024)!
            var fed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return slice
            }
            if err == nil { builder.yield(AnalyzerInput(buffer: out)) }
        }
        builder.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collect.value
    }
}

/// EdAcc clips (real conversational English, 16 kHz) from a shard of the engine test (#145).
public struct EdaccClip: Decodable, Sendable {
    public let clipID: String; public let reference: String; public let audioSeconds: Double; public let file: String
    enum CodingKeys: String, CodingKey { case clipID = "clip_id", reference, audioSeconds = "audio_seconds", file }

    public static func load(shard: URL, min: Double, max: Double, count: Int) throws -> [EdaccClip] {
        let text = try String(contentsOf: shard.appendingPathComponent("manifest.jsonl"), encoding: .utf8)
        let all = text.split(separator: "\n").compactMap { try? JSONDecoder().decode(EdaccClip.self, from: Data($0.utf8)) }
        return Array(all.filter { $0.audioSeconds >= min && $0.audioSeconds <= max }.prefix(count))
    }

    public func audio(in shard: URL) throws -> AVAudioPCMBuffer {
        let f = try AVAudioFile(forReading: shard.appendingPathComponent(file))
        let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try f.read(into: b)
        return try AudioFiles.resample([b], to: 16000)
    }
}

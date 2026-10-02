import AVFoundation
import XCTest
@testable import CaptionCore

/// Network + model download + macOS `say`, so opt-in: CAPTION_INTEGRATION=1 swift test --filter DiarizerIntegration
/// Feeds two clearly different synthetic voices, alternating, straight into LiveDiarizer. Separates
/// "the pipeline can't tell two voices apart" from "far-field mic / real-room conditions".
final class DiarizerIntegrationTests: XCTestCase {
    private func synth(voice: String, text: String) throws -> [Float] {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID()).wav")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@16000", text]
        try p.run(); p.waitUntilExit()
        let file = try AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    }

    func testTwoSyntheticVoicesAreSeparated() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_INTEGRATION"] == "1", "opt-in")
        let a = "Hello there, how was your day? I went for a long walk this morning and then made some coffee."
        let b = "Pretty good, thanks for asking. I spent most of the afternoon fixing the old bicycle in the garage."
        let silence = [Float](repeating: 0, count: 8000)
        var audio: [Float] = []
        for _ in 0..<2 { audio += try synth(voice: "Samantha", text: a) + silence + (try synth(voice: "Daniel", text: b)) + silence }

        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = ProcessInfo.processInfo.environment["CAPTION_DIARIZER_MODEL"].map { URL(fileURLWithPath: $0) }
            ?? repo.appendingPathComponent("Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc")
        let d = LiveDiarizer(modelURL: model)
        try await d.prepare()
        var i = 0
        while i < audio.count { d.feed(Array(audio[i..<min(i + 1600, audio.count)])); i += 1600 }
        d.finish()
        let segs = d.segments
        print("DIAR-RESULT total \(Double(audio.count) / 16000)s :: \(d.diagnostics)")
        for s in segs { print("DIAR-SEG speaker \(s.speaker + 1) \(String(format: "%.1f", s.start))-\(String(format: "%.1f", s.end))") }
        XCTAssertGreaterThanOrEqual(Set(segs.map(\.speaker)).count, 2, "two distinct voices should yield two speakers")
    }
}

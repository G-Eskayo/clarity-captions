import AVFoundation
import XCTest
@testable import CaptionCore

/// Opt-in, real model (#220): CAPTION_ZIPFORMER=<folder with Encoder, Decoder, Joiner and tokens.txt> swift test
/// --filter ZipformerIntegration. Speaks Hebrew with macOS's Carmit voice, feeds it to the backend at real-time pace
/// in 100 ms pieces, as the microphone path does, and checks the words, their order and the per-chunk cost.
final class ZipformerIntegrationTests: XCTestCase {
    private func folder() throws -> URL {
        let path = ProcessInfo.processInfo.environment["CAPTION_ZIPFORMER"] ?? ""
        try XCTSkipIf(path.isEmpty, "opt-in: set CAPTION_ZIPFORMER to a build folder")
        return URL(fileURLWithPath: path)
    }

    private func speech(_ text: String) throws -> [Float] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zipformer-it-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("he.wav")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "Carmit", "-o", url.path, "--data-format=LEF32@16000", text]
        try p.run(); p.waitUntilExit()
        try XCTSkipIf(p.terminationStatus != 0, "the Carmit voice is not installed")
        let file = try AVAudioFile(forReading: url)
        let buf = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buf)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    }

    private static func words(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    func testHebrewSpeechComesOutAsHebrewWordsInOrderFasterThanRealTime() async throws {
        let said = "שלום, מה שלומך היום? אני רוצה לספר לך על הטיול שלנו לירושלים. היה מזג אוויר נעים מאוד, "
            + "וטיילנו בעיר העתיקה עד הערב."
        let audio = try speech(said)
        let backend = ZipformerBackend(modelURL: try folder())
        let loadStart = ContinuousClock.now
        try await backend.prepare()
        let load = ContinuousClock.now - loadStart
        let costs = Costs()
        backend.onDecode = { costs.add($0) }
        let stream = try await backend.start()
        let collected = Task { () -> (finals: [String], volatile: Int) in
            var finals: [String] = []; var volatile = 0
            for try await p in stream { if p.isFinal { finals.append(p.text) } else { volatile += 1 } }
            return (finals, volatile)
        }
        let piece = 1_600
        var i = 0
        while i < audio.count {
            backend.feed(samples16k: Array(audio[i..<min(audio.count, i + piece)]), level: -20)
            i += piece
            try await Task.sleep(for: .milliseconds(100))
        }
        await backend.finish()
        let (finals, volatile) = try await collected.value
        let got = Self.words(finals.joined(separator: " ")), want = Self.words(said)
        let errors = editDistance(got, want)
        let c = costs.all.sorted()
        print("ZIPFORMER-IT finals: \(finals.joined(separator: " | "))")
        print(String(format: "ZIPFORMER-IT load %.2f s, %d word errors of %d, chunk compute median %.0f ms max %.0f ms over %d",
                     Double(load.components.seconds) + Double(load.components.attoseconds) / 1e18, errors, want.count,
                     1000 * c[c.count / 2], 1000 * (c.last ?? 0), c.count))
        XCTAssertGreaterThan(volatile, 0, "words show as a volatile tail before they settle")
        XCTAssertLessThanOrEqual(Double(errors) / Double(want.count), 0.25, "synthetic speech, loose bound")
        XCTAssertLessThan(c[c.count / 2], 1.28, "each 1.28 s chunk decodes in less than 1.28 s")
    }

    private final class Costs: @unchecked Sendable {
        private let lock = NSLock(); private var v: [Double] = []
        func add(_ s: Double) { lock.withLock { v.append(s) } }
        var all: [Double] { lock.withLock { v } }
    }

    private func editDistance(_ a: [String], _ b: [String]) -> Int {
        var row = Array(0...b.count)
        for i in 1...max(1, a.count) where !a.isEmpty {
            var prev = row[0]; row[0] = i
            for j in 1...max(1, b.count) where !b.isEmpty {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }
}

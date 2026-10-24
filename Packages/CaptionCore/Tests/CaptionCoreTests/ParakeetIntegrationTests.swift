import XCTest
@testable import CaptionCore

/// Opt-in, real model (design §8, test 9): CAPTION_PARAKEET=1 swift test --filter ParakeetIntegration
/// Needs scripts/fetch-asr-models.sh and scripts/fetch-diarizer-models.sh. Replays spoken audio through the whole
/// engine at real-time pace with ModelHub offline, and checks what a reader would see.
final class ParakeetIntegrationTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func speech(_ text: String, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parakeet-it-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("\(name).wav")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "Samantha", "-o", url.path, "--data-format=LEF32@16000", text]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        return url
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    func testReplayCaptionsTheWordsOnceInOrder() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_PARAKEET"] == "1", "opt-in")
        let said = "The quick brown fox jumps over the lazy dog. She sells seashells by the seashore. "
            + "How much wood would a woodchuck chuck if a woodchuck could chuck wood. "
            + "These pretzels are making me thirsty, and the weather is here."
        let audio = try speech(said, name: "speech")
        let engine = TranscriptionEngine(
            diarizerModelURL: repo.appendingPathComponent("Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc"),
            recognizer: .parakeet(modelURL: repo.appendingPathComponent("Apps/Spike/Resources/Models/ParakeetUltra")))
        var stream = CaptionStream()
        var finals: [String] = []
        var lags: [Double] = []
        var volatileCount = 0
        for try await u in try await engine.startReplaying(fileURL: audio) {
            stream.apply(text: u.text, isFinal: u.isFinal, speaker: u.speaker,
                         range: u.startSeconds.flatMap { s in u.endSeconds.map { s...$0 } }, wordEmphasis: u.wordEmphasis)
            if u.isFinal { finals.append(u.text) } else { volatileCount += 1 }
            if let lag = u.lagSeconds { lags.append(lag) }
        }
        XCTAssertEqual(engine.engineName, "parakeet-ultra-pal6")
        XCTAssertNil(engine.fallbackReason)
        XCTAssertGreaterThan(volatileCount, 0, "words show as a volatile tail before they settle")
        let got = Self.words(finals.joined(separator: " ")), want = Self.words(said)
        let shown = Self.words(stream.lines.map(\.text).joined(separator: " "))
        XCTAssertEqual(shown, got, "the screen shows the finals, nothing extra left over")
        let errors = editDistance(got, want)
        print("PARAKEET-IT finals: \(finals.joined(separator: " | "))")
        print(String(format: "PARAKEET-IT word errors %d of %d (%.1f%%), lag median %.2f s over %d samples",
                     errors, want.count, 100 * Double(errors) / Double(want.count),
                     lags.sorted()[lags.count / 2], lags.count))
        XCTAssertLessThanOrEqual(Double(errors) / Double(want.count), 0.10)
    }

    func testMissingModelFallsBackToAppleAndStillCaptions() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_PARAKEET"] == "1", "opt-in")
        let audio = try speech("Captions keep flowing when the model is missing.", name: "fallback")
        let engine = TranscriptionEngine(
            diarizerModelURL: repo.appendingPathComponent("Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc"),
            recognizer: .parakeet(modelURL: URL(fileURLWithPath: "/nonexistent/ParakeetUltra")))
        var text = ""
        for try await u in try await engine.startReplaying(fileURL: audio) where u.isFinal { text += " " + u.text }
        XCTAssertEqual(engine.fallbackReason, .loadFailed)
        XCTAssertEqual(engine.engineName, "apple-speechanalyzer")
        XCTAssertTrue(text.lowercased().contains("captions"), text)
    }

    private func editDistance(_ a: [String], _ b: [String]) -> Int {
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var prev = row[0]; row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }
}

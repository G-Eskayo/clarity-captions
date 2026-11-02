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

    private func speech(_ text: String, name: String, voice: String = "Samantha") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parakeet-it-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("\(name).wav")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@16000", text]
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

    func testAMemoryWarningMidSessionSwitchesToAppleAndCaptionsKeepFlowing() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_PARAKEET"] == "1", "opt-in")
        let said = "The birch canoe slid on the smooth planks. Glue the sheet to the dark blue background. "
            + "It is easy to tell the depth of a well. These days a chicken leg is a rare dish. "
            + "Rice is often served in round bowls. The juice of lemons makes fine punch."
        let audio = try speech(said, name: "switch")
        let engine = TranscriptionEngine(
            diarizerModelURL: repo.appendingPathComponent("Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc"),
            recognizer: .parakeet(modelURL: repo.appendingPathComponent("Apps/Spike/Resources/Models/ParakeetUltra")))
        let counted = Counter()
        engine.onFallback = { _ in counted.bump() }
        var finals: [(engine: String, text: String)] = []
        var lastEnd = -1.0
        let started = Date()
        var fired = false
        for try await u in try await engine.startReplaying(fileURL: audio) {
            if u.isFinal {
                finals.append((u.engine, u.text))
                if let s = u.startSeconds { XCTAssertGreaterThanOrEqual(s, lastEnd - 1.5, "finals move forward in time") }
                lastEnd = max(lastEnd, u.endSeconds ?? lastEnd)
            }
            if !fired, Date().timeIntervalSince(started) > 6 {
                fired = true
                engine.handle(.memoryWarning)
                engine.handle(.memoryWarning)   // a second warning during the switch changes nothing
            }
        }
        print("PARAKEET-IT switch: " + finals.map { "[\($0.engine)] \($0.text)" }.joined(separator: " "))
        XCTAssertEqual(engine.fallbackReason, .memoryWarning)
        XCTAssertEqual(engine.engineName, "apple-speechanalyzer")
        XCTAssertEqual(counted.value, 1, "one fallback counts once toward the daily pin")
        XCTAssertTrue(finals.contains { $0.engine == "parakeet-ultra-pal6" }, "Parakeet's words before the switch were kept as final")
        let after = finals.filter { $0.engine == "apple-speechanalyzer" }.map(\.text).joined(separator: " ").lowercased()
        XCTAssertTrue(after.contains("lemons") || after.contains("punch"), "Apple captioned the rest: \(after)")
    }

    // MARK: #234: a language Parakeet won, end to end

    /// The engine the app would make for a caption language (CaptionEngineFactory.make, without the app target).
    private func engine(for id: String) -> TranscriptionEngine {
        let plan = CaptionEnginePlan.make(captionLanguage: Locale(identifier: id), choice: .parakeet, now: Date(),
                                          recentFallbacks: [], availableMemory: .max, modelPresent: true)
        let models = repo.appendingPathComponent("Apps/Spike/Resources/Models")
        let recognizer: SpeechRecognizerSetup = plan.selection.engine == .parakeet
            ? .parakeet(modelURL: models.appendingPathComponent("ParakeetUltra")) : .apple
        return TranscriptionEngine(locale: plan.locale, diarizerModelURL: models.appendingPathComponent("Sortformer_v2.1.mlmodelc"),
                                   recognizer: recognizer, startReason: plan.selection.reason)
    }

    func testSpanishCaptionsRunOnParakeetAndComeOutSpanish() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_PARAKEET"] == "1", "opt-in")
        let said = "El tren sale de la estación a las ocho de la mañana. Mi hermana vive en una casa pequeña cerca "
            + "del río. Los niños juegan en el parque cuando hace buen tiempo. Mañana vamos a comer con nuestros abuelos."
        let audio = try speech(said, name: "es", voice: "Eddy (Spanish (Spain))")
        let engine = engine(for: "es-ES")
        var finals: [String] = []
        for try await u in try await engine.startReplaying(fileURL: audio) where u.isFinal { finals.append(u.text) }
        XCTAssertEqual(engine.engineName, "parakeet-ultra-pal6")
        XCTAssertNil(engine.fallbackReason)
        let got = Self.words(finals.joined(separator: " ")), want = Self.words(said)
        let errors = editDistance(got, want)
        print("PARAKEET-IT es finals: \(finals.joined(separator: " | "))")
        print(String(format: "PARAKEET-IT es word errors %d of %d (%.1f%%)", errors, want.count,
                     100 * Double(errors) / Double(want.count)))
        XCTAssertLessThanOrEqual(Double(errors) / Double(want.count), 0.15)
    }

    func testAMemoryWarningInSpanishFallsBackToAppleInSpanish() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_PARAKEET"] == "1", "opt-in")
        let said = "El tren sale de la estación a las ocho de la mañana. Mi hermana vive en una casa pequeña cerca "
            + "del río. Los niños juegan en el parque cuando hace buen tiempo. Mañana vamos a comer con nuestros abuelos. "
            + "El zumo de limón es muy bueno para la garganta."
        let audio = try speech(said, name: "es-switch", voice: "Eddy (Spanish (Spain))")
        let engine = engine(for: "es-ES")
        var finals: [(engine: String, text: String)] = []
        let started = Date()
        var fired = false
        for try await u in try await engine.startReplaying(fileURL: audio) {
            if u.isFinal { finals.append((u.engine, u.text)) }
            if !fired, Date().timeIntervalSince(started) > 6 { fired = true; engine.handle(.memoryWarning) }
        }
        print("PARAKEET-IT es switch: " + finals.map { "[\($0.engine)] \($0.text)" }.joined(separator: " "))
        XCTAssertEqual(engine.fallbackReason, .memoryWarning)
        XCTAssertEqual(engine.engineName, "apple-speechanalyzer")
        XCTAssertTrue(finals.contains { $0.engine == "parakeet-ultra-pal6" })
        let after = finals.filter { $0.engine == "apple-speechanalyzer" }.map(\.text).joined(separator: " ").lowercased()
        // Apple's engine was made in Spanish, not English: Spanish words come out, not an English guess at them.
        XCTAssertTrue(after.contains("limón") || after.contains("garganta") || after.contains("abuelos"),
                      "Apple captioned the rest in Spanish: \(after)")
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.withLock { n += 1 } }
        var value: Int { lock.withLock { n } }
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

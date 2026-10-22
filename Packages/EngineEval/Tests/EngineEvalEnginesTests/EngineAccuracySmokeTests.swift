import AVFoundation
import EngineEvalEngines
import EngineEvalKit
import XCTest

/// Opt-in smoke run of every Apple-side engine on one synthesized sentence, same shape as CaptionCore's
/// SpeakerModelComparisonTests. Run with: CAPTION_ENGINE_EVAL=1 swift test --filter EngineAccuracySmoke
/// Needs network the first time (Parakeet ~0.5 GB each, WhisperKit large-v3 turbo ~1.6 GB, Apple en-US asset).
/// The real corpus run is `engine-eval run` driven by scripts/engine-eval/m4-driver.sh.
final class EngineAccuracySmokeTests: XCTestCase {
    private func synth(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "Daniel", "-o", url.path, "--data-format=LEI16@16000", text]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        return url
    }

    func testEveryEngineTranscribesASentence() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_ENGINE_EVAL"] == "1", "opt-in")
        let wav = try synth("The quick brown fox jumps over the lazy dog.")
        defer { try? FileManager.default.removeItem(at: wav) }
        let models = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAPTION_ENGINE_MODELS"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("edacc-eval/models").path)
        for id in EngineID.allCases {  // includes the no-gate WhisperKit variant
            let t = makeTranscriber(id, modelsDir: models, versions: EngineVersions(fluidAudio: "test", whisperKit: "test"))
            do {
                try await t.load()
                let start = Date()
                let text = try await t.transcribe(wav)
                print("ENGINE-EVAL-RESULT \(t.engine) \(t.model) \(String(format: "%.3f", Date().timeIntervalSince(start))) s: \(text)")
                XCTAssertTrue(text.lowercased().contains("fox"), "\(t.engine): \(text)")
            } catch {
                XCTFail("\(t.engine) failed: \(error)")
            }
        }
    }
}

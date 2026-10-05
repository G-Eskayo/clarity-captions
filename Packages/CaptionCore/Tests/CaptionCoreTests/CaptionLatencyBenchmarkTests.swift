import AVFoundation
import XCTest
@testable import CaptionCore

/// Opt-in latency measurement against a fixed audio fixture.
/// Run with: CAPTION_LATENCY=1 swift test -c release --filter CaptionLatencyBenchmark
/// Results are compared against the baseline in docs/perf/caption-latency-baseline.md.
final class CaptionLatencyBenchmarkTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        // Try to load from bundle first.
        if let bundled = Bundle.module.url(forResource: "latency-fixture", withExtension: "wav") {
            return bundled
        }

        // If not bundled, generate dynamically (same pattern as DiarizerIntegrationTests).
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("latency-fixture.wav")

        // Only generate if not already cached in temp.
        if !FileManager.default.fileExists(atPath: url.path) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            p.arguments = [
                "-v", "Samantha",
                "-o", url.path,
                "--data-format=LEF32@16000",
                "The quick brown fox jumps over the lazy dog. Now is the time for all good people to come to the aid of their country. She sells seashells by the seashore. Whether the weather be fine or whether the weather be not, whatever the weather, the weather is here. These pretzels are making me thirsty. How much wood would a woodchuck chuck if a woodchuck could chuck wood."
            ]
            try p.run()
            p.waitUntilExit()

            guard p.terminationStatus == 0 else {
                throw NSError(domain: "CaptionLatencyBenchmarkTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate latency fixture via say"])
            }
        }

        return url
    }

    private func loadBaseline() throws -> CaptionLatencyBaseline? {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let baselineFile = repo.appendingPathComponent("docs/perf/caption-latency-baseline.md")

        guard FileManager.default.fileExists(atPath: baselineFile.path) else {
            return nil
        }

        let content = try String(contentsOf: baselineFile)
        return CaptionLatencyBaseline.parse(markdown: content)
    }

    func testReplayFixedAudioStaysWithinBudget() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_LATENCY"] == "1", "opt-in")

        let fixtureURL = try fixtureURL()
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let diarModel = ProcessInfo.processInfo.environment["CAPTION_DIARIZER_MODEL"]
            .map { URL(fileURLWithPath: $0) }
            ?? repo.appendingPathComponent("Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc")

        // Warm up: model load + ANE prep don't count toward regression.
        try await TranscriptionEngine.warmUp(diarizerModelURL: diarModel)

        // First pass: throwaway, discard numbers.
        let engine1 = TranscriptionEngine(diarizerModelURL: diarModel)
        var count = 0
        for try await _ in try await engine1.startReplaying(fileURL: fixtureURL) {
            count += 1
        }
        print("LATENCY-WARMUP threw away \(count) captions")

        // Measured pass.
        let engine = TranscriptionEngine(diarizerModelURL: diarModel)
        var lagSamples: [Double] = []
        var firstCaptionTime: TimeInterval?
        let startTime = Date()

        for try await update in try await engine.startReplaying(fileURL: fixtureURL) {
            if firstCaptionTime == nil && !update.text.isEmpty {
                firstCaptionTime = Date().timeIntervalSince(startTime)
            }
            if let lag = update.lagSeconds {
                lagSamples.append(lag)
            }
        }

        let report = CaptionLatencyReport(lagSamples: lagSamples, timeToFirstCaption: firstCaptionTime)
        print(String(format: "LATENCY-RESULT median: %.3f s, p95: %.3f s, time-to-first: %.3f s",
                     report.medianLagSeconds,
                     report.p95LagSeconds,
                     report.timeToFirstCaptionSeconds ?? 0))

        // Check against baseline.
        if let baseline = try loadBaseline() {
            let status = report.regressionStatus(against: baseline)

            switch status {
            case .ok:
                print(String(format: "✓ Median within budget: %.3f s < %.3f s",
                             report.medianLagSeconds, baseline.medianLagSeconds * 1.10))
                print(String(format: "✓ P95 within budget: %.3f s < %.3f s",
                             report.p95LagSeconds, baseline.p95LagSeconds * 1.10))
            case .p95Warning(let measured, let budget, let baselineVal):
                print(String(format: "✓ Median within budget: %.3f s < %.3f s",
                             report.medianLagSeconds, baseline.medianLagSeconds * 1.10))
                print(String(format: "⚠️  P95 lag %.3f s exceeds budget %.3f s (baseline %.3f s + 10%%)",
                             measured, budget, baselineVal))
            case .medianFailure(let measured, let budget, let baselineVal):
                XCTFail(String(format: "Median lag %.3f s exceeds budget %.3f s (baseline %.3f s + 10%%)",
                               measured, budget, baselineVal))
            }
        } else {
            print("LATENCY-NOTE no baseline found; update docs/perf/caption-latency-baseline.md with these numbers")
        }
    }
}

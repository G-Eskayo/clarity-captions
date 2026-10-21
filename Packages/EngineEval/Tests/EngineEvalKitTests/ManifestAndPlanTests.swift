import Foundation
import XCTest
@testable import EngineEvalKit

final class ManifestAndPlanTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("shard-007-\(UUID().uuidString)")
            .appendingPathComponent("shard-007")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("audio"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
    }

    private func writeManifest(_ lines: [String]) throws {
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: dir.appendingPathComponent("manifest.jsonl"))
    }

    private func clipLine(_ id: String, accent: String = "Kenyan English", seconds: Double = 1.5) -> String {
        "{\"clip_id\":\"\(id)\",\"file\":\"audio/\(id).wav\",\"accent\":\"\(accent)\",\"audio_seconds\":\(seconds),\"speaker\":\"s\",\"reference\":\"HI\",\"split\":\"test\",\"l1\":\"x\",\"gender\":\"f\",\"source_file\":\"f\",\"row\":0}"
    }

    func testLoadsManifestIgnoringBlankLinesAndExtraFields() throws {
        try writeManifest([clipLine("a"), "", clipLine("b", accent: "Vietnamese")])
        let m = try Manifest.load(shardDir: dir)
        XCTAssertEqual(m.map(\.clipID), ["a", "b"])
        XCTAssertEqual(m[1].accent, "Vietnamese")
        XCTAssertEqual(Manifest.shardNumber(of: dir), 7)
    }

    func testCorruptManifestLineThrowsWithLineNumber() throws {
        try writeManifest([clipLine("a"), "{oops"])
        XCTAssertThrowsError(try Manifest.load(shardDir: dir)) { error in
            XCTAssertTrue("\(error)".contains("line 2"), "\(error)")
        }
    }

    func testDuplicateClipInManifestThrows() throws {
        try writeManifest([clipLine("a"), clipLine("a")])
        XCTAssertThrowsError(try Manifest.load(shardDir: dir))
    }

    func testMissingAudioListed() throws {
        try writeManifest([clipLine("a"), clipLine("b")])
        try Data("RIFF".utf8).write(to: dir.appendingPathComponent("audio/a.wav"))
        let m = try Manifest.load(shardDir: dir)
        XCTAssertEqual(Manifest.missingAudio(m, shardDir: dir), ["b"])
    }

    func testPendingSkipsDoneAndOrdersRepeatMajor() {
        let clips = ["a", "b"].map { ManifestClip(clipID: $0, file: "audio/\($0).wav", accent: "A", audioSeconds: 1) }
        let done: Set<ResultKey> = [ResultKey(clipID: "a", engine: "e", model: "m", repeat: 1)]
        let p = RunPlan.pending(clips: clips, engine: "e", model: "m", repeats: 2, done: done)
        XCTAssertEqual(p.map { "\($0.clip.clipID)\($0.repeat)" }, ["b1", "a2", "b2"])
        XCTAssertTrue(RunPlan.pending(clips: clips, engine: "e", model: "m", repeats: 0, done: []).isEmpty)
    }

    func testPendingIgnoresOtherEnginesAndModels() {
        let clips = [ManifestClip(clipID: "a", file: "audio/a.wav", accent: "A", audioSeconds: 1)]
        let done: Set<ResultKey> = [ResultKey(clipID: "a", engine: "e", model: "other", repeat: 1),
                                    ResultKey(clipID: "a", engine: "x", model: "m", repeat: 1)]
        XCTAssertEqual(RunPlan.pending(clips: clips, engine: "e", model: "m", repeats: 1, done: done).count, 1)
    }

    func testETA() {
        var eta = ETAEstimator()
        XCTAssertNil(eta.secondsRemaining(audioRemaining: 100))
        eta.record(audioSeconds: 10, processingSeconds: 1)
        eta.record(audioSeconds: 10, processingSeconds: 1)
        XCTAssertEqual(eta.secondsRemaining(audioRemaining: 100) ?? -1, 10, accuracy: 1e-9)
        XCTAssertEqual(ETAEstimator.format(3725), "1h 03m")
        XCTAssertEqual(ETAEstimator.format(59), "0h 01m")
    }

    func testPackagePinVersion() throws {
        let resolved = dir.appendingPathComponent("Package.resolved")
        try Data("""
        {"pins":[{"identity":"argmax-oss-swift","state":{"revision":"abc","version":"1.1.1"}},
                 {"identity":"fluidaudio","state":{"revision":"def","version":"0.17.5"}}],"version":3}
        """.utf8).write(to: resolved)
        XCTAssertEqual(PackagePins.version(of: "fluidaudio", resolvedFile: resolved), "0.17.5")
        XCTAssertNil(PackagePins.version(of: "nope", resolvedFile: resolved))
        XCTAssertNil(PackagePins.version(of: "fluidaudio", resolvedFile: dir.appendingPathComponent("missing")))
    }
}

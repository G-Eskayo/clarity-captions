import Foundation
import XCTest
@testable import EngineEvalKit

/// Adversarial tests for the M4 side of the resumable run (#145). Temp dirs only, never a real home dir.
final class ResultStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("engine-eval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func line(_ clip: String = "c1", engine: String = "apple", model: String = "m", repeat r: Int = 1,
                      hyp: String = "hi") -> ResultLine {
        ResultLine(clipID: clip, shard: 1, accent: "Irish English", engine: engine, model: model, engineVersion: "1",
                   repeat: r, hypothesis: hyp, audioSeconds: 2, processingSeconds: 0.1, host: "test",
                   finishedAt: "2026-10-21T00:00:00Z")
    }

    private var resultsURL: URL { dir.appendingPathComponent("results.jsonl") }

    func testMissingFileMeansNothingDone() throws {
        let store = try ResultStore(url: resultsURL)
        XCTAssertTrue(store.done.isEmpty)
    }

    func testAppendThenReopenResumes() throws {
        let store = try ResultStore(url: resultsURL)
        try store.append(line())
        try store.append(line(repeat: 2))
        let reopened = try ResultStore(url: resultsURL)
        XCTAssertEqual(reopened.done, [ResultKey(clipID: "c1", engine: "apple", model: "m", repeat: 1),
                                       ResultKey(clipID: "c1", engine: "apple", model: "m", repeat: 2)])
    }

    func testCorruptAndTruncatedLinesSkippedAndNextAppendStartsOnFreshLine() throws {
        let store = try ResultStore(url: resultsURL)
        try store.append(line())
        let fh = try FileHandle(forWritingTo: resultsURL)
        try fh.seekToEnd()
        try fh.write(contentsOf: Data("{not json\n{\"clip_id\": \"c2\", \"eng".utf8))  // crash mid-write
        try fh.close()

        let reopened = try ResultStore(url: resultsURL)
        XCTAssertEqual(reopened.done.count, 1)
        XCTAssertEqual(reopened.corruptLines, 2)
        try reopened.append(line("c3"))

        let again = try ResultStore(url: resultsURL)
        XCTAssertEqual(Set(again.done.map(\.clipID)), ["c1", "c3"])
        XCTAssertEqual(again.corruptLines, 2)
    }

    func testDuplicateLinesCountedOnce() throws {
        let store = try ResultStore(url: resultsURL)
        try store.append(line(hyp: "first"))
        try store.append(line(hyp: "second"))
        let reopened = try ResultStore(url: resultsURL)
        XCTAssertEqual(reopened.done.count, 1)
        XCTAssertEqual(reopened.duplicateLines, 1)
    }

    func testEmptyAndUnicodeHypothesesRoundTrip() throws {
        let store = try ResultStore(url: resultsURL)
        try store.append(line("e", hyp: ""))
        try store.append(line("u", hyp: "Hạ Long café \"quoted\"\nnewline ✓"))
        let text = try String(contentsOf: resultsURL, encoding: .utf8)
        XCTAssertEqual(text.split(separator: "\n").count, 2, "a newline inside a hypothesis must be escaped")
        let rows = try ResultStore.readLines(resultsURL).rows
        XCTAssertEqual(rows.first { $0.clipID == "e" }?.hypothesis, "")
        XCTAssertEqual(rows.first { $0.clipID == "u" }?.hypothesis, "Hạ Long café \"quoted\"\nnewline ✓")
    }

    func testSnakeCaseKeysMatchPythonScorer() throws {
        let store = try ResultStore(url: resultsURL)
        try store.append(line())
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: resultsURL)) as! [String: Any]
        for key in ["clip_id", "shard", "accent", "engine", "model", "engine_version", "repeat", "hypothesis",
                    "audio_seconds", "processing_seconds", "host", "finished_at"] {
            XCTAssertNotNil(obj[key], key)
        }
    }

    func testLineMissingRequiredFieldIsCorrupt() throws {
        try Data("{\"clip_id\":\"x\",\"engine\":\"a\"}\n".utf8).write(to: resultsURL)
        let store = try ResultStore(url: resultsURL)
        XCTAssertTrue(store.done.isEmpty)
        XCTAssertEqual(store.corruptLines, 1)
    }
}

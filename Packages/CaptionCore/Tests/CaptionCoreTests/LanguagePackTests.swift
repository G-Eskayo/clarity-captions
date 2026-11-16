import CryptoKit
import XCTest
@testable import CaptionCore

final class LanguagePackTests: XCTestCase {
    private let fm = FileManager.default

    func testCodingRoundtrip() throws {
        let pack = LanguagePack(
            id: "speech-en-parakeet-pal6-v1",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: 498000000,
            files: [
                LanguagePack.File(path: "model.mlmodelc/weights/weight.bin", size: 498000000,
                                  sha256: "abcd1234")
            ],
            credit: "Parakeet by NVIDIA"
        )

        let encoded = try JSONEncoder().encode(pack)
        let decoded = try JSONDecoder().decode(LanguagePack.self, from: encoded)
        XCTAssertEqual(pack, decoded)
    }

    func testKindEquality() {
        XCTAssertEqual(LanguagePack.Kind.speech, .speech)
        XCTAssertEqual(LanguagePack.Kind.diarizer, .diarizer)
        XCTAssertEqual(LanguagePack.Kind.translation, .translation)
        XCTAssertNotEqual(LanguagePack.Kind.speech, .diarizer)
    }

    func testVerifySucceedsWithValidPack() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let filePath = tmpDir.appendingPathComponent("model.bin")
        let data = "test content".data(using: .utf8)!
        try data.write(to: filePath)
        let hash = Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()

        let pack = LanguagePack(
            id: "test-pack-v1",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: Int64(data.count),
            files: [LanguagePack.File(path: "model.bin", size: Int64(data.count), sha256: hash)],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        XCTAssertEqual(result, .ok)
    }

    func testVerifyFailsWithEmptyManifest() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let pack = LanguagePack(
            id: "empty-pack",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: 0,
            files: [],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        guard case .failed(let problems) = result else { XCTFail("Expected failed verification"); return }
        XCTAssert(problems.contains { $0.contains("empty") || $0.contains("no files") })
    }

    func testVerifyFailsWithDuplicatePaths() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let pack = LanguagePack(
            id: "dup-paths",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: 100,
            files: [
                LanguagePack.File(path: "model.bin", size: 50, sha256: "abc"),
                LanguagePack.File(path: "model.bin", size: 50, sha256: "def")
            ],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        guard case .failed(let problems) = result else { XCTFail("Expected failed verification"); return }
        XCTAssert(problems.contains { $0.contains("Duplicate") })
    }

    func testVerifyFailsWithMissingFile() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let pack = LanguagePack(
            id: "missing-file",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: 100,
            files: [
                LanguagePack.File(path: "missing.bin", size: 100, sha256: "abc123")
            ],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        guard case .failed(let problems) = result else { XCTFail("Expected failed verification"); return }
        XCTAssert(problems.contains { $0.contains("missing.bin") || $0.contains("not found") })
    }

    func testVerifyFailsWithUnexpectedFile() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        try "unexpected".data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("extra.bin"))

        let pack = LanguagePack(
            id: "extra-file",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: 0,
            files: [],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        guard case .failed(let problems) = result else { XCTFail("Expected failed verification"); return }
        XCTAssert(problems.contains { $0.contains("extra.bin") || $0.contains("unexpected") })
    }

    func testVerifyFailsWithSizeMismatch() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let data = "test".data(using: .utf8)!
        try data.write(to: tmpDir.appendingPathComponent("model.bin"))

        let pack = LanguagePack(
            id: "size-mismatch",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: 999,
            files: [
                LanguagePack.File(path: "model.bin", size: 999, sha256: "abc")
            ],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        guard case .failed(let problems) = result else { XCTFail("Expected failed verification"); return }
        XCTAssert(problems.contains { $0.contains("model.bin") && ($0.contains("size") || $0.contains("999")) })
    }

    func testVerifyFailsWithHashMismatch() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let data = "test content".data(using: .utf8)!
        try data.write(to: tmpDir.appendingPathComponent("model.bin"))

        let pack = LanguagePack(
            id: "hash-mismatch",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: Int64(data.count),
            files: [
                LanguagePack.File(path: "model.bin", size: Int64(data.count), sha256: "wronghash123")
            ],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        guard case .failed(let problems) = result else { XCTFail("Expected failed verification"); return }
        XCTAssert(problems.contains { $0.contains("model.bin") && ($0.contains("sha256") || $0.contains("hash")) })
    }

    func testVerifyProblemsAreSorted() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let pack = LanguagePack(
            id: "multi-error",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: 100,
            files: [
                LanguagePack.File(path: "z.bin", size: 50, sha256: "abc"),
                LanguagePack.File(path: "a.bin", size: 50, sha256: "def")
            ],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        guard case .failed(let problems) = result else { XCTFail("Expected failed verification"); return }
        XCTAssertEqual(problems, problems.sorted())
    }

    func testVerifyWithNestedPaths() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let nestedDir = tmpDir.appendingPathComponent("model.mlmodelc/weights")
        try fm.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        let filePath = nestedDir.appendingPathComponent("weight.bin")
        let data = "nested test".data(using: .utf8)!
        try data.write(to: filePath)
        let hash = Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()

        let pack = LanguagePack(
            id: "nested-pack",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: Int64(data.count),
            files: [
                LanguagePack.File(path: "model.mlmodelc/weights/weight.bin", size: Int64(data.count), sha256: hash)
            ],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        XCTAssertEqual(result, .ok)
    }

    func testVerifyRejectsPathTraversalWithDotDot() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let pack = LanguagePack(
            id: "path-traversal-test",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: 100,
            files: [
                LanguagePack.File(path: "../outside.bin", size: 100, sha256: "abc")
            ],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        guard case .failed(let problems) = result else { XCTFail("Expected failed verification"); return }
        XCTAssert(problems.contains { $0.contains("path traversal") || $0.contains("..") || $0.contains("rejected") })
    }

    func testVerifyRejectsAbsolutePath() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let pack = LanguagePack(
            id: "absolute-path-test",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: 100,
            files: [
                LanguagePack.File(path: "/etc/passwd", size: 100, sha256: "abc")
            ],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        guard case .failed(let problems) = result else { XCTFail("Expected failed verification"); return }
        XCTAssert(problems.contains { $0.contains("path traversal") || $0.contains("absolute") || $0.contains("rejected") })
    }

    func testVerifyRejectsUnknownEngine() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let jsonData = """
        {
          "id": "test-pack",
          "kind": "speech",
          "languages": ["en-US"],
          "engine": "unknown-engine-xyz",
          "minAppBuild": 7,
          "sizeOnDisk": 100,
          "files": [],
          "credit": "Test"
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(LanguagePack.self, from: jsonData))
    }

    func testVerifyWithLargeFilesUsesChunkedHashing() throws {
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let filePath = tmpDir.appendingPathComponent("large.bin")
        let chunkSize = 1024 * 1024
        let chunkCount = 10
        var hasher = SHA256()

        let chunk = Data(repeating: 0x42, count: chunkSize)
        for _ in 0..<chunkCount {
            hasher.update(data: chunk)
        }
        let expectedHash = Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()

        try fm.createFile(atPath: filePath.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: filePath)
        for _ in 0..<chunkCount {
            try fileHandle.write(contentsOf: chunk)
        }
        try fileHandle.close()

        let pack = LanguagePack(
            id: "large-file-pack",
            kind: .speech,
            languages: ["en-US"],
            engine: .parakeet,
            minAppBuild: 7,
            sizeOnDisk: Int64(chunkSize * chunkCount),
            files: [
                LanguagePack.File(path: "large.bin", size: Int64(chunkSize * chunkCount), sha256: expectedHash)
            ],
            credit: "Test"
        )

        let result = pack.verify(in: tmpDir)
        XCTAssertEqual(result, .ok)
    }
}

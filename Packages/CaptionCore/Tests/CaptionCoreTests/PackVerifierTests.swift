import CryptoKit
import Foundation
import XCTest
@testable import CaptionCore

final class PackVerifierTests: XCTestCase {
    private var testDir: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        testDir = tempDir.appendingPathComponent(UUID().uuidString)
        try? fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: testDir)
        testDir = nil
        super.tearDown()
    }

    // Test 12: Folder whose files exactly match the manifest verifies clean
    func testExactMatchVerifiesClean() throws {
        let file1Content = "test content 1".data(using: .utf8)!
        let file1Hash = Data(SHA256.hash(data: file1Content)).map { String(format: "%02x", $0) }.joined()

        let file2Content = "test content 2".data(using: .utf8)!
        let file2Hash = Data(SHA256.hash(data: file2Content)).map { String(format: "%02x", $0) }.joined()

        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: file1Content.count + file2Content.count,
            files: [
                PackManifest.File(path: "file1.txt", size: file1Content.count, sha256: file1Hash),
                PackManifest.File(path: "file2.txt", size: file2Content.count, sha256: file2Hash),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)
        try file1Content.write(to: folderPath.appendingPathComponent("file1.txt"))
        try file2Content.write(to: folderPath.appendingPathComponent("file2.txt"))

        let problems = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(problems, [])
    }

    // Test 13: Missing manifest file is reported as missing
    func testMissingFileIsReported() throws {
        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: 100,
            files: [
                PackManifest.File(
                    path: "missing.txt",
                    size: 100,
                    sha256: "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
                ),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)

        let problems = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(problems[0], .missing("missing.txt"))
    }

    // Test 14: Extra file not in manifest is reported as unexpected
    func testUnexpectedFileIsReported() throws {
        let content = "test".data(using: .utf8)!
        let hash = Data(SHA256.hash(data: content)).map { String(format: "%02x", $0) }.joined()

        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: content.count,
            files: [
                PackManifest.File(path: "expected.txt", size: content.count, sha256: hash),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)
        try content.write(to: folderPath.appendingPathComponent("expected.txt"))
        try content.write(to: folderPath.appendingPathComponent("unexpected.txt"))

        let problems = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(problems[0], .unexpected("unexpected.txt"))
    }

    // Test 15: Size mismatch is reported, hash is not checked
    func testSizeMismatchIsReportedWithoutHashing() throws {
        let correctContent = "correct size content".data(using: .utf8)!
        let correctHash = Data(SHA256.hash(data: correctContent)).map { String(format: "%02x", $0) }.joined()

        let wrongSizeContent = "x".data(using: .utf8)!

        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: correctContent.count,
            files: [
                PackManifest.File(path: "file.txt", size: correctContent.count, sha256: correctHash),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)
        try wrongSizeContent.write(to: folderPath.appendingPathComponent("file.txt"))

        let problems = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(problems[0], .sizeMismatch("file.txt"))
    }

    // Test 16: Checksum mismatch is reported when size matches
    func testChecksumMismatchIsReported() throws {
        let correctContent = "correct content".data(using: .utf8)!
        let correctHash = Data(SHA256.hash(data: correctContent)).map { String(format: "%02x", $0) }.joined()

        let wrongContent = "wrong content!!".data(using: .utf8)! // Same length, different content

        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: correctContent.count,
            files: [
                PackManifest.File(path: "file.txt", size: correctContent.count, sha256: correctHash),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)
        try wrongContent.write(to: folderPath.appendingPathComponent("file.txt"))

        let problems = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(problems[0], .checksumMismatch("file.txt"))
    }

    // Test 17: Non-existent folder is reported as folderMissing
    func testMissingFolderIsReported() throws {
        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: 100,
            files: [
                PackManifest.File(
                    path: "file.txt",
                    size: 100,
                    sha256: "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
                ),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("nonexistent")
        let problems = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(problems[0], .folderMissing)
    }

    // Test 18: Empty folder reports all manifest files as missing
    func testEmptyFolderReportsAllMissing() throws {
        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: 200,
            files: [
                PackManifest.File(
                    path: "file1.txt",
                    size: 100,
                    sha256: "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
                ),
                PackManifest.File(
                    path: "file2.txt",
                    size: 100,
                    sha256: "ef001234ef001234ef001234ef001234ef001234ef001234ef001234ef001234"
                ),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)

        let problems = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(problems.count, 2)
        XCTAssertTrue(problems.contains(.missing("file1.txt")))
        XCTAssertTrue(problems.contains(.missing("file2.txt")))
    }

    // Test 19: .DS_Store is ignored
    func testDotDSStoreIsIgnored() throws {
        let content = "test".data(using: .utf8)!
        let hash = Data(SHA256.hash(data: content)).map { String(format: "%02x", $0) }.joined()

        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: content.count,
            files: [
                PackManifest.File(path: "file.txt", size: content.count, sha256: hash),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)
        try content.write(to: folderPath.appendingPathComponent("file.txt"))
        try content.write(to: folderPath.appendingPathComponent(".DS_Store"))

        let problems = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(problems, [])
    }

    // Test 20: Large file with chunked hashing verifies correctly
    func testLargeFileVerifiesWithChunkedHashing() throws {
        let chunkSize = 1 << 20 // 1 MB
        var largeContent = Data()
        for _ in 0..<3 {
            largeContent.append(Data(repeating: 0x42, count: chunkSize))
        }
        let hash = Data(SHA256.hash(data: largeContent)).map { String(format: "%02x", $0) }.joined()

        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: largeContent.count,
            files: [
                PackManifest.File(path: "large.bin", size: largeContent.count, sha256: hash),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)
        try largeContent.write(to: folderPath.appendingPathComponent("large.bin"))

        let problems = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(problems, [])
    }

    // Test 21: Verifier reports unreadable files (permission denied)
    func testFileSystemErrorsAreCaught() throws {
        let content = "test".data(using: .utf8)!
        let hash = Data(SHA256.hash(data: content)).map { String(format: "%02x", $0) }.joined()

        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: content.count,
            files: [
                PackManifest.File(path: "file.txt", size: content.count, sha256: hash),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)
        let filePath = folderPath.appendingPathComponent("file.txt")
        try content.write(to: filePath)

        // Remove read permission using shell command
        #if os(macOS)
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["000", filePath.path]
        try process.run()
        process.waitUntilExit()
        #endif

        defer {
            // Restore read permission for cleanup
            #if os(macOS)
            let cleanup = Foundation.Process()
            cleanup.executableURL = URL(fileURLWithPath: "/bin/chmod")
            cleanup.arguments = ["644", filePath.path]
            try? cleanup.run()
            cleanup.waitUntilExit()
            #endif
        }

        let problems = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(problems[0], .unreadable("file.txt"))
    }

    // Test 22: Verification is pure (multiple concurrent calls are independent)
    func testVerificationIsPure() throws {
        let content = "test content".data(using: .utf8)!
        let hash = Data(SHA256.hash(data: content)).map { String(format: "%02x", $0) }.joined()

        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: content.count,
            files: [
                PackManifest.File(path: "file.txt", size: content.count, sha256: hash),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)
        try content.write(to: folderPath.appendingPathComponent("file.txt"))

        // Verify the function is pure: no mutable shared state
        var results: [Result<[PackVerificationProblem], Error>] = []
        let lock = NSLock()
        let dispatchGroup = DispatchGroup()

        for _ in 0..<3 {
            DispatchQueue.global().async(group: dispatchGroup) {
                do {
                    let result = try PackVerifier.verify(manifest, in: folderPath, fileManager: self.fileManager)
                    lock.lock()
                    results.append(.success(result))
                    lock.unlock()
                } catch {
                    lock.lock()
                    results.append(.failure(error))
                    lock.unlock()
                }
            }
        }

        dispatchGroup.wait()
        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy { if case .success = $0 { return true } else { return false } })
        let values = results.compactMap { try? $0.get() }
        XCTAssertEqual(values[0], values[1])
        XCTAssertEqual(values[1], values[2])
    }

    // Test 23: Verifying the same folder twice gives the same result
    func testVerifyingTwiceIsIdempotent() throws {
        let content = "test content".data(using: .utf8)!
        let hash = Data(SHA256.hash(data: content)).map { String(format: "%02x", $0) }.joined()

        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: content.count,
            files: [
                PackManifest.File(path: "file.txt", size: content.count, sha256: hash),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)
        try content.write(to: folderPath.appendingPathComponent("file.txt"))

        let result1 = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        let result2 = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)

        XCTAssertEqual(result1, result2)
    }

    // Test 24: Large multi-chunk file hashing correctly recovers from I/O errors
    func testLargeFileIOErrorsAreCaught() throws {
        let chunkSize = 1 << 20 // 1 MB
        var largeContent = Data()
        for _ in 0..<3 {
            largeContent.append(Data(repeating: 0x55, count: chunkSize))
        }
        let hash = Data(SHA256.hash(data: largeContent)).map { String(format: "%02x", $0) }.joined()

        let manifest = PackManifest(
            id: "test",
            kind: .speech,
            languages: ["en"],
            engine: "test",
            minAppBuild: 1,
            sizeOnDisk: largeContent.count,
            files: [
                PackManifest.File(path: "large.bin", size: largeContent.count, sha256: hash),
            ],
            credit: "Test"
        )

        let folderPath = testDir.appendingPathComponent("model")
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)
        let filePath = folderPath.appendingPathComponent("large.bin")
        try largeContent.write(to: filePath)

        // First verify the large file works correctly with multiple chunks
        let result1 = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(result1, [])

        // Now remove read permission and verify it reports unreadable instead of crashing
        #if os(macOS)
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["000", filePath.path]
        try process.run()
        process.waitUntilExit()
        #endif

        defer {
            #if os(macOS)
            let cleanup = Foundation.Process()
            cleanup.executableURL = URL(fileURLWithPath: "/bin/chmod")
            cleanup.arguments = ["644", filePath.path]
            try? cleanup.run()
            cleanup.waitUntilExit()
            #endif
        }

        // Verify that I/O errors are caught and reported as unreadable, not crashed
        let result2 = try PackVerifier.verify(manifest, in: folderPath, fileManager: fileManager)
        XCTAssertEqual(result2.count, 1)
        XCTAssertEqual(result2[0], .unreadable("large.bin"))
    }
}

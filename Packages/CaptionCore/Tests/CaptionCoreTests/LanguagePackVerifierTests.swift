import XCTest
import CommonCrypto
@testable import CaptionCore

final class LanguagePackVerifierTests: XCTestCase {
    private var tempDirectory: URL!
    private var fileManager: FileManager!

    override func setUp() {
        super.setUp()
        fileManager = FileManager.default
        tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    override func tearDown() {
        super.tearDown()
        try? fileManager.removeItem(at: tempDirectory)
    }

    // MARK: - Test 13: Verify valid pack matches manifest
    func testVerifyValidPackMatches() throws {
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testData = "hello world".data(using: .utf8)!
        try testData.write(to: testFile)

        let sha256 = try computeTestSHA256(testData)
        let files = [
            LanguagePack.FileEntry(path: "test.txt", size: testData.count, sha256: sha256)
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: testData.count,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(pack, at: tempDirectory)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.problems.count, 0)
        XCTAssertEqual(result.filesVerified, 1)
    }

    // MARK: - Test 14: Verify detects missing files
    func testVerifyDetectsMissingFile() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "missing.txt",
                size: 1024,
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            )
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: 1024,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(pack, at: tempDirectory)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.problems.count, 1)
        XCTAssertTrue(result.problems[0].description.contains("missing"))
    }

    // MARK: - Test 15: Verify detects unexpected files
    func testVerifyDetectsUnexpectedFile() throws {
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testData = "hello".data(using: .utf8)!
        try testData.write(to: testFile)

        let unexpectedFile = tempDirectory.appendingPathComponent("unexpected.txt")
        try "data".data(using: .utf8)!.write(to: unexpectedFile)

        let sha256 = try computeTestSHA256(testData)
        let validFiles = [
            LanguagePack.FileEntry(path: "test.txt", size: testData.count, sha256: sha256)
        ]
        let validPack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: validFiles,
            languages: ["en"],
            sizeOnDisk: testData.count,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(validPack, at: tempDirectory)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.problems.count, 1)
        XCTAssertTrue(result.problems[0].description.contains("unexpected"))
    }

    // MARK: - Test 16: Verify detects size mismatch
    func testVerifyDetectsSizeMismatch() throws {
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testData = "hello".data(using: .utf8)!
        try testData.write(to: testFile)

        let sha256 = try computeTestSHA256(testData)
        let files = [
            LanguagePack.FileEntry(
                path: "test.txt",
                size: testData.count + 100,
                sha256: sha256
            )
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: testData.count + 100,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(pack, at: tempDirectory)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.problems.count, 1)
        XCTAssertTrue(result.problems[0].description.contains("size mismatch"))
    }

    // MARK: - Test 17: Verify detects checksum mismatch
    func testVerifyDetectsChecksumMismatch() throws {
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testData = "hello".data(using: .utf8)!
        try testData.write(to: testFile)

        let wrongSHA256 = "0000000000000000000000000000000000000000000000000000000000000000"
        let files = [
            LanguagePack.FileEntry(
                path: "test.txt",
                size: testData.count,
                sha256: wrongSHA256
            )
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: testData.count,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(pack, at: tempDirectory)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.problems.count, 1)
        XCTAssertTrue(result.problems[0].description.contains("checksum mismatch"))
    }

    // MARK: - Test 18: Verify handles nested directories
    func testVerifyHandlesNestedDirectories() throws {
        let subdir = tempDirectory.appendingPathComponent("subdir")
        try fileManager.createDirectory(at: subdir, withIntermediateDirectories: true)

        let nestedFile = subdir.appendingPathComponent("nested.txt")
        let testData = "nested content".data(using: .utf8)!
        try testData.write(to: nestedFile)

        let sha256 = try computeTestSHA256(testData)
        let files = [
            LanguagePack.FileEntry(
                path: "subdir/nested.txt",
                size: testData.count,
                sha256: sha256
            )
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: testData.count,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(pack, at: tempDirectory)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.filesVerified, 1)
    }

    // MARK: - Test 19: Verify skips .DS_Store
    func testVerifySkipsDSStore() throws {
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testData = "hello".data(using: .utf8)!
        try testData.write(to: testFile)

        let dsStore = tempDirectory.appendingPathComponent(".DS_Store")
        try "macOS".data(using: .utf8)!.write(to: dsStore)

        let sha256 = try computeTestSHA256(testData)
        let files = [
            LanguagePack.FileEntry(
                path: "test.txt",
                size: testData.count,
                sha256: sha256
            )
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: testData.count,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(pack, at: tempDirectory)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.filesVerified, 1)
    }

    // MARK: - Test 20: Verify multiple files with various issues
    func testVerifyMultipleFilesWithMixedIssues() throws {
        let file1 = tempDirectory.appendingPathComponent("file1.txt")
        let data1 = "content1".data(using: .utf8)!
        try data1.write(to: file1)

        let file2 = tempDirectory.appendingPathComponent("file2.txt")
        let data2 = "content2".data(using: .utf8)!
        try data2.write(to: file2)

        let subdir = tempDirectory.appendingPathComponent("subdir")
        try fileManager.createDirectory(at: subdir, withIntermediateDirectories: true)
        let file3 = subdir.appendingPathComponent("file3.txt")
        try data1.write(to: file3)

        let sha1 = try computeTestSHA256(data1)
        let sha2 = try computeTestSHA256(data2)

        let files = [
            LanguagePack.FileEntry(path: "file1.txt", size: data1.count, sha256: sha1),
            LanguagePack.FileEntry(path: "file2.txt", size: 9999, sha256: sha2),
            LanguagePack.FileEntry(path: "missing.txt", size: 1024, sha256: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789")
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: data1.count + 9999 + 1024,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(pack, at: tempDirectory)
        XCTAssertFalse(result.isValid)
        XCTAssertGreaterThanOrEqual(result.problems.count, 2)
        XCTAssertEqual(result.filesVerified, 1)
    }

    // MARK: - Test 21: Verify detects missing file correctly (not unexpected)
    func testVerifyReportsCorrectErrorForMissingFile() throws {
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testData = "hello".data(using: .utf8)!
        try testData.write(to: testFile)

        let sha256 = try computeTestSHA256(testData)
        let files = [
            LanguagePack.FileEntry(path: "test.txt", size: testData.count, sha256: sha256),
            LanguagePack.FileEntry(
                path: "missing.txt",
                size: 1024,
                sha256: "0000000000000000000000000000000000000000000000000000000000000000"
            )
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: testData.count + 1024,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(pack, at: tempDirectory)
        XCTAssertFalse(result.isValid)
        let missingProblem = result.problems.first { problem in
            if case .missingFile = problem.kind {
                return true
            }
            return false
        }
        XCTAssertNotNil(missingProblem, "Should report missing.txt as missing, not unexpected")
    }

    // MARK: - Test 22: Verify uppercase SHA256 matches lowercase computed hash
    func testVerifyAcceptsUppercaseSHA256() throws {
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testData = "hello".data(using: .utf8)!
        try testData.write(to: testFile)

        let sha256Lower = try computeTestSHA256(testData)
        let sha256Upper = sha256Lower.uppercased()

        let files = [
            LanguagePack.FileEntry(path: "test.txt", size: testData.count, sha256: sha256Upper)
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: testData.count,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(pack, at: tempDirectory)
        XCTAssertTrue(result.isValid, "Uppercase SHA256 should match lowercase computed hash")
        XCTAssertEqual(result.problems.count, 0)
    }

    // MARK: - Test 23: Verify rejects symlinks to files
    func testVerifyRejectsSymlinksToFiles() throws {
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testData = "hello".data(using: .utf8)!
        try testData.write(to: testFile)

        let symlinkPath = tempDirectory.appendingPathComponent("symlink.txt")
        try fileManager.createSymbolicLink(at: symlinkPath, withDestinationURL: testFile)

        let sha256 = try computeTestSHA256(testData)
        let files = [
            LanguagePack.FileEntry(path: "symlink.txt", size: testData.count, sha256: sha256)
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: testData.count,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(pack, at: tempDirectory)
        XCTAssertFalse(result.isValid, "Symlinks should cause verification to fail")
        let hasSymlinkOrMissingProblem = result.problems.contains { problem in
            switch problem.kind {
            case .symlinkRejected:
                return true
            case .missingFile(let path):
                return path == "symlink.txt"
            default:
                return false
            }
        }
        XCTAssertTrue(hasSymlinkOrMissingProblem, "Should report symlink as either rejected or missing")
    }

    // MARK: - Test 24: Verify correctly handles regular file in mix
    func testVerifyWithRegularFile() throws {
        let testFile = tempDirectory.appendingPathComponent("regular.txt")
        let testData = "test content".data(using: .utf8)!
        try testData.write(to: testFile)

        let sha256 = try computeTestSHA256(testData)
        let files = [
            LanguagePack.FileEntry(path: "regular.txt", size: testData.count, sha256: sha256)
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: testData.count,
            credit: "Test"
        )

        let result = try LanguagePackVerifier.verify(pack, at: tempDirectory)
        XCTAssertTrue(result.isValid, "Regular files should verify correctly")
        XCTAssertEqual(result.filesVerified, 1)
        XCTAssertEqual(result.problems.count, 0)
    }

    // MARK: - Helper function

    private func computeTestSHA256(_ data: Data) throws -> String {
        var digest = [UInt8](repeating: 0, count: 32)
        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)

        data.withUnsafeBytes { buffer in
            CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(data.count))
        }

        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

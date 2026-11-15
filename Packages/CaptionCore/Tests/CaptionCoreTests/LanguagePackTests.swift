import XCTest
@testable import CaptionCore

final class LanguagePackTests: XCTestCase {
    // MARK: - Test 1: Basic structure and encoding/decoding
    func testLanguagePackCodableRoundtrip() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: 1024,
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            ),
            LanguagePack.FileEntry(
                path: "vocab.json",
                size: 512,
                sha256: "d4735fea8e8c00a743fc686ba20eb158cfb3f6b85f1fc45e2e2b0cf0a1f0c6b7"
            )
        ]
        let pack = LanguagePack(
            id: "parakeet-v1",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: 1536,
            credit: "Original creators"
        )

        let encoder = JSONEncoder()
        let encoded = try encoder.encode(pack)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LanguagePack.self, from: encoded)

        XCTAssertEqual(decoded.kind, pack.kind)
        XCTAssertEqual(decoded.engine, pack.engine)
        XCTAssertEqual(decoded.version, pack.version)
        XCTAssertEqual(decoded.files.count, 2)
        XCTAssertEqual(decoded.files[0].path, "model.mlmodelc")
        XCTAssertEqual(decoded.files[1].path, "vocab.json")
        XCTAssertEqual(decoded.id, "parakeet-v1")
        XCTAssertEqual(decoded.languages, ["en"])
        XCTAssertEqual(decoded.sizeOnDisk, 1536)
    }

    // MARK: - Test 2: Validation fails with empty files
    func testValidateFailsWithNoFiles() throws {
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: [],
            languages: ["en"],
            sizeOnDisk: 0,
            credit: "Test"
        )

        XCTAssertThrowsError(try pack.validate()) { error in
            guard case LanguagePack.LanguagePackError.noFiles = error else {
                XCTFail("Expected noFiles error, got \(error)")
                return
            }
        }
    }

    // MARK: - Test 3: Validation fails with duplicate paths
    func testValidateFailsWithDuplicatePaths() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: 1024,
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            ),
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: 512,
                sha256: "d4735fea8e8c00a743fc686ba20eb158cfb3f6b85f1fc45e2e2b0cf0a1f0c6b7"
            )
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: 1536,
            credit: "Test"
        )

        XCTAssertThrowsError(try pack.validate()) { error in
            guard case LanguagePack.LanguagePackError.duplicatePaths = error else {
                XCTFail("Expected duplicatePaths error, got \(error)")
                return
            }
        }
    }

    // MARK: - Test 4: Validation fails with invalid SHA256
    func testValidateFailsWithInvalidSHA256() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: 1024,
                sha256: "not-a-valid-hex-string-at-all"
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

        XCTAssertThrowsError(try pack.validate()) { error in
            guard case LanguagePack.LanguagePackError.invalidSHA256 = error else {
                XCTFail("Expected invalidSHA256 error, got \(error)")
                return
            }
        }
    }

    // MARK: - Test 5: Validation fails with invalid file size
    func testValidateFailsWithZeroSize() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: 0,
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
            sizeOnDisk: 0,
            credit: "Test"
        )

        XCTAssertThrowsError(try pack.validate()) { error in
            guard case LanguagePack.LanguagePackError.invalidSize = error else {
                XCTFail("Expected invalidSize error, got \(error)")
                return
            }
        }
    }

    // MARK: - Test 6: Validation fails with negative file size
    func testValidateFailsWithNegativeSize() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: -1,
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
            sizeOnDisk: 0,
            credit: "Test"
        )

        XCTAssertThrowsError(try pack.validate()) { error in
            guard case LanguagePack.LanguagePackError.invalidSize = error else {
                XCTFail("Expected invalidSize error, got \(error)")
                return
            }
        }
    }

    // MARK: - Test 7: Validation fails with empty version
    func testValidateFailsWithEmptyVersion() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: 1024,
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            )
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "",
            files: files,
            languages: ["en"],
            sizeOnDisk: 1024,
            credit: "Test"
        )

        XCTAssertThrowsError(try pack.validate()) { error in
            guard case LanguagePack.LanguagePackError.invalidVersion = error else {
                XCTFail("Expected invalidVersion error, got \(error)")
                return
            }
        }
    }

    // MARK: - Test 8: Valid pack passes validation
    func testValidPackPasses() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: 1024,
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            ),
            LanguagePack.FileEntry(
                path: "vocab.json",
                size: 512,
                sha256: "d4735fea8e8c00a743fc686ba20eb158cfb3f6b85f1fc45e2e2b0cf0a1f0c6b7"
            )
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: 1536,
            credit: "Test"
        )

        XCTAssertNoThrow(try pack.validate())
    }

    // MARK: - Test 9: decode(_:) validates and decodes
    func testDecodeValidates() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
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
        let encoded = try JSONEncoder().encode(pack)

        let decoded = try LanguagePack.decode(encoded)
        XCTAssertEqual(decoded.version, "1.0.0")
        XCTAssertEqual(decoded.files.count, 1)
    }

    // MARK: - Test 10: decode(_:) throws on invalid pack
    func testDecodeThrowsOnInvalidPack() throws {
        let json = """
        {
            "id": "test",
            "kind": "asr-model",
            "engine": "parakeet",
            "version": "1.0.0",
            "files": [],
            "minAppBuild": null,
            "languages": ["en"],
            "sizeOnDisk": 0,
            "credit": "test"
        }
        """
        let data = json.data(using: .utf8)!

        XCTAssertThrowsError(try LanguagePack.decode(data)) { error in
            guard case LanguagePack.LanguagePackError.noFiles = error else {
                XCTFail("Expected noFiles error during decode, got \(error)")
                return
            }
        }
    }

    // MARK: - Test 11: isUsable checks minAppBuild
    func testIsUsableWithoutMinBuild() {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
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
            minAppBuild: nil,
            languages: ["en"],
            sizeOnDisk: 1024,
            credit: "Test"
        )

        XCTAssertTrue(pack.isUsable(byAppBuild: 1))
        XCTAssertTrue(pack.isUsable(byAppBuild: 100))
    }

    // MARK: - Test 12: isUsable enforces minAppBuild
    func testIsUsableWithMinBuild() {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
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
            minAppBuild: 50,
            languages: ["en"],
            sizeOnDisk: 1024,
            credit: "Test"
        )

        XCTAssertFalse(pack.isUsable(byAppBuild: 49))
        XCTAssertTrue(pack.isUsable(byAppBuild: 50))
        XCTAssertTrue(pack.isUsable(byAppBuild: 51))
    }

    // MARK: - Test 7a: Validation rejects unsafe file paths
    func testValidateRejectsUnsafePaths() throws {
        let unsafePaths = [
            "/etc/passwd",
            "../../../etc/passwd",
            "subdir/../../../etc/passwd",
            "./model.mlmodelc",
            "",
            "model/./mlmodelc"
        ]

        for unsafePath in unsafePaths {
            let files = [
                LanguagePack.FileEntry(
                    path: unsafePath,
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

            XCTAssertThrowsError(
                try pack.validate(),
                "Should reject unsafe path: \(unsafePath)"
            ) { error in
                guard case LanguagePack.LanguagePackError.invalidPath = error else {
                    XCTFail("Expected invalidPath error for \(unsafePath), got \(error)")
                    return
                }
            }
        }
    }

    // MARK: - Test 7b: Validation accepts safe file paths
    func testValidateAcceptsSafePaths() throws {
        let safePaths = [
            "model.mlmodelc",
            "subdir/model.mlmodelc",
            "a/b/c/model.mlmodelc",
            "model-v1.2.3.mlmodelc"
        ]

        for safePath in safePaths {
            let files = [
                LanguagePack.FileEntry(
                    path: safePath,
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

            XCTAssertNoThrow(
                try pack.validate(),
                "Should accept safe path: \(safePath)"
            )
        }
    }

    // MARK: - Test 8a: SHA256 case normalization
    func testSHA256CaseNormalization() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: 1024,
                sha256: "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"
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

        XCTAssertNoThrow(try pack.validate())
        XCTAssertEqual(
            pack.files[0].sha256,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    // MARK: - Test 8b: Validation fails with empty ID
    func testValidateFailsWithEmptyID() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: 1024,
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            )
        ]
        let pack = LanguagePack(
            id: "",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: 1024,
            credit: "Test"
        )

        XCTAssertThrowsError(try pack.validate()) { error in
            guard case LanguagePack.LanguagePackError.invalidID = error else {
                XCTFail("Expected invalidID error, got \(error)")
                return
            }
        }
    }

    // MARK: - Test 8c: Validation fails with empty languages
    func testValidateFailsWithNoLanguages() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
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
            languages: [],
            sizeOnDisk: 1024,
            credit: "Test"
        )

        XCTAssertThrowsError(try pack.validate()) { error in
            guard case LanguagePack.LanguagePackError.noLanguages = error else {
                XCTFail("Expected noLanguages error, got \(error)")
                return
            }
        }
    }

    // MARK: - Test 8d: Validation fails with empty credit
    func testValidateFailsWithNoCredit() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
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
            credit: ""
        )

        XCTAssertThrowsError(try pack.validate()) { error in
            guard case LanguagePack.LanguagePackError.noCredit = error else {
                XCTFail("Expected noCredit error, got \(error)")
                return
            }
        }
    }

    // MARK: - Test 8e: Validation fails with minAppBuild <= 0
    func testValidateFailsWithInvalidMinAppBuild() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: 1024,
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            )
        ]
        for invalidBuild in [0, -1, -100] {
            let pack = LanguagePack(
                id: "test-pack",
                kind: .asrModel,
                engine: .parakeet,
                version: "1.0.0",
                files: files,
                minAppBuild: invalidBuild,
                languages: ["en"],
                sizeOnDisk: 1024,
                credit: "Test"
            )

            XCTAssertThrowsError(try pack.validate()) { error in
                guard case LanguagePack.LanguagePackError.invalidMinAppBuild = error else {
                    XCTFail("Expected invalidMinAppBuild error, got \(error)")
                    return
                }
            }
        }
    }

    // MARK: - Test 8f: Validation fails with sizeOnDisk mismatch
    func testValidateFailsWithSizeOnDiskMismatch() throws {
        let files = [
            LanguagePack.FileEntry(
                path: "model.mlmodelc",
                size: 1024,
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            ),
            LanguagePack.FileEntry(
                path: "vocab.json",
                size: 512,
                sha256: "d4735fea8e8c00a743fc686ba20eb158cfb3f6b85f1fc45e2e2b0cf0a1f0c6b7"
            )
        ]
        let pack = LanguagePack(
            id: "test-pack",
            kind: .asrModel,
            engine: .parakeet,
            version: "1.0.0",
            files: files,
            languages: ["en"],
            sizeOnDisk: 9999,
            credit: "Test"
        )

        XCTAssertThrowsError(try pack.validate()) { error in
            guard case LanguagePack.LanguagePackError.sizeOnDiskMismatch = error else {
                XCTFail("Expected sizeOnDiskMismatch error, got \(error)")
                return
            }
        }
    }
}

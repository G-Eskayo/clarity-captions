import XCTest
@testable import CaptionCore

final class PackManifestTests: XCTestCase {
    // Test 1: A valid pack.json decodes and round-trips
    func testValidPackManifestDecodes() throws {
        let json = """
        {
            "id": "parakeet-hebrew",
            "kind": "speech",
            "languages": ["he"],
            "engine": "parakeet",
            "minAppBuild": 1,
            "sizeOnDisk": 500000000,
            "files": [
                {
                    "path": "encoder.mlmodelc",
                    "size": 461000000,
                    "sha256": "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
                }
            ],
            "credit": "FluidAudio Parakeet Ultra, NVIDIA Open Model License."
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        XCTAssertEqual(manifest.id, "parakeet-hebrew")
        XCTAssertEqual(manifest.kind, .speech)
        XCTAssertEqual(manifest.languages, ["he"])
        XCTAssertEqual(manifest.engine, "parakeet")
        XCTAssertEqual(manifest.minAppBuild, 1)
        XCTAssertEqual(manifest.sizeOnDisk, 500000000)
        XCTAssertEqual(manifest.files.count, 1)
        XCTAssertEqual(manifest.files[0].path, "encoder.mlmodelc")
        XCTAssertEqual(manifest.credit, "FluidAudio Parakeet Ultra, NVIDIA Open Model License.")

        let reencoded = try JSONEncoder().encode(manifest)
        let remanifest = try JSONDecoder().decode(PackManifest.self, from: reencoded)
        XCTAssertEqual(manifest, remanifest)
    }

    // Test 2: Malformed JSON throws decoding error
    func testMalformedJSONThrows() {
        let truncated = Data([0x7b, 0x22, 0x69, 0x64]) // "{"id" truncated
        XCTAssertThrowsError(try JSONDecoder().decode(PackManifest.self, from: truncated))
    }

    // Test 3: Missing required field throws
    func testMissingRequiredFieldThrows() {
        let json = """
        {
            "id": "test",
            "kind": "speech"
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(PackManifest.self, from: json))
    }

    // Test 4: Unknown kind string fails to decode
    func testUnknownKindFailsToDecodestring() {
        let json = """
        {
            "id": "test",
            "kind": "unknown-type",
            "languages": ["en"],
            "engine": "test",
            "minAppBuild": 1,
            "sizeOnDisk": 1000,
            "files": [],
            "credit": "Test"
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(PackManifest.self, from: json))
    }

    // Test 5: Empty files array is rejected
    func testEmptyFilesArrayIsRejected() throws {
        let json = """
        {
            "id": "test",
            "kind": "speech",
            "languages": ["en"],
            "engine": "test",
            "minAppBuild": 1,
            "sizeOnDisk": 1000,
            "files": [],
            "credit": "Test"
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        XCTAssertThrowsError(try manifest.validate())
    }

    // Test 6: Empty languages array is rejected
    func testEmptyLanguagesArrayIsRejected() throws {
        let json = """
        {
            "id": "test",
            "kind": "speech",
            "languages": [],
            "engine": "test",
            "minAppBuild": 1,
            "sizeOnDisk": 1000,
            "files": [
                {
                    "path": "file.mlmodelc",
                    "size": 1000,
                    "sha256": "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
                }
            ],
            "credit": "Test"
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        XCTAssertThrowsError(try manifest.validate())
    }

    // Test 7: Invalid sha256 (not 64 lowercase hex) is rejected
    func testInvalidSha256IsRejected() throws {
        let json = """
        {
            "id": "test",
            "kind": "speech",
            "languages": ["en"],
            "engine": "test",
            "minAppBuild": 1,
            "sizeOnDisk": 1000,
            "files": [
                {
                    "path": "file.mlmodelc",
                    "size": 1000,
                    "sha256": "not-a-valid-hash"
                }
            ],
            "credit": "Test"
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        XCTAssertThrowsError(try manifest.validate())
    }

    // Test 8: Negative file size is rejected
    func testNegativeFileSizeIsRejected() throws {
        let json = """
        {
            "id": "test",
            "kind": "speech",
            "languages": ["en"],
            "engine": "test",
            "minAppBuild": 1,
            "sizeOnDisk": 1000,
            "files": [
                {
                    "path": "file.mlmodelc",
                    "size": -100,
                    "sha256": "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
                }
            ],
            "credit": "Test"
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        XCTAssertThrowsError(try manifest.validate())
    }

    // Test 9: minAppBuild below 1 is rejected
    func testMinAppBuildBelowOneIsRejected() throws {
        let json = """
        {
            "id": "test",
            "kind": "speech",
            "languages": ["en"],
            "engine": "test",
            "minAppBuild": 0,
            "sizeOnDisk": 1000,
            "files": [
                {
                    "path": "file.mlmodelc",
                    "size": 1000,
                    "sha256": "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
                }
            ],
            "credit": "Test"
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        XCTAssertThrowsError(try manifest.validate())
    }

    // Test 10: Duplicate paths are rejected
    func testDuplicatePathsAreRejected() throws {
        let json = """
        {
            "id": "test",
            "kind": "speech",
            "languages": ["en"],
            "engine": "test",
            "minAppBuild": 1,
            "sizeOnDisk": 2000,
            "files": [
                {
                    "path": "file.mlmodelc",
                    "size": 1000,
                    "sha256": "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
                },
                {
                    "path": "file.mlmodelc",
                    "size": 1000,
                    "sha256": "ef001234ef001234ef001234ef001234ef001234ef001234ef001234ef001234"
                }
            ],
            "credit": "Test"
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        XCTAssertThrowsError(try manifest.validate())
    }

    // Test 11: Empty credit string is rejected
    func testEmptyCreditIsRejected() throws {
        let json = """
        {
            "id": "test",
            "kind": "speech",
            "languages": ["en"],
            "engine": "test",
            "minAppBuild": 1,
            "sizeOnDisk": 1000,
            "files": [
                {
                    "path": "file.mlmodelc",
                    "size": 1000,
                    "sha256": "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
                }
            ],
            "credit": ""
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PackManifest.self, from: json)
        XCTAssertThrowsError(try manifest.validate())
    }
}

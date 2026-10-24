import FluidAudio
import XCTest
@testable import CaptionCore

/// CONTEXT.md "On-device only": after the system speech model is installed, the captioning path
/// makes no network call. These tests pin the two guarantees that make the speaker models part of that.
final class BundledModelsTests: XCTestCase {
    func testMissingBundledModelFailsLoudlyInsteadOfDownloading() async {
        let missing = URL(fileURLWithPath: "/nonexistent/Sortformer_v2.1.mlmodelc")
        let diarizer = LiveDiarizer(modelURL: missing)
        do {
            try await diarizer.prepare()
            XCTFail("prepare() must throw when the bundled model is absent")
        } catch let error as SpeakerModelError {
            XCTAssertEqual(error, .modelMissing(missing))
        } catch {
            XCTFail("expected SpeakerModelError.modelMissing, got \(error)")
        }
    }

    func testCreatingTheDiarizerTurnsOnFluidAudioOfflineMode() {
        ModelHub.offlineMode = false
        _ = LiveDiarizer(modelURL: URL(fileURLWithPath: "/x"))
        XCTAssertTrue(ModelHub.offlineMode, "any accidental model download must throw, not fetch")
    }

    func testErrorMessageNamesTheProblemInPlainWords() {
        let e = SpeakerModelError.modelMissing(URL(fileURLWithPath: "/a/b.mlmodelc"))
        XCTAssertTrue(e.description.lowercased().contains("speaker"))
    }
}

/// ADR 0025 + ADR 0014 for the speech model: a missing folder fails loudly (and falls back), never downloads, and
/// the folder the fetch script made matches the checked-in manifest.
final class BundledSpeechModelTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testMissingParakeetFolderThrowsModelMissing() async {
        let missing = URL(fileURLWithPath: "/nonexistent/ParakeetUltra")
        do {
            try await ParakeetBackend(modelURL: missing).prepare()
            XCTFail("prepare() must throw when the bundled model is absent")
        } catch let error as SpeechModelError {
            XCTAssertEqual(error, .modelMissing(missing))
        } catch {
            XCTFail("expected SpeechModelError.modelMissing, got \(error)")
        }
    }

    func testCreatingTheParakeetBackendTurnsOnOfflineMode() {
        ModelHub.offlineMode = false
        _ = ParakeetBackend(modelURL: URL(fileURLWithPath: "/x"))
        XCTAssertTrue(ModelHub.offlineMode)
    }

    func testManifestListsEveryComponentLoadLocalNeeds() throws {
        let manifest = try String(contentsOf: repo.appendingPathComponent("scripts/models/ultra-pal6.sha256"), encoding: .utf8)
        let paths = manifest.split(separator: "\n").filter { !$0.hasPrefix("#") }.map { $0.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true) }
        XCTAssertTrue(paths.allSatisfy { $0.count == 3 && $0[0].count == 64 && Int($0[1]) != nil }, "sha256  size  path on every line")
        let files = Set(paths.map { $0[2].trimmingCharacters(in: .whitespaces) })
        for component in ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"] {
            XCTAssertTrue(files.contains("\(component).mlmodelc/coremldata.bin"), component)
        }
        XCTAssertTrue(files.contains("parakeet_v3_vocab.json"))
        XCTAssertTrue(files.contains("NOTICE.txt"), "CC BY 4.0 credit travels with the model")
        XCTAssertFalse(files.contains("config.json"), "the stale config label is not shipped")
        XCTAssertFalse(files.contains("parakeet_vocab.json"))
    }

    func testShippedNoticeNamesTheChange() throws {
        let folder = repo.appendingPathComponent("Apps/Spike/Resources/Models/ParakeetUltra")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: folder.path), "run scripts/fetch-asr-models.sh")
        let notice = try String(contentsOf: folder.appendingPathComponent("NOTICE.txt"), encoding: .utf8)
        XCTAssertTrue(notice.contains("6 bits"))
        XCTAssertTrue(notice.contains("creativecommons.org/licenses/by/4.0"))
    }
}

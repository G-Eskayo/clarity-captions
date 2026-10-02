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

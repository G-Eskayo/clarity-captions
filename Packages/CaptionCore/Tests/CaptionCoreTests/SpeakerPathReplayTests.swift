import XCTest
@testable import CaptionCore

/// The pure part of the #271 replay: what counts as one caption stream. The replay itself needs the bundled model and
/// runs from engine-eval (`engine-eval speakers`), scored in scripts/engine-eval/speaker_eval.
final class SpeakerPathReplayTests: XCTestCase {
    private func p(_ s: Double, _ e: Double) -> SpeakerReplayPhrase { SpeakerReplayPhrase(start: s, end: e) }

    func testInOrderNonOverlappingIsAStream() {
        XCTAssertTrue(SpeakerPathReplay.isStream([p(0, 1), p(1, 2.5), p(4, 5)]))
        XCTAssertTrue(SpeakerPathReplay.isStream([]))
    }

    func testOverlapIsNotAStream() {
        // Two lines on screen at once is not what the app does; the scorer must resolve overlap first.
        XCTAssertFalse(SpeakerPathReplay.isStream([p(0, 2), p(1.9, 3)]))
    }

    func testOutOfOrderIsNotAStream() {
        XCTAssertFalse(SpeakerPathReplay.isStream([p(3, 4), p(0, 1)]))
    }

    func testEmptyOrBackwardsRangeIsNotAStream() {
        XCTAssertFalse(SpeakerPathReplay.isStream([p(1, 1)]))
        XCTAssertFalse(SpeakerPathReplay.isStream([p(2, 1)]))
        XCTAssertFalse(SpeakerPathReplay.isStream([p(-0.5, 1)]))
    }

    func testReplayRefusesANonStreamBeforeLoadingAnything() async {
        let missing = URL(fileURLWithPath: "/nonexistent/Sortformer.mlmodelc")
        do {
            _ = try await SpeakerPathReplay.run(next: { nil }, phrases: [p(0, 2), p(1, 3)], modelURL: missing)
            XCTFail("expected phrasesNotAStream")
        } catch {
            XCTAssertEqual(error as? SpeakerReplayError, .phrasesNotAStream)
        }
    }
}

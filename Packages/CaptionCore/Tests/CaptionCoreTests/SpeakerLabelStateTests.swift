import XCTest
@testable import CaptionCore

final class SpeakerLabelStateTests: XCTestCase {
    func testSoundLabelLineReturnsNoneRegardlessOfSpeakerOrFinal() {
        var line = CaptionLine(id: 0, committed: "Laughter", tail: nil)
        line.soundLabel = .laughter
        XCTAssertEqual(SpeakerLabeling.state(for: line), .none, "sound label without speaker")

        line.speaker = 0
        XCTAssertEqual(SpeakerLabeling.state(for: line), .none, "sound label with speaker")
    }

    func testNonFinalLineWithoutSpeakerReturnsPending() {
        let line = CaptionLine(id: 0, committed: "Hello", tail: "wor")
        XCTAssertEqual(SpeakerLabeling.state(for: line), .pending)
    }

    func testFinalLineWithoutSpeakerReturnsUnknown() {
        let line = CaptionLine(id: 0, committed: "Hello world", tail: nil)
        XCTAssertEqual(SpeakerLabeling.state(for: line), .unknown)
    }

    func testFinalLineWithSpeakerReturnsResolved() {
        var line = CaptionLine(id: 0, committed: "Hello", tail: nil)
        line.speaker = 0
        XCTAssertEqual(SpeakerLabeling.state(for: line), .resolved(0))
    }

    func testNonFinalLineWithSpeakerReturnsResolved() {
        var line = CaptionLine(id: 0, committed: "Hello", tail: "wor")
        line.speaker = 2
        XCTAssertEqual(SpeakerLabeling.state(for: line), .resolved(2))
    }
}

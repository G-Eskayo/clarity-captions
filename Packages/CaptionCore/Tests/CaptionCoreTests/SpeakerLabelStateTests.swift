import XCTest
@testable import CaptionCore

final class SpeakerLabelStateTests: XCTestCase {
    private func captionWords(from text: String) -> [CaptionWord] {
        text.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { CaptionWord(text: $0, emphasis: .normal) }
    }

    func testSoundLabelLineReturnsNoneRegardlessOfSpeakerOrFinal() {
        var line = CaptionLine(id: 0, committed: captionWords(from: "Laughter"), tail: nil)
        line.soundLabel = .laughter
        XCTAssertEqual(SpeakerLabeling.state(for: line), .none, "sound label without speaker")

        line.speaker = 0
        XCTAssertEqual(SpeakerLabeling.state(for: line), .none, "sound label with speaker")
    }

    func testNonFinalLineWithoutSpeakerReturnsPending() {
        let line = CaptionLine(id: 0, committed: captionWords(from: "Hello"), tail: "wor")
        XCTAssertEqual(SpeakerLabeling.state(for: line), .pending)
    }

    func testFinalLineWithoutSpeakerReturnsUnknown() {
        let line = CaptionLine(id: 0, committed: captionWords(from: "Hello world"), tail: nil)
        XCTAssertEqual(SpeakerLabeling.state(for: line), .unknown)
    }

    func testFinalLineWithSpeakerReturnsResolved() {
        var line = CaptionLine(id: 0, committed: captionWords(from: "Hello"), tail: nil)
        line.speaker = 0
        XCTAssertEqual(SpeakerLabeling.state(for: line), .resolved(0))
    }

    func testNonFinalLineWithSpeakerReturnsResolved() {
        var line = CaptionLine(id: 0, committed: captionWords(from: "Hello"), tail: "wor")
        line.speaker = 2
        XCTAssertEqual(SpeakerLabeling.state(for: line), .resolved(2))
    }
}

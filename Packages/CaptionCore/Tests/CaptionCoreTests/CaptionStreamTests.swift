import XCTest
@testable import CaptionCore

final class CaptionStreamTests: XCTestCase {
    func testVolatileUpdatesReviseTheLastLineInPlace() {
        var s = CaptionStream()
        s.apply(text: "hel", isFinal: false)
        s.apply(text: "hello wor", isFinal: false)
        XCTAssertEqual(s.lines.map(\.text), ["hello wor"])
        XCTAssertFalse(s.lines[0].isFinal)
    }

    func testFinalResultClosesTheLineAndNextResultStartsANewOne() {
        var s = CaptionStream()
        s.apply(text: "hello world", isFinal: true)
        s.apply(text: "how are", isFinal: false)
        XCTAssertEqual(s.lines.map(\.text), ["hello world", "how are"])
        XCTAssertEqual(s.lines.map(\.isFinal), [true, false])
    }

    func testBlankTextIsIgnored() {
        var s = CaptionStream()
        s.apply(text: "   ", isFinal: false)
        XCTAssertTrue(s.lines.isEmpty)
    }

    func testLineIDsAreStableAcrossRevisions() {
        var s = CaptionStream()
        s.apply(text: "a", isFinal: false)
        let id = s.lines[0].id
        s.apply(text: "ab", isFinal: false)
        XCTAssertEqual(s.lines[0].id, id)
    }

    // MARK: - Sound labels

    func testInsertSoundLabelAddsNewLine() {
        var s = CaptionStream()
        s.insertSoundLabel(.laughter)
        XCTAssertEqual(s.lines.count, 1)
        XCTAssertEqual(s.lines[0].soundLabel, .laughter)
        XCTAssertEqual(s.lines[0].text, "[Laughter]")
    }

    func testInsertSoundLabelIsAlwaysFinal() {
        var s = CaptionStream()
        s.insertSoundLabel(.applause)
        XCTAssertTrue(s.lines[0].isFinal)
        XCTAssertNil(s.lines[0].tail)
    }

    func testInsertSoundLabelClosesOpenTail() {
        var s = CaptionStream()
        s.apply(text: "hel", isFinal: false)
        XCTAssertTrue(s.lines[0].tail != nil)
        s.insertSoundLabel(.doorbell)
        XCTAssertEqual(s.lines.count, 2)
        XCTAssertTrue(s.lines[0].isFinal)
        XCTAssertEqual(s.lines[0].text, "hel")
        XCTAssertEqual(s.lines[1].soundLabel, .doorbell)
    }

    func testSpeechAfterSoundLabelStartsNewLine() {
        var s = CaptionStream()
        s.insertSoundLabel(.laughter)
        s.apply(text: "hello", isFinal: false)
        XCTAssertEqual(s.lines.count, 2)
        XCTAssertEqual(s.lines[0].soundLabel, .laughter)
        XCTAssertNil(s.lines[1].soundLabel)
        XCTAssertEqual(s.lines[1].text, "hello")
    }

    func testSpeechNeverMergesIntoSoundLabel() {
        var s = CaptionStream()
        s.insertSoundLabel(.applause)
        s.apply(text: "thank", isFinal: true)
        s.apply(text: "you", isFinal: false)
        XCTAssertEqual(s.lines.count, 3)
        XCTAssertEqual(s.lines[0].soundLabel, .applause)
        XCTAssertEqual(s.lines[1].text, "thank")
        XCTAssertEqual(s.lines[2].text, "you")
    }

    func testMultipleSoundLabelsInSequence() {
        var s = CaptionStream()
        s.insertSoundLabel(.laughter)
        s.apply(text: "hello", isFinal: true)
        s.insertSoundLabel(.applause)
        XCTAssertEqual(s.lines.count, 3)
        XCTAssertEqual(s.lines[0].soundLabel, .laughter)
        XCTAssertNil(s.lines[1].soundLabel)
        XCTAssertEqual(s.lines[2].soundLabel, .applause)
    }

    func testSoundLabelLineHasNilSpeaker() {
        var s = CaptionStream()
        s.insertSoundLabel(.knock)
        XCTAssertNil(s.lines[0].speaker)
    }

    func testSoundLabelIsSoundLabelPropertyWorks() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true)
        s.insertSoundLabel(.phoneRinging)
        XCTAssertFalse(s.lines[0].isSoundLabel)
        XCTAssertTrue(s.lines[1].isSoundLabel)
    }
}

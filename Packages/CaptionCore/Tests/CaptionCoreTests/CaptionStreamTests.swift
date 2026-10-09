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

    // MARK: - Start time tracking for export

    func testStartTimeSetFromRangeLowerBound() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true, range: 1.5...2.5)
        XCTAssertEqual(s.lines[0].startTime, 1.5)
    }

    func testStartTimeNilWhenNoRange() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true)
        XCTAssertNil(s.lines[0].startTime)
    }

    func testStartTimePreservedAcrossTailRevisions() {
        var s = CaptionStream()
        s.apply(text: "hel", isFinal: false, range: 1.0...1.5)
        let originalStartTime = s.lines[0].startTime
        s.apply(text: "hello", isFinal: false, range: 1.0...2.0)
        XCTAssertEqual(s.lines[0].startTime, originalStartTime)
    }

    func testStartTimePreservedAfterCommit() {
        var s = CaptionStream()
        s.apply(text: "hel", isFinal: false, range: 1.0...1.5)
        s.apply(text: "hello", isFinal: true, range: 1.0...2.0)
        XCTAssertEqual(s.lines[0].startTime, 1.0)
        XCTAssertTrue(s.lines[0].isFinal)
    }

    func testSoundLabelStartTimeNil() {
        var s = CaptionStream()
        s.insertSoundLabel(.laughter)
        XCTAssertNil(s.lines[0].startTime)
    }

    // MARK: - Emphasis

    func testCommittedWordsCarryEmphasis() {
        var s = CaptionStream()
        s.apply(text: "hello world", isFinal: true, wordEmphasis: [.normal, .loud])
        XCTAssertEqual(s.lines[0].styledWords.count, 2)
        XCTAssertEqual(s.lines[0].styledWords[0].text, "hello")
        XCTAssertEqual(s.lines[0].styledWords[0].emphasis, .normal)
        XCTAssertEqual(s.lines[0].styledWords[1].text, "world")
        XCTAssertEqual(s.lines[0].styledWords[1].emphasis, .loud)
    }

    func testVolatileTailHasNoEmphasis() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: false, wordEmphasis: [.loud])
        XCTAssertEqual(s.lines[0].styledWords.count, 0, "volatile tail should not create committed words")
        XCTAssertEqual(s.lines[0].tail, "hello")
    }

    func testMismatchedEmphasisCountDefaultsToNormal() {
        var s = CaptionStream()
        s.apply(text: "hello world", isFinal: true, wordEmphasis: [.loud])
        XCTAssertEqual(s.lines[0].styledWords[0].emphasis, .loud)
        XCTAssertEqual(s.lines[0].styledWords[1].emphasis, .normal, "missing emphasis defaults to normal")
    }

    func testSoundLabelWordsDefaultToNormal() {
        var s = CaptionStream()
        s.insertSoundLabel(.laughter)
        XCTAssertTrue(s.lines[0].styledWords.allSatisfy { $0.emphasis == .normal })
    }

    // MARK: - Markers

    func testInsertMarkerAddsNewLine() {
        var s = CaptionStream()
        let markerText = "— while you were away —"
        s.insertMarker(markerText)
        XCTAssertEqual(s.lines.count, 1)
        XCTAssertEqual(s.lines[0].marker, markerText)
    }

    func testInsertMarkerIsAlwaysFinal() {
        var s = CaptionStream()
        s.insertMarker("— while you were away —")
        XCTAssertTrue(s.lines[0].isFinal)
        XCTAssertNil(s.lines[0].tail)
    }

    func testInsertMarkerClosesOpenTailOnPreviousLine() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: false)
        XCTAssertEqual(s.lines[0].text, "hello")
        XCTAssertFalse(s.lines[0].isFinal)
        s.insertMarker("— while you were away —")
        XCTAssertEqual(s.lines.count, 2)
        XCTAssertTrue(s.lines[0].isFinal, "previous line's tail must be finalized")
        XCTAssertEqual(s.lines[1].marker, "— while you were away —")
    }

    func testSpeechAfterMarkerStartsNewLine() {
        var s = CaptionStream()
        s.insertMarker("— while you were away —")
        s.apply(text: "hello", isFinal: false)
        XCTAssertEqual(s.lines.count, 2)
        XCTAssertTrue(s.lines[0].isMarker)
        XCTAssertFalse(s.lines[1].isMarker)
        XCTAssertEqual(s.lines[1].text, "hello")
    }

    // MARK: - Unbounded scrollback

    func testUnboundedScrollbackLargeTranscript() {
        var s = CaptionStream()
        for i in 0..<1000 {
            s.apply(text: "Line \(i)", isFinal: true)
        }
        XCTAssertEqual(s.lines.count, 1000, "all 1000 lines should be retained for scrollback")
    }
}

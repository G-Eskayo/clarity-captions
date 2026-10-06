import XCTest
@testable import CaptionCore

final class TranscriptExportTests: XCTestCase {
    // MARK: - Plain text formatting

    func testPlainTextWithoutSpeakers() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true)
        s.apply(text: "world", isFinal: true)
        let text = TranscriptFormatter.plainText(lines: s.lines)
        XCTAssertEqual(text, "hello\nworld")
    }

    func testPlainTextWithResolvedSpeakers() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true, speaker: 0)
        s.apply(text: "world", isFinal: true, speaker: 1)
        let text = TranscriptFormatter.plainText(lines: s.lines)
        XCTAssertEqual(text, "Speaker 1: hello\nSpeaker 2: world")
    }

    func testPlainTextWithMixedSpeakerStates() {
        var s = CaptionStream()
        s.apply(text: "hi", isFinal: true, speaker: 0)
        s.apply(text: "hey", isFinal: true)  // no speaker
        s.apply(text: "yo", isFinal: true, speaker: 1)
        let text = TranscriptFormatter.plainText(lines: s.lines)
        XCTAssertEqual(text, "Speaker 1: hi\nhey\nSpeaker 2: yo")
    }

    func testPlainTextIncludesSoundLabels() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true, speaker: 0)
        s.insertSoundLabel(.laughter)
        s.apply(text: "that's funny", isFinal: true, speaker: 0)
        let text = TranscriptFormatter.plainText(lines: s.lines)
        XCTAssertEqual(text, "Speaker 1: hello\n[Laughter]\nSpeaker 1: that's funny")
    }

    func testPlainTextIncludesVolatileLineIfPresent() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true)
        s.apply(text: "wo", isFinal: false)  // volatile
        let text = TranscriptFormatter.plainText(lines: s.lines)
        XCTAssertEqual(text, "hello\nwo")
    }

    func testPlainTextEmptyStream() {
        let s = CaptionStream()
        let text = TranscriptFormatter.plainText(lines: s.lines)
        XCTAssertEqual(text, "")
    }

    // MARK: - SRT formatting

    func testSRTBasicStructure() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true, range: 0...1)
        let srt = TranscriptFormatter.srt(lines: s.lines)
        XCTAssertTrue(srt.contains("1\n") && srt.contains("0:00:00,000 --> 0:00:01,000"))
        XCTAssertTrue(srt.contains("hello"))
    }

    func testSRTMultipleBlocks() {
        var s = CaptionStream()
        s.apply(text: "first", isFinal: true, range: 0...1)
        s.apply(text: "second", isFinal: true, range: 3...4)  // gap > 1.2s pause threshold
        let srt = TranscriptFormatter.srt(lines: s.lines)
        XCTAssertTrue(srt.contains("1\n") && srt.contains("0:00:00,000 --> 0:00:01,000"))
        XCTAssertTrue(srt.contains("2\n") && srt.contains("0:00:03,000 --> 0:00:04,000"))
        XCTAssertTrue(srt.contains("first"))
        XCTAssertTrue(srt.contains("second"))
    }

    func testSRTWithSpeakerLabels() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true, speaker: 0, range: 0...1)
        s.apply(text: "hi", isFinal: true, speaker: 1, range: 2...3)
        let srt = TranscriptFormatter.srt(lines: s.lines)
        XCTAssertTrue(srt.contains("Speaker 1: hello"))
        XCTAssertTrue(srt.contains("Speaker 2: hi"))
    }

    func testSRTIncludesVolatileLine() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true, range: 0...1)
        s.apply(text: "wo", isFinal: false, range: 3...4)  // gap > 1.2s pause threshold
        let srt = TranscriptFormatter.srt(lines: s.lines)
        XCTAssertTrue(srt.contains("2") && srt.contains("0:00:03,000 --> 0:00:04,000"))
        XCTAssertTrue(srt.contains("wo"))
    }

    func testSRTEmptyStream() {
        let s = CaptionStream()
        let srt = TranscriptFormatter.srt(lines: s.lines)
        XCTAssertEqual(srt, "")
    }

    // MARK: - Timing handling

    func testSRTTimestampFormatting() {
        var s = CaptionStream()
        s.apply(text: "test", isFinal: true, range: 65.5...67.5)
        let srt = TranscriptFormatter.srt(lines: s.lines)
        // 65.5 seconds = 0:01:05,500
        // 67.5 seconds = 0:01:07,500
        XCTAssertTrue(srt.contains("0:01:05,500 --> 0:01:07,500"))
    }

    func testSRTMissingStartTimeUsesZero() {
        var s = CaptionStream()
        s.apply(text: "test", isFinal: true)  // no range
        let srt = TranscriptFormatter.srt(lines: s.lines)
        XCTAssertTrue(srt.contains("1") && srt.contains("0:00:00,000 --> 0:00:00,500"))
    }

    func testSRTMissingTimingSynthesizedFromPreviousLine() {
        var s = CaptionStream()
        s.apply(text: "first", isFinal: true, range: 0...1)
        s.apply(text: "second", isFinal: true)  // no range, should chain from first's end
        let srt = TranscriptFormatter.srt(lines: s.lines)
        XCTAssertTrue(srt.contains("1") && srt.contains("0:00:00,000 --> 0:00:01,000"))
        XCTAssertTrue(srt.contains("2") && srt.contains("0:00:01,000 --> 0:00:01,500"))  // 1s + 0.5s minimum duration
    }
}

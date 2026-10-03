import XCTest
@testable import CaptionCore

/// Lines break at real pauses and speaker changes, and flow together in between, so conversation reads as
/// paragraphs, not a wall of text and not a line per fragment. Times are seconds of audio.
final class PauseBreaksTests: XCTestCase {
    func testContinuousSpeechFromTheSameSpeakerFlowsIntoOneLine() {
        var s = CaptionStream()
        s.apply(text: "hello there", isFinal: true, speaker: 0, range: 0.0...1.0)
        s.apply(text: "how are you", isFinal: true, speaker: 0, range: 1.2...2.0)
        XCTAssertEqual(s.lines.map(\.text), ["hello there how are you"])
    }

    func testALongPauseStartsANewLine() {
        var s = CaptionStream()
        s.apply(text: "hello there", isFinal: true, speaker: 0, range: 0.0...1.0)
        s.apply(text: "anyway", isFinal: true, speaker: 0, range: 3.0...3.6)
        XCTAssertEqual(s.lines.map(\.text), ["hello there", "anyway"])
    }

    func testASpeakerChangeStartsANewLineEvenWithNoPause() {
        var s = CaptionStream()
        s.apply(text: "hello there", isFinal: true, speaker: 0, range: 0.0...1.0)
        s.apply(text: "hi", isFinal: true, speaker: 1, range: 1.05...1.4)
        XCTAssertEqual(s.lines.map(\.text), ["hello there", "hi"])
        XCTAssertEqual(s.lines.map(\.speaker), [0, 1])
    }

    func testVolatileRevisionsOfTheSameSegmentReplaceTheTail() {
        var s = CaptionStream()
        s.apply(text: "hel", isFinal: false, speaker: 0, range: 0.0...0.5)
        s.apply(text: "hello", isFinal: false, speaker: 0, range: 0.0...1.0)
        XCTAssertEqual(s.lines.map(\.text), ["hello"])
        XCTAssertFalse(s.lines[0].isFinal)
    }

    func testFinalResultClosesTheTail() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: false, speaker: 0, range: 0.0...1.0)
        s.apply(text: "hello.", isFinal: true, speaker: 0, range: 0.0...1.0)
        XCTAssertEqual(s.lines.map(\.text), ["hello."])
        XCTAssertTrue(s.lines[0].isFinal)
    }

    func testNewVolatileSpeechAfterAJoinedFinalExtendsTheSameLine() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true, speaker: 0, range: 0.0...1.0)
        s.apply(text: "wor", isFinal: false, speaker: 0, range: 1.1...1.4)
        XCTAssertEqual(s.lines.map(\.text), ["hello wor"])
        XCTAssertFalse(s.lines[0].isFinal)
        s.apply(text: "world", isFinal: true, speaker: 0, range: 1.1...1.8)
        XCTAssertEqual(s.lines.map(\.text), ["hello world"])
        XCTAssertTrue(s.lines[0].isFinal)
    }

    func testUnknownSpeakersNeverForceABreak() {
        var s = CaptionStream()
        s.apply(text: "one", isFinal: true, speaker: nil, range: 0.0...0.5)
        s.apply(text: "two", isFinal: true, speaker: 1, range: 0.6...1.0)
        XCTAssertEqual(s.lines.map(\.text), ["one two"])
    }

    func testPauseLengthIsASingleNamedSetting() {
        var s = CaptionStream(pauseSeconds: 0.5)
        s.apply(text: "one", isFinal: true, speaker: 0, range: 0.0...1.0)
        s.apply(text: "two", isFinal: true, speaker: 0, range: 1.6...2.0)
        XCTAssertEqual(s.lines.count, 2)
        XCTAssertEqual(CaptionStream.defaultPauseSeconds, CaptionStream().pauseSeconds)
    }

    func testLineIDStaysStableWhileSpeechFlowsIn() {
        var s = CaptionStream()
        s.apply(text: "one", isFinal: true, speaker: 0, range: 0.0...1.0)
        let id = s.lines[0].id
        s.apply(text: "two", isFinal: false, speaker: 0, range: 1.1...1.5)
        s.apply(text: "two three", isFinal: true, speaker: 0, range: 1.1...2.0)
        XCTAssertEqual(s.lines[0].id, id)
    }
}

/// While captioning, Stop shrinks to a small circle so captions get the room; otherwise the big button returns.
final class CompactStopTests: XCTestCase {
    func testListeningUsesTheCompactCircle() {
        XCTAssertEqual(PrimaryControl.for(.listening).presentation, .compact)
    }

    func testEverythingElseUsesTheLargeButton() {
        for state in [CaptionState.idle, .preparing, .failed("x")] {
            XCTAssertEqual(PrimaryControl.for(state).presentation, .large, "\(state)")
        }
    }

    func testCompactStopStillHasAClearSpokenLabel() {
        XCTAssertEqual(PrimaryControl.for(.listening).accessibilityLabel, "Stop captions")
        XCTAssertEqual(PrimaryControl.for(.idle).accessibilityLabel, "Start captions")
    }

    func testCompactTouchTargetIsAtLeastFortyFourPoints() {
        XCTAssertGreaterThanOrEqual(PrimaryControl.compactDiameter, 44)
    }
}

import XCTest
@testable import CaptionCore

final class CaptionSessionLifecycleTests: XCTestCase {
    func testActionIsNoneWhenSessionNotStarted() {
        var stream = CaptionStream()
        stream.apply(text: "hello", isFinal: true)

        let action = CaptionSessionLifecycle.action(
            for: .idle,
            sessionStartedAt: nil,
            lines: stream.lines
        )

        XCTAssertEqual(action, .none)
    }

    func testActionIsNoneWhenStateIsPreparing() {
        let now = Date()
        var stream = CaptionStream()
        stream.apply(text: "hello", isFinal: true)

        let action = CaptionSessionLifecycle.action(
            for: .preparing,
            sessionStartedAt: now,
            lines: stream.lines
        )

        XCTAssertEqual(action, .none)
    }

    func testActionIsNoneWhenStateIsListening() {
        let now = Date()
        var stream = CaptionStream()
        stream.apply(text: "hello", isFinal: true)

        let action = CaptionSessionLifecycle.action(
            for: .listening,
            sessionStartedAt: now,
            lines: stream.lines
        )

        XCTAssertEqual(action, .none)
    }

    func testActionIsNoneWhenStatePaused() {
        let now = Date()
        var stream = CaptionStream()
        stream.apply(text: "hello", isFinal: true)

        let action = CaptionSessionLifecycle.action(
            for: .paused("another app is using the microphone"),
            sessionStartedAt: now,
            lines: stream.lines
        )

        XCTAssertEqual(action, .none)
    }

    func testActionIsSaveWhenIdleWithContent() {
        let now = Date()
        var stream = CaptionStream()
        stream.apply(text: "hello world", isFinal: true)

        let action = CaptionSessionLifecycle.action(
            for: .idle,
            sessionStartedAt: now,
            lines: stream.lines
        )

        switch action {
        case .save(let conversation):
            XCTAssertEqual(conversation.transcript, "hello world")
            XCTAssertEqual(conversation.startedAt, now)
        default:
            XCTFail("Expected save action")
        }
    }

    func testActionIsSaveWhenFailedWithContent() {
        let now = Date()
        var stream = CaptionStream()
        stream.apply(text: "partially captured", isFinal: true)

        let action = CaptionSessionLifecycle.action(
            for: .failed("Mic disconnected"),
            sessionStartedAt: now,
            lines: stream.lines
        )

        switch action {
        case .save(let conversation):
            XCTAssertEqual(conversation.transcript, "partially captured")
        default:
            XCTFail("Expected save action")
        }
    }

    func testActionIsDiscardWhenIdleWithBlankOnly() {
        let now = Date()
        var stream = CaptionStream()
        stream.apply(text: "   ", isFinal: true)
        stream.apply(text: "\n", isFinal: true)

        let action = CaptionSessionLifecycle.action(
            for: .idle,
            sessionStartedAt: now,
            lines: stream.lines
        )

        XCTAssertEqual(action, .discard)
    }

    func testActionIsDiscardWhenFailedWithBlankOnly() {
        let now = Date()
        var stream = CaptionStream()
        stream.apply(text: "", isFinal: true)

        let action = CaptionSessionLifecycle.action(
            for: .failed("Timed out"),
            sessionStartedAt: now,
            lines: stream.lines
        )

        XCTAssertEqual(action, .discard)
    }

    func testActionIsSaveWithSoundLabelOnly() {
        let now = Date()
        var stream = CaptionStream()
        stream.insertSoundLabel(.laughter)

        let action = CaptionSessionLifecycle.action(
            for: .idle,
            sessionStartedAt: now,
            lines: stream.lines
        )

        switch action {
        case .save(let conversation):
            XCTAssertTrue(conversation.transcript.contains("Laughter"))
        default:
            XCTFail("Expected save action")
        }
    }

    func testSavedConversationIncludesSpeakerNames() {
        let now = Date()
        var stream = CaptionStream()
        stream.apply(text: "Hello", isFinal: true, speaker: 0)
        stream.apply(text: "Hi there", isFinal: true, speaker: 1)

        var speakers = SpeakerNames()
        speakers.apply("Alice", to: 0)
        speakers.apply("Bob", to: 1)

        let action = CaptionSessionLifecycle.action(
            for: .idle,
            sessionStartedAt: now,
            lines: stream.lines,
            speakerNames: speakers
        )

        switch action {
        case .save(let conversation):
            XCTAssertTrue(conversation.transcript.contains("Alice"))
            XCTAssertTrue(conversation.transcript.contains("Bob"))
        default:
            XCTFail("Expected save action")
        }
    }

    func testDiscardActionIsEquatable() {
        let now = Date()
        var stream = CaptionStream()
        stream.apply(text: "   ", isFinal: true)

        let action1 = CaptionSessionLifecycle.action(
            for: .idle,
            sessionStartedAt: now,
            lines: stream.lines
        )

        let action2 = CaptionSessionLifecycle.action(
            for: .idle,
            sessionStartedAt: now,
            lines: stream.lines
        )

        XCTAssertEqual(action1, action2)
        XCTAssertEqual(action1, .discard)
    }

    func testNoneActionIsEquatable() {
        let now = Date()
        var stream = CaptionStream()
        stream.apply(text: "test", isFinal: true)

        let action1 = CaptionSessionLifecycle.action(
            for: .preparing,
            sessionStartedAt: now,
            lines: stream.lines
        )

        let action2 = CaptionSessionLifecycle.action(
            for: .preparing,
            sessionStartedAt: now,
            lines: stream.lines
        )

        XCTAssertEqual(action1, action2)
        XCTAssertEqual(action1, .none)
    }
}

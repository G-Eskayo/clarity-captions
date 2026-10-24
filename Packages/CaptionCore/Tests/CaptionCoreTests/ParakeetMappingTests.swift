import CoreMedia
import Speech
import XCTest
@testable import CaptionCore

/// Parakeet's committed and open words fed through a real CaptionStream (design §8, test 6), plus the pieces either
/// recognizer hands TranscriptionEngine.
final class ParakeetMappingTests: XCTestCase {
    private func w(_ text: String, _ start: Double, _ end: Double) -> TimedWord { TimedWord(text: text, start: start, end: end) }

    private func apply(_ pieces: [RecognizedPiece], to stream: inout CaptionStream, speaker: Int? = nil) {
        for p in pieces {
            stream.apply(text: p.text, isFinal: p.isFinal, speaker: speaker, range: p.start.flatMap { s in p.end.map { s...$0 } })
        }
    }

    func testCommittedThenOpenWordsMakeOneLine() {
        var emitter = ParakeetEmitter()
        var stream = CaptionStream()
        apply(emitter.pieces(final: [], volatile: [w("hello", 0, 0.3), w("there", 0.4, 0.7)]), to: &stream)
        apply(emitter.pieces(final: [w("hello", 0, 0.3), w("there", 0.4, 0.7)], volatile: [w("friend", 0.8, 1.1)]), to: &stream)
        XCTAssertEqual(stream.lines.count, 1)
        XCTAssertEqual(stream.lines[0].text, "hello there friend")
        XCTAssertFalse(stream.lines[0].isFinal)
        apply(emitter.pieces(final: [w("friend", 0.8, 1.1)], volatile: []), to: &stream)
        XCTAssertEqual(stream.lines.map(\.text), ["hello there friend"])
        XCTAssertTrue(stream.lines[0].isFinal)
    }

    func testAPauseInsideACommittedBatchStartsANewLine() {
        var emitter = ParakeetEmitter()
        var stream = CaptionStream()
        let pieces = emitter.pieces(final: [w("yes", 0, 0.3), w("no", 2.0, 2.3)], volatile: [])
        XCTAssertEqual(pieces.count, 2)
        apply(pieces, to: &stream)
        XCTAssertEqual(stream.lines.map(\.text), ["yes", "no"])
    }

    func testATailThatChangedCompletelyIsReplacedNotKept() {
        // The decoder first heard "oh" then decided it was "go home", starting later: the ghost must not stay.
        var emitter = ParakeetEmitter()
        var stream = CaptionStream()
        apply(emitter.pieces(final: [w("ok", 0, 0.2)], volatile: [w("oh", 0.4, 0.6)]), to: &stream)
        apply(emitter.pieces(final: [], volatile: [w("go", 0.9, 1.0), w("home", 1.1, 1.3)]), to: &stream)
        XCTAssertEqual(stream.lines.map(\.text), ["ok go home"])
        apply(emitter.pieces(final: [w("go", 0.9, 1.0), w("home", 1.1, 1.3)], volatile: []), to: &stream)
        XCTAssertEqual(stream.lines.map(\.text), ["ok go home"])
    }

    func testAnUnchangedTailIsNotSentAgain() {
        var emitter = ParakeetEmitter()
        XCTAssertEqual(emitter.pieces(final: [], volatile: [w("hm", 0, 0.2)]).count, 1)
        XCTAssertEqual(emitter.pieces(final: [], volatile: [w("hm", 0, 0.2)]).count, 0)
    }

    func testASpeakerChangeStillSplitsTheLine() {
        var emitter = ParakeetEmitter()
        var stream = CaptionStream()
        apply(emitter.pieces(final: [w("hi", 0, 0.2)], volatile: []), to: &stream, speaker: 0)
        apply(emitter.pieces(final: [w("hey", 0.4, 0.6)], volatile: []), to: &stream, speaker: 1)
        XCTAssertEqual(stream.lines.map(\.text), ["hi", "hey"])
    }

    // MARK: Apple's runs to words (refactor guard for word emphasis)

    func testAppleRunsBecomeWordsWithTheirRunsTime() {
        var text = AttributedString("good morning")
        text.audioTimeRange = CMTimeRange(start: CMTime(seconds: 1, preferredTimescale: 600), end: CMTime(seconds: 2, preferredTimescale: 600))
        var untimed = AttributedString(" all")
        untimed.audioTimeRange = nil
        text.append(untimed)
        let piece = AppleSpeechBackend.piece(from: text, isFinal: true)
        XCTAssertEqual(piece.text, "good morning all")
        XCTAssertEqual(piece.words, [RecognizedWord(text: "good", range: 1...2), RecognizedWord(text: "morning", range: 1...2),
                                     RecognizedWord(text: "all", range: nil)])
        XCTAssertEqual(piece.start, 1)
        XCTAssertEqual(piece.end, 2)
    }

    func testEmphasisIsPerWordAndUntimedWordsStayNormal() {
        let words = [RecognizedWord(text: "a", range: 0...1), RecognizedWord(text: "b", range: nil), RecognizedWord(text: "c", range: 2...3)]
        let levels = WordEmphasis.levels(for: words, baseline: -40, loudness: { $0.lowerBound < 1 ? -20 : -39 }, fallback: -60)
        XCTAssertEqual(levels, [.loud, .normal, .normal])
        XCTAssertEqual(WordEmphasis.levels(for: words, baseline: nil, loudness: { _ in 0 }, fallback: 0), [.normal, .normal, .normal])
    }

    // MARK: Sample window

    func testSampleWindowTrimsAndStaysBounded() {
        var window = SampleWindow(maxSeconds: 2)
        window.append([Float](repeating: 0, count: 16_000), speech: false)
        window.append([Float](repeating: 1, count: 16_000), speech: true)
        let shot = window.take(from: 0.5)
        XCTAssertEqual(shot.start, 0.5, accuracy: 1e-9)
        XCTAssertEqual(shot.end, 2.0, accuracy: 1e-9)
        XCTAssertEqual(shot.samples.count, 24_000)
        XCTAssertTrue(shot.speech)
        XCTAssertFalse(window.take(from: 0).speech, "speech is reported once per take")
        window.trim(before: 1.0)
        XCTAssertEqual(window.startTime, 1.0, accuracy: 1e-9)
        window.append([Float](repeating: 0, count: 64_000), speech: false)
        XCTAssertEqual(window.samples.count, 32_000, "never more than maxSeconds")
        XCTAssertEqual(window.endTime, 6.0, accuracy: 1e-9, "dropping old audio never moves the clock")
        window.trim(before: 100)
        XCTAssertEqual(window.samples.count, 0)
        XCTAssertEqual(window.take(from: 50).samples, [])
    }
}

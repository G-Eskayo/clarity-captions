import FluidAudio
import XCTest
@testable import CaptionCore

/// Sub-word tokens to words (design §8, test 2). Reuses FluidAudio's own `buildWordTimings`, so this checks our
/// window offset and the edge cases we rely on, not a second merger.
final class ParakeetWordsTests: XCTestCase {
    private func tok(_ s: String, _ start: Double, _ end: Double) -> TokenTiming {
        TokenTiming(token: s, tokenId: 0, startTime: start, endTime: end, confidence: 1)
    }

    func testWordStartsAreMarkedAndSubwordsJoin() {
        let words = ParakeetWords.words(from: [tok("▁hel", 0.0, 0.1), tok("lo", 0.1, 0.2), tok("▁world", 0.3, 0.6)], windowStart: 0)
        XCTAssertEqual(words, [TimedWord(text: "hello", start: 0.0, end: 0.2), TimedWord(text: "world", start: 0.3, end: 0.6)])
    }

    func testPunctuationStaysOnItsWord() {
        let words = ParakeetWords.words(from: [tok("▁Yes", 0.0, 0.2), tok(",", 0.2, 0.25), tok("▁okay", 0.3, 0.5), tok(".", 0.5, 0.55)], windowStart: 0)
        XCTAssertEqual(words.map(\.text), ["Yes,", "okay."])
        XCTAssertEqual(words.last?.end, 0.55)
    }

    func testWindowStartShiftsEveryTimeOnce() {
        let words = ParakeetWords.words(from: [tok("▁a", 0.1, 0.2)], windowStart: 7.5)
        XCTAssertEqual(words, [TimedWord(text: "a", start: 7.6, end: 7.7)])
    }

    func testEmptyAndBlankTokensGiveNoWords() {
        XCTAssertEqual(ParakeetWords.words(from: [], windowStart: 3), [])
        XCTAssertEqual(ParakeetWords.words(from: [tok("<blank>", 0, 0.1), tok("", 0.1, 0.2), tok("▁", 0.2, 0.3)], windowStart: 0), [])
    }

    func testAContinuationWithNoWordStartBeforeItStillBecomesAWord() {
        // A window can open in the middle of a word; the fragment must not vanish or glue onto nothing.
        let words = ParakeetWords.words(from: [tok("ing", 0.0, 0.1), tok("▁next", 0.2, 0.4)], windowStart: 0)
        XCTAssertEqual(words.map(\.text), ["ing", "next"])
    }
}

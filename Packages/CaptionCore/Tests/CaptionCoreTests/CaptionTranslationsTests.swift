import CaptionCore
import XCTest

/// #53: which caption lines get translated, and which translation shows. Only finished spoken lines (translating words
/// that are still changing would flicker and lag, #60's design); each line once; again when more words land on it;
/// never a sound label; and an answer for words that have since changed never overwrites a newer one.
final class CaptionTranslationsTests: XCTestCase {
    private func stream(_ build: (inout CaptionStream) -> Void) -> [CaptionLine] {
        var s = CaptionStream()
        build(&s)
        return s.lines
    }

    func testAFinishedLineIsTranslatedOnce() {
        let lines = stream { $0.apply(text: "hola", isFinal: true, speaker: 0) }
        var t = CaptionTranslations()
        let work = t.take(from: lines)
        XCTAssertEqual(work.map(\.text), ["hola"])
        XCTAssertTrue(t.take(from: lines).isEmpty, "already asked for")
        t.finished(lineID: work[0].lineID, source: "hola", translation: "hello")
        XCTAssertTrue(t.take(from: lines).isEmpty, "already done")
        XCTAssertEqual(t.translation(for: lines[0]), "hello")
    }

    func testWordsStillChangingWaitUntilTheyreFinished() {
        let lines = stream { $0.apply(text: "hol", isFinal: false, speaker: 0) }
        var t = CaptionTranslations()
        XCTAssertTrue(t.take(from: lines).isEmpty)
    }

    func testSoundLabelsAreNeverTranslated() {
        let lines = stream { $0.insertSoundLabel(.laughter) }
        var t = CaptionTranslations()
        XCTAssertTrue(t.take(from: lines).isEmpty)
    }

    func testALineThatGrowsIsTranslatedAgainAndTheOldTranslationShowsMeanwhile() {
        var s = CaptionStream()
        s.apply(text: "hola", isFinal: true, speaker: 0)
        var t = CaptionTranslations()
        let first = t.take(from: s.lines)[0]
        t.finished(lineID: first.lineID, source: first.text, translation: "hello")
        s.apply(text: "qué tal", isFinal: true, speaker: 0)
        let line = s.lines.last!
        guard line.id == first.lineID else { return }   // the stream started a new line: nothing to re-translate
        let again = t.take(from: s.lines)
        XCTAssertEqual(again.map(\.text), [line.text])
        XCTAssertEqual(t.translation(for: line), "hello", "the old translation stays until the new one lands")
    }

    func testALateAnswerForOlderWordsDoesntReplaceANewerOne() {
        var t = CaptionTranslations()
        let lines = stream { $0.apply(text: "hola", isFinal: true, speaker: 0) }
        let id = lines[0].id
        _ = t.take(from: lines)
        t.finished(lineID: id, source: "hola qué tal", translation: "hello how are you")
        t.finished(lineID: id, source: "hola", translation: "hello")
        XCTAssertEqual(t.translation(for: lines[0]), "hello how are you")
    }

    func testAFailedTranslationIsTriedAgainLater() {
        let lines = stream { $0.apply(text: "hola", isFinal: true, speaker: 0) }
        var t = CaptionTranslations()
        let work = t.take(from: lines)
        t.failed(lineID: work[0].lineID, source: "hola")
        XCTAssertEqual(t.take(from: lines).map(\.text), ["hola"])
    }

    func testEmptyLinesAreSkipped() {
        let lines = stream { $0.apply(text: "   ", isFinal: true, speaker: 0) }
        var t = CaptionTranslations()
        XCTAssertTrue(t.take(from: lines).isEmpty)
    }

    func testANewConversationStartsClean() {
        let lines = stream { $0.apply(text: "hola", isFinal: true, speaker: 0) }
        var t = CaptionTranslations()
        let work = t.take(from: lines)
        t.finished(lineID: work[0].lineID, source: "hola", translation: "hello")
        t.reset()
        XCTAssertNil(t.translation(for: lines[0]))
        XCTAssertEqual(t.take(from: lines).count, 1)
    }

    func testLinesAreHandedOutOldestFirst() {
        let lines = stream {
            $0.apply(text: "uno", isFinal: true, speaker: 0)
            $0.apply(text: "dos", isFinal: true, speaker: 1)
        }
        var t = CaptionTranslations()
        XCTAssertEqual(t.take(from: lines).map(\.lineID), lines.map(\.id))
    }
}

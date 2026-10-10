import XCTest
@testable import CaptionCore

/// Copying (#107): press and hold to select caption text across lines; a Copy-only button appears once the selection
/// has settled for half a second. The selection lives in caption positions (line + UTF-16 offset into its text), so it
/// survives scrolling and keeps working while new captions arrive.
final class CaptionSelectionTests: XCTestCase {

    /// Three finished lines and one still being heard: Gil, Dana, a laugh, then Gil mid-sentence.
    private func transcript() -> [CaptionLine] {
        var s = CaptionStream()
        s.apply(text: "Meet us at Luigi's on Fifth", isFinal: true, speaker: 0)
        s.apply(text: "Around seven, okay?", isFinal: true, speaker: 1)
        s.insertSoundLabel(.laughter)
        s.apply(text: "I'll call them", isFinal: false, speaker: 0)
        return s.lines
    }

    private func pos(_ lines: [CaptionLine], _ i: Int, _ offset: Int) -> CaptionPosition {
        CaptionPosition(lineID: lines[i].id, offset: offset)
    }

    // MARK: word selection (the press-and-hold)

    func testHoldOnAWordSelectsThatWordWithoutTrailingPunctuation() {
        let lines = transcript()
        let sel = CaptionSelection.word(at: 13, in: lines[0])   // inside "Luigi's"
        XCTAssertEqual(sel?.copyText(lines: lines), "Luigi's")
        let comma = CaptionSelection.word(at: 2, in: lines[1])  // inside "Around"
        XCTAssertEqual(comma?.copyText(lines: lines), "Around")
        let seven = CaptionSelection.word(at: 9, in: lines[1])  // inside "seven," -> no comma
        XCTAssertEqual(seven?.copyText(lines: lines), "seven")
    }

    func testHoldOnTheSpaceBetweenWordsPicksTheWordBefore() {
        let lines = transcript()
        let sel = CaptionSelection.word(at: 4, in: lines[0])    // the space after "Meet"
        XCTAssertEqual(sel?.copyText(lines: lines), "Meet")
    }

    func testHoldOutsideTheTextIsClampedToTheNearestWordRatherThanCrashing() {
        let lines = transcript()
        XCTAssertEqual(CaptionSelection.word(at: -3, in: lines[0])?.copyText(lines: lines), "Meet")
        XCTAssertEqual(CaptionSelection.word(at: 500, in: lines[0])?.copyText(lines: lines), "Fifth")
    }

    func testHoldOnALineWithNoWordsSelectsNothing() {
        var s = CaptionStream()
        s.apply(text: "   ", isFinal: true, speaker: 0)
        s.apply(text: "...", isFinal: true, speaker: 0)
        for line in s.lines { XCTAssertNil(CaptionSelection.word(at: 0, in: line)) }
    }

    // MARK: ranges per line

    func testASelectionAcrossLinesCoversTheTailOfTheFirstLineAllMiddleLinesAndTheHeadOfTheLast() {
        let lines = transcript()
        let sel = CaptionSelection(anchor: pos(lines, 0, 11), focus: pos(lines, 1, 6))
        let r = sel.resolved(in: lines)
        XCTAssertEqual(r?.range(forLineAt: 0, length: lines[0].text.utf16.count), 11..<27)
        XCTAssertEqual(r?.range(forLineAt: 1, length: lines[1].text.utf16.count), 0..<6)
        XCTAssertNil(r?.range(forLineAt: 2, length: lines[2].text.utf16.count))
    }

    func testDraggingTheFocusAboveTheAnchorStillSelectsTheSameTextInReadingOrder() {
        let lines = transcript()
        let forward = CaptionSelection(anchor: pos(lines, 0, 11), focus: pos(lines, 1, 6))
        let backward = CaptionSelection(anchor: pos(lines, 1, 6), focus: pos(lines, 0, 11))
        XCTAssertEqual(forward.copyText(lines: lines), backward.copyText(lines: lines))
    }

    func testOffsetsBeyondALineThatShrankAreClampedNotTrusted() {
        let lines = transcript()
        let sel = CaptionSelection(anchor: pos(lines, 3, 0), focus: pos(lines, 3, 999))
        XCTAssertEqual(sel.copyText(lines: lines), "I'll call them")
    }

    func testASelectionWhoseLineIsGoneResolvesToNothing() {
        let lines = transcript()
        let sel = CaptionSelection(anchor: CaptionPosition(lineID: 9_999, offset: 0), focus: pos(lines, 1, 3))
        XCTAssertNil(sel.resolved(in: lines))
        XCTAssertEqual(sel.copyText(lines: lines), "")
        XCTAssertNil(sel.resolved(in: []))
    }

    func testAnEmptySelectionIsEmpty() {
        let lines = transcript()
        XCTAssertTrue(CaptionSelection(anchor: pos(lines, 1, 4), focus: pos(lines, 1, 4)).isEmpty(in: lines))
        XCTAssertFalse(CaptionSelection(anchor: pos(lines, 1, 4), focus: pos(lines, 1, 5)).isEmpty(in: lines))
    }

    // MARK: the copied text

    func testOneLineCopiesJustTheSelectedWords() {
        let lines = transcript()
        let sel = CaptionSelection(anchor: pos(lines, 0, 11), focus: pos(lines, 0, 27))
        XCTAssertEqual(sel.copyText(lines: lines), "Luigi's on Fifth")
    }

    func testSeveralLinesCopyOneLinePerCaptionWithSpeakerNamesLikeTheTranscriptExport() {
        let lines = transcript()
        var names = SpeakerNames()
        names.apply("Dana", to: 1)
        let sel = CaptionSelection(anchor: pos(lines, 0, 11), focus: pos(lines, 3, 4))
        XCTAssertEqual(sel.copyText(lines: lines, speakerNames: names), """
        Speaker 1: Luigi's on Fifth
        Dana: Around seven, okay?
        [Laughter]
        Speaker 1: I'll
        """)
    }

    func testNamesOnEveryCopyWhenAskedTo() {
        let lines = transcript()
        let sel = CaptionSelection(anchor: pos(lines, 0, 11), focus: pos(lines, 0, 27))
        XCTAssertEqual(sel.copyText(lines: lines, naming: .always), "Speaker 1: Luigi's on Fifth")
    }

    func testCopyNeverSplitsAnEmojiOrAccentedLetterInHalf() {
        var s = CaptionStream()
        s.apply(text: "Café 🎂 time", isFinal: true, speaker: 0)
        let lines = s.lines
        // UTF-16: "Café " is 5, the cake is 2 units (5..<7). A focus inside the surrogate pair must not cut it.
        let sel = CaptionSelection(anchor: CaptionPosition(lineID: lines[0].id, offset: 0), focus: CaptionPosition(lineID: lines[0].id, offset: 6))
        let copied = sel.copyText(lines: lines)
        XCTAssertTrue(copied == "Café 🎂" || copied == "Café ", "never half a cake: \(copied.debugDescription)")
    }

    // MARK: the Copy button's timing

    func testTheCopyButtonAppearsHalfASecondAfterTheSelectionStopsChanging() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var timing = CopyButtonTiming()
        timing.selectionChanged(at: t0, isEmpty: false)
        XCTAssertFalse(timing.update(now: t0.addingTimeInterval(0.3)))
        timing.selectionChanged(at: t0.addingTimeInterval(0.3), isEmpty: false)   // still dragging
        XCTAssertFalse(timing.update(now: t0.addingTimeInterval(0.7)))           // 0.4 s since the last change
        XCTAssertTrue(timing.update(now: t0.addingTimeInterval(0.8)))            // 0.5 s since the last change
    }

    func testOnceShownTheButtonFollowsTheSelectionWhileItIsResized() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var timing = CopyButtonTiming()
        timing.selectionChanged(at: t0, isEmpty: false)
        XCTAssertTrue(timing.update(now: t0.addingTimeInterval(0.5)))
        timing.selectionChanged(at: t0.addingTimeInterval(1), isEmpty: false)
        XCTAssertTrue(timing.update(now: t0.addingTimeInterval(1.01)), "resizing must not make it blink away")
    }

    func testClearingTheSelectionHidesTheButtonAndTheNextSelectionWaitsAgain() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var timing = CopyButtonTiming()
        timing.selectionChanged(at: t0, isEmpty: false)
        XCTAssertTrue(timing.update(now: t0.addingTimeInterval(0.6)))
        timing.selectionChanged(at: t0.addingTimeInterval(1), isEmpty: true)
        XCTAssertFalse(timing.update(now: t0.addingTimeInterval(5)))
        timing.selectionChanged(at: t0.addingTimeInterval(6), isEmpty: false)
        XCTAssertFalse(timing.update(now: t0.addingTimeInterval(6.2)))
        XCTAssertTrue(timing.update(now: t0.addingTimeInterval(6.5)))
    }

    func testAClockThatJumpsBackwardsNeverShowsTheButtonEarly() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var timing = CopyButtonTiming()
        timing.selectionChanged(at: t0, isEmpty: false)
        XCTAssertFalse(timing.update(now: t0.addingTimeInterval(-10)))
    }

    // MARK: cost on a long conversation (ADR 0015: the caption screen must never lag behind speech)

    func testSelectingInAnHourLongConversationStaysCheap() {
        var s = CaptionStream()
        for i in 0..<3_000 {   // about an hour of conversation at a line every 1.2 s
            s.apply(text: "This is caption line number \(i) of a long dinner conversation", isFinal: true, speaker: i % 2)
        }
        let lines = s.lines
        let sel = CaptionSelection(anchor: CaptionPosition(lineID: lines[100].id, offset: 3),
                                   focus: CaptionPosition(lineID: lines[2_900].id, offset: 10))
        let start = Date()
        for _ in 0..<20 {   // what one screen update does, twenty times over
            guard let r = sel.resolved(in: lines) else { return XCTFail("must resolve") }
            let index = Dictionary(uniqueKeysWithValues: lines.enumerated().map { ($1.id, $0) })
            for line in lines.suffix(20) { _ = r.range(forLineAt: index[line.id]!, length: line.text.utf16.count) }
        }
        let perUpdate = Date().timeIntervalSince(start) / 20
        XCTAssertLessThan(perUpdate, 0.008, "one update must fit well inside a 120 Hz frame; took \(perUpdate * 1000) ms")
        print("selection resolve per update, 3,000 lines: \(String(format: "%.3f", perUpdate * 1000)) ms")
        XCTAssertEqual(sel.copyText(lines: lines).split(separator: "\n").count, 2_801)
    }

    // MARK: auto-scroll while selecting

    func testNewCaptionsDoNotScrollTheScreenWhileSomethingIsSelected() {
        XCTAssertTrue(AutoScroll.followsNewCaptions(following: true, selecting: false))
        XCTAssertFalse(AutoScroll.followsNewCaptions(following: true, selecting: true))
        XCTAssertFalse(AutoScroll.followsNewCaptions(following: false, selecting: false))
    }
}

/// The selection must read in every theme: handles visible, selected words still at the themes' 7:1.
final class SelectionColorsTests: XCTestCase {
    func testHandlesStandOutFromEveryTheme() {
        for preset in CaptionPreset.all {
            XCTAssertGreaterThanOrEqual(RGBA.contrast(SelectionColors.handle(on: preset.background), preset.background), 3, preset.id)
        }
    }

    func testSelectedTextKeepsAAAContrastOnTheHighlightInEveryTheme() {
        for preset in CaptionPreset.all {
            let highlight = SelectionColors.highlight(on: preset.background)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(preset.text, highlight), 7, preset.id)
            XCTAssertGreaterThan(RGBA.contrast(highlight, preset.background), 1.3, "the highlight must still be visible on \(preset.id)")
        }
    }
}

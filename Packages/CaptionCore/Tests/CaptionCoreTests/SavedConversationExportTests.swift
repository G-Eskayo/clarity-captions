import XCTest
@testable import CaptionCore

/// #139: [ Share ] on a saved conversation hands out its text and a .txt named for the day it started.
final class SavedConversationExportTests: XCTestCase {
    private let denver = TimeZone(identifier: "America/Denver")!

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func conversation(startedAt: Date, transcript: String = "Speaker 1: Hi") -> SavedConversation {
        SavedConversation(startedAt: startedAt, savedAt: startedAt.addingTimeInterval(5400), transcript: transcript)
    }

    func testFileNameIsTheStartTimeInTheDevicesZone() {
        let c = conversation(startedAt: date(2026, 10, 18, 9, 2, in: denver))
        XCTAssertEqual(SavedConversationExport.fileName(for: c, timeZone: denver), "Seal Speak 2026-10-18 09.02.txt")
    }

    func testFileNameUsesStartNotSave() {
        // A 90-minute coffee that started before midnight is named for the evening it started.
        let c = conversation(startedAt: date(2026, 10, 18, 23, 30, in: denver))
        XCTAssertEqual(SavedConversationExport.fileName(for: c, timeZone: denver), "Seal Speak 2026-10-18 23.30.txt")
    }

    func testFileNameIsTwentyFourHourAndPaddedWhateverTheLocale() {
        let c = conversation(startedAt: date(2026, 1, 5, 7, 4, in: denver))
        XCTAssertEqual(SavedConversationExport.fileName(for: c, timeZone: denver), "Seal Speak 2026-01-05 07.04.txt")
    }

    func testFileNameNeverHoldsSlashOrColon() {
        let c = conversation(startedAt: date(2026, 12, 31, 12, 59, in: denver), transcript: "a/b: c\\d")
        let name = SavedConversationExport.fileName(for: c, timeZone: denver)
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains("\\"))
        XCTAssertTrue(name.hasSuffix(".txt"))
    }

    func testTextIsTheTranscriptAsSaved() {
        let transcript = "Speaker 1: Morning, how was the drive?\nSpeaker 2: Not bad, traffic on 36."
        let c = conversation(startedAt: Date(), transcript: transcript)
        XCTAssertEqual(SavedConversationExport.text(for: c), transcript + "\n")
    }

    func testTextKeepsUnicodeAndInnerBlankLines() {
        let transcript = "Speaker 1: ¿Qué tal?\n\nSpeaker 2: שלום 👋"
        let c = conversation(startedAt: Date(), transcript: transcript)
        XCTAssertEqual(SavedConversationExport.text(for: c), transcript + "\n")
    }

    func testTextTrimsOuterWhitespaceToOneFinalNewline() {
        let c = conversation(startedAt: Date(), transcript: "\n\n  Speaker 1: Hi  \n\n\n")
        XCTAssertEqual(SavedConversationExport.text(for: c), "Speaker 1: Hi\n")
    }

    func testEmptyTranscriptHasNothingToShare() {
        XCTAssertFalse(SavedConversationExport.canShare(conversation(startedAt: Date(), transcript: "")))
        XCTAssertFalse(SavedConversationExport.canShare(conversation(startedAt: Date(), transcript: " \n\t ")))
        XCTAssertTrue(SavedConversationExport.canShare(conversation(startedAt: Date(), transcript: "Hi")))
    }

    func testFileBytesAreUTF8OfTheText() {
        let c = conversation(startedAt: Date(), transcript: "Speaker 1: שלום")
        XCTAssertEqual(String(data: SavedConversationExport.data(for: c), encoding: .utf8), "Speaker 1: שלום\n")
    }
}

/// #139: a saved conversation is selected and copied with the same gestures as live captions, so its text becomes lines.
final class SavedTranscriptLinesTests: XCTestCase {
    private let transcript = "Speaker 1: Morning, how was the drive?\nSpeaker 2: Not bad, traffic on 36."

    func testOneLinePerTranscriptLineWithTheTextAsSaved() {
        let lines = SavedConversationExport.lines(from: transcript)
        XCTAssertEqual(lines.map(\.text), ["Speaker 1: Morning, how was the drive?", "Speaker 2: Not bad, traffic on 36."])
        XCTAssertEqual(Set(lines.map(\.id)).count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.isFinal && $0.speaker == nil && !$0.isSoundLabel })
    }

    func testBlankLinesAreSkipped() {
        XCTAssertEqual(SavedConversationExport.lines(from: "\nA\n\n  \nB\n").map(\.text), ["A", "B"])
        XCTAssertEqual(SavedConversationExport.lines(from: "").count, 0)
    }

    func testCopyingAcrossLinesKeepsEachSpeakerOnce() {
        let lines = SavedConversationExport.lines(from: transcript)
        let all = CaptionSelection(anchor: CaptionPosition(lineID: lines[0].id, offset: 0),
                                   focus: CaptionPosition(lineID: lines[1].id, offset: lines[1].text.utf16.count))
        XCTAssertEqual(all.copyText(lines: lines), transcript)
    }

    func testCopyingAWordGivesJustTheWord() {
        let lines = SavedConversationExport.lines(from: transcript)
        let offset = (lines[1].text as NSString).range(of: "traffic").location
        let word = CaptionSelection.word(at: offset + 2, in: lines[1])
        XCTAssertEqual(word?.copyText(lines: lines), "traffic")
    }

    func testEmojiAndHebrewSurviveTheRoundTrip() {
        let text = "Speaker 1: שלום 👋🏽 friend"
        let lines = SavedConversationExport.lines(from: text)
        let all = CaptionSelection(anchor: CaptionPosition(lineID: lines[0].id, offset: 0),
                                   focus: CaptionPosition(lineID: lines[0].id, offset: lines[0].text.utf16.count))
        XCTAssertEqual(all.copyText(lines: lines), text)
    }
}

/// #139: [ Copy ] sits above the selection like on the live screen; on a saved page's first line there's no room
/// above, so it goes just under the selection's last line instead of being cut off over the selected words.
final class SavedCopyPlacementTests: XCTestCase {
    func testAboveWhenThereIsRoom() {
        XCTAssertEqual(SavedConversationExport.copyButtonCenterY(selectionTop: 200, selectionBottom: 260), 154)
    }

    func testBelowTheLastLineWhenTheTopHasNoRoom() {
        XCTAssertEqual(SavedConversationExport.copyButtonCenterY(selectionTop: 10, selectionBottom: 120), 166)
    }

    func testExactlyEnoughRoomStaysAbove() {
        XCTAssertEqual(SavedConversationExport.copyButtonCenterY(selectionTop: 72, selectionBottom: 100), 26)
    }

    func testNeverOverlapsTheSelectionEitherWay() {
        for top in stride(from: CGFloat(0), through: 300, by: 7) {
            let bottom = top + 40
            let y = SavedConversationExport.copyButtonCenterY(selectionTop: top, selectionBottom: bottom)
            let half = SavedConversationExport.copyButtonHalfHeight
            XCTAssertTrue(y + half <= top || y - half >= bottom, "top \(top): \(y)")
            XCTAssertGreaterThanOrEqual(y - half, 0, "cut off at top \(top)")
        }
    }
}

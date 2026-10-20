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

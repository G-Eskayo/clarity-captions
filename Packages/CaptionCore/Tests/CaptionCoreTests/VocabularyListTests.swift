import XCTest
@testable import CaptionCore

final class VocabularyListTests: XCTestCase {
    func testEmptyInputYieldsEmptyEntries() {
        let list = VocabularyList(rawText: "")
        XCTAssertEqual(list.entries, [])
    }

    func testBlankLinesAreSkipped() {
        let list = VocabularyList(rawText: "Alice\n\nBob")
        XCTAssertEqual(list.entries, ["Alice", "Bob"])
    }

    func testWhitespaceIsTrimmed() {
        let list = VocabularyList(rawText: "  Alice  \n  Bob  ")
        XCTAssertEqual(list.entries, ["Alice", "Bob"])
    }

    func testCaseInsensitiveDuplicatesAreCollapsed() {
        let list = VocabularyList(rawText: "Alice\nalice\nBob\nBOB")
        XCTAssertEqual(list.entries, ["Alice", "Bob"])
    }

    func testFirstOccurrenceCasingIsPreserved() {
        let list = VocabularyList(rawText: "alice\nAlice\nalice")
        XCTAssertEqual(list.entries, ["alice"])
    }

    func testEntriesOverMaxLengthAreDropped() {
        let list = VocabularyList(rawText: "Alice\nThisIsAVeryLongNameThatExceedsTheMaximumLength\nBob")
        XCTAssertEqual(list.entries, ["Alice", "Bob"])
    }

    func testEntriesAtMaxLengthAreKept() {
        let entry = String(repeating: "a", count: 40)
        let list = VocabularyList(rawText: entry)
        XCTAssertEqual(list.entries, [entry])
    }

    func testEntriesBeyondMaxAreDroppedKeepingEarliest() {
        var text = ""
        for i in 0..<250 {
            text += "Entry\(i)\n"
        }
        let list = VocabularyList(rawText: text)
        XCTAssertEqual(list.entries.count, 200)
        XCTAssertEqual(list.entries.first, "Entry0")
        XCTAssertEqual(list.entries.last, "Entry199")
    }

    func testStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "vocabulary-test-\(UUID())")!
        let store = VocabularyStore(defaults: defaults)
        let rawText = "Alice\nBob\nCharlie"
        store.save(rawText: rawText)
        XCTAssertEqual(store.loadRawText(), rawText)
    }

    func testEmptySaveYieldsEmptyLoad() {
        let defaults = UserDefaults(suiteName: "vocabulary-test-\(UUID())")!
        let store = VocabularyStore(defaults: defaults)
        XCTAssertEqual(store.loadRawText(), "")
    }

    func testStorePreservesExactText() {
        let defaults = UserDefaults(suiteName: "vocabulary-test-\(UUID())")!
        let store = VocabularyStore(defaults: defaults)
        let rawText = "  Alice  \nalice\n\nBob"
        store.save(rawText: rawText)
        XCTAssertEqual(store.loadRawText(), rawText)
    }
}

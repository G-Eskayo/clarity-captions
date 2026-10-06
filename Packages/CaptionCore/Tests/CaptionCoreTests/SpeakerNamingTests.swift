import XCTest
@testable import CaptionCore

final class SpeakerNamingTests: XCTestCase {
    func testApplyTrimsWhitespace() {
        var names = SpeakerNames()
        names.apply("  Alice  ", to: 0)
        XCTAssertEqual(names.name(for: 0), "Alice")
    }

    func testApplyTrimsNewlines() {
        var names = SpeakerNames()
        names.apply("\nBob\n", to: 1)
        XCTAssertEqual(names.name(for: 1), "Bob")
    }

    func testApplyTruncatesOverLength() {
        var names = SpeakerNames()
        let longName = String(repeating: "x", count: SpeakerNaming.maxLength + 10)
        names.apply(longName, to: 0)
        XCTAssertEqual(names.name(for: 0)?.count, SpeakerNaming.maxLength)
    }

    func testApplyDoesNotSplitGraphemes() {
        var names = SpeakerNames()
        let emoji = "👨‍👩‍👧‍👦" + String(repeating: "x", count: 35)
        names.apply(emoji, to: 0)
        let result = names.name(for: 0)!
        XCTAssertEqual(result.count, SpeakerNaming.maxLength)
        // Grapheme should be unbroken (count by Character, not scalars)
        XCTAssertFalse(result.allSatisfy { $0.isASCII }, "emoji should be preserved")
    }

    func testApplyWhitespaceOnlyStringClears() {
        var names = SpeakerNames()
        names.apply("Alice", to: 0)
        XCTAssertEqual(names.name(for: 0), "Alice")

        names.apply("   \n  ", to: 0)
        XCTAssertNil(names.name(for: 0))
    }

    func testClearRemovesName() {
        var names = SpeakerNames()
        names.apply("Charlie", to: 0)
        XCTAssertEqual(names.name(for: 0), "Charlie")

        names.clear(speaker: 0)
        XCTAssertNil(names.name(for: 0))
    }

    func testUnrelatedSpeakersUnaffected() {
        var names = SpeakerNames()
        names.apply("Alice", to: 0)
        names.apply("Bob", to: 1)
        names.apply("Charlie", to: 2)

        names.clear(speaker: 1)

        XCTAssertEqual(names.name(for: 0), "Alice")
        XCTAssertNil(names.name(for: 1))
        XCTAssertEqual(names.name(for: 2), "Charlie")
    }

    func testRoundTripApplyAndName() {
        var names = SpeakerNames()
        names.apply("Diana", to: 5)
        XCTAssertEqual(names.name(for: 5), "Diana")
    }

    func testMaxLengthBoundary() {
        var names = SpeakerNames()
        let exactMax = String(repeating: "a", count: SpeakerNaming.maxLength)
        names.apply(exactMax, to: 0)
        XCTAssertEqual(names.name(for: 0), exactMax)
    }

    func testMultipleSpeakersIndependent() {
        var names = SpeakerNames()
        for i in 0..<5 {
            names.apply("Speaker\(i)", to: i)
        }
        for i in 0..<5 {
            XCTAssertEqual(names.name(for: i), "Speaker\(i)")
        }
    }
}

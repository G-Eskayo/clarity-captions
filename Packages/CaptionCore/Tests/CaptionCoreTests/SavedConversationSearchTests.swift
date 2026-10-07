import XCTest
@testable import CaptionCore

final class SavedConversationSearchTests: XCTestCase {
    func testEmptyQueryReturnsAllConversations() {
        let conversations = [
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "First"),
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "Second")
        ]
        let result = SavedConversationSearch.filter(conversations, query: "")
        XCTAssertEqual(result.count, 2)
    }

    func testWhitespaceOnlyQueryReturnsAllConversations() {
        let conversations = [
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "First"),
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "Second")
        ]
        let result = SavedConversationSearch.filter(conversations, query: "   \n  ")
        XCTAssertEqual(result.count, 2)
    }

    func testCaseInsensitiveMatch() {
        let conversations = [
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "Hello world"),
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "Goodbye world")
        ]
        let result = SavedConversationSearch.filter(conversations, query: "HELLO")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].transcript, "Hello world")
    }

    func testSubstringMatch() {
        let conversations = [
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "The quick brown fox"),
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "The lazy dog")
        ]
        let result = SavedConversationSearch.filter(conversations, query: "quick")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].transcript, "The quick brown fox")
    }

    func testNoMatchReturnsEmpty() {
        let conversations = [
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "First"),
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "Second")
        ]
        let result = SavedConversationSearch.filter(conversations, query: "third")
        XCTAssertTrue(result.isEmpty)
    }

    func testMatchesSpeakerNameEmbeddedInText() {
        let conversations = [
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "Alice: Hello\nBob: Hi there"),
            SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "Charlie: What's up")
        ]
        let result = SavedConversationSearch.filter(conversations, query: "alice")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].transcript, "Alice: Hello\nBob: Hi there")
    }
}

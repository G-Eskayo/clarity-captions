import XCTest
@testable import CaptionCore
import Foundation

final class SavedConversationTests: XCTestCase {
    // MARK: - Builder Tests

    func testBuilderEmptyLines() {
        let lines: [CaptionLine] = []
        let names = SpeakerNames()
        let result = SavedConversationBuilder.build(lines: lines, speakerNames: names, endedAt: Date())
        XCTAssertNil(result)
    }

    func testBuilderBlankOnlyText() {
        var s = CaptionStream()
        s.apply(text: "   ", isFinal: true)
        let names = SpeakerNames()
        let result = SavedConversationBuilder.build(lines: s.lines, speakerNames: names, endedAt: Date())
        XCTAssertNil(result)
    }

    func testBuilderNormalSession() {
        var s = CaptionStream()
        s.apply(text: "hello", isFinal: true, speaker: 0)
        s.apply(text: "world", isFinal: true, speaker: 1)
        var names = SpeakerNames()
        names.apply("Alice", to: 0)
        names.apply("Bob", to: 1)

        let endDate = Date()
        let result = SavedConversationBuilder.build(lines: s.lines, speakerNames: names, endedAt: endDate)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.date, endDate)
        XCTAssertEqual(result?.text, "Alice: hello\nBob: world")
    }

    func testBuilderWithUnnamedSpeakers() {
        var s = CaptionStream()
        s.apply(text: "hi", isFinal: true, speaker: 0)
        s.apply(text: "hey", isFinal: true, speaker: 1)
        let names = SpeakerNames()

        let result = SavedConversationBuilder.build(lines: s.lines, speakerNames: names, endedAt: Date())

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "Speaker 1: hi\nSpeaker 2: hey")
    }

    func testBuilderIncludesSoundLabels() {
        var s = CaptionStream()
        s.apply(text: "funny", isFinal: true, speaker: 0)
        s.insertSoundLabel(.laughter)
        s.apply(text: "yes", isFinal: true, speaker: 0)
        let names = SpeakerNames()

        let result = SavedConversationBuilder.build(lines: s.lines, speakerNames: names, endedAt: Date())

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "Speaker 1: funny\n[Laughter]\nSpeaker 1: yes")
    }

    // MARK: - Retention Tests

    func testRetentionActiveConversations() {
        let now = Date()
        let recent = SavedConversation(date: now.addingTimeInterval(-1000), text: "recent")
        let old = SavedConversation(date: now.addingTimeInterval(-30 * 24 * 60 * 60 - 1000), text: "old")

        let conversations = [recent, old]
        let active = SavedConversationRetention.active(conversations, now: now)

        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].id, recent.id)
    }

    func testRetentionBoundaryExactly30Days() {
        let now = Date()
        let exact30Days = SavedConversation(date: now.addingTimeInterval(-30 * 24 * 60 * 60), text: "exact")
        let just30DaysAgo = SavedConversation(date: now.addingTimeInterval(-30 * 24 * 60 * 60 + 1), text: "just30")

        let conversations = [exact30Days, just30DaysAgo]
        let active = SavedConversationRetention.active(conversations, now: now)

        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].id, just30DaysAgo.id)
    }

    func testRetentionJustOver30Days() {
        let now = Date()
        let over30Days = SavedConversation(date: now.addingTimeInterval(-30 * 24 * 60 * 60 - 1), text: "over")

        let conversations = [over30Days]
        let active = SavedConversationRetention.active(conversations, now: now)

        XCTAssertEqual(active.count, 0)
    }

    func testRetentionEmptyList() {
        let active = SavedConversationRetention.active([], now: Date())
        XCTAssertEqual(active.count, 0)
    }

    // MARK: - Search Tests

    func testSearchCaseInsensitive() {
        let c1 = SavedConversation(text: "Hello World")
        let c2 = SavedConversation(text: "goodbye world")
        let conversations = [c1, c2]

        let result = SavedConversationSearch.matching(conversations, query: "HELLO")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, c1.id)
    }

    func testSearchPartialWord() {
        let c1 = SavedConversation(text: "Speaker 1: interesting conversation")
        let c2 = SavedConversation(text: "Speaker 2: something else")
        let conversations = [c1, c2]

        let result = SavedConversationSearch.matching(conversations, query: "interest")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, c1.id)
    }

    func testSearchNoMatch() {
        let c1 = SavedConversation(text: "hello world")
        let c2 = SavedConversation(text: "goodbye")
        let conversations = [c1, c2]

        let result = SavedConversationSearch.matching(conversations, query: "xyz")

        XCTAssertEqual(result.count, 0)
    }

    func testSearchEmptyQueryReturnsAll() {
        let c1 = SavedConversation(text: "hello")
        let c2 = SavedConversation(text: "world")
        let conversations = [c1, c2]

        let result = SavedConversationSearch.matching(conversations, query: "")

        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Store Tests

    func testStoreSaveAndLoad() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SavedConversationStore(directory: tmpDir)

        let conversation = SavedConversation(text: "test conversation")
        try store.save(conversation)

        let all = store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, conversation.id)
        XCTAssertEqual(all[0].text, "test conversation")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testStoreMultipleSavesSortedNewestFirst() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SavedConversationStore(directory: tmpDir)

        let now = Date()
        let c1 = SavedConversation(date: now.addingTimeInterval(-100), text: "first")
        let c2 = SavedConversation(date: now.addingTimeInterval(-50), text: "second")
        let c3 = SavedConversation(date: now, text: "third")

        try store.save(c1)
        try store.save(c2)
        try store.save(c3)

        let all = store.all()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].id, c3.id)
        XCTAssertEqual(all[1].id, c2.id)
        XCTAssertEqual(all[2].id, c1.id)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testStoreDeleteOne() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SavedConversationStore(directory: tmpDir)

        let c1 = SavedConversation(text: "keep")
        let c2 = SavedConversation(text: "delete")

        try store.save(c1)
        try store.save(c2)
        XCTAssertEqual(store.all().count, 2)

        try store.delete(id: c2.id)

        let all = store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, c1.id)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testStoreDeleteAll() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SavedConversationStore(directory: tmpDir)

        let c1 = SavedConversation(text: "one")
        let c2 = SavedConversation(text: "two")

        try store.save(c1)
        try store.save(c2)
        XCTAssertEqual(store.all().count, 2)

        try store.deleteAll()

        let all = store.all()
        XCTAssertEqual(all.count, 0)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testStoreRelaunchSimulation() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let c = SavedConversation(text: "persisted")
        do {
            let store1 = SavedConversationStore(directory: tmpDir)
            try store1.save(c)
        }

        do {
            let store2 = SavedConversationStore(directory: tmpDir)
            let all = store2.all()
            XCTAssertEqual(all.count, 1)
            XCTAssertEqual(all[0].id, c.id)
            XCTAssertEqual(all[0].text, "persisted")
        }

        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testStoreBackupExclusionOnDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SavedConversationStore(directory: tmpDir)

        let c = SavedConversation(text: "test")
        try store.save(c)

        let values = try tmpDir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testStoreExpiredEntriesPurgedOnLoad() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SavedConversationStore(directory: tmpDir)

        let now = Date()
        let recent = SavedConversation(date: now.addingTimeInterval(-1000), text: "keep")
        let expired = SavedConversation(date: now.addingTimeInterval(-30 * 24 * 60 * 60 - 1000), text: "delete")

        try store.save(recent)
        try store.save(expired)

        let all = store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, recent.id)

        try? FileManager.default.removeItem(at: tmpDir)
    }
}

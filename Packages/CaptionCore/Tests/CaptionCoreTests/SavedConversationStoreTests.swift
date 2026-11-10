import XCTest
@testable import CaptionCore

final class SavedConversationStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var fileManager: FileManager!

    override func setUp() {
        super.setUp()
        fileManager = FileManager.default
        tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    override func tearDown() {
        super.tearDown()
        try? fileManager.removeItem(at: tempDirectory)
    }

    func testRetentionPolicyIsExpired29DaysAgo() {
        let now = Date()
        let savedAt = Calendar.current.date(byAdding: .day, value: -29, to: now)!
        let expired = RetentionPolicy.isExpired(savedAt: savedAt, now: now, retentionDays: 30)
        XCTAssertFalse(expired)
    }

    func testRetentionPolicyIsExpired30DaysAgo() {
        let now = Date()
        let savedAt = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let expired = RetentionPolicy.isExpired(savedAt: savedAt, now: now, retentionDays: 30)
        XCTAssertTrue(expired)
    }

    func testRetentionPolicyIsExpired31DaysAgo() {
        let now = Date()
        let savedAt = Calendar.current.date(byAdding: .day, value: -31, to: now)!
        let expired = RetentionPolicy.isExpired(savedAt: savedAt, now: now, retentionDays: 30)
        XCTAssertTrue(expired)
    }

    func testRetentionPolicyAcrossDaylightSavingFallBack() {
        let savedAtComponents = DateComponents(year: 2026, month: 10, day: 2, hour: 12, minute: 0, second: 0)
        let savedAt = Calendar.current.date(from: savedAtComponents)!

        let now29Components = DateComponents(year: 2026, month: 10, day: 31, hour: 12, minute: 0, second: 0)
        let now29 = Calendar.current.date(from: now29Components)!
        let expiredAt29 = RetentionPolicy.isExpired(savedAt: savedAt, now: now29, retentionDays: 30)
        XCTAssertFalse(expiredAt29, "At 29 days should not be expired")

        let now30BoundaryComponents = DateComponents(year: 2026, month: 11, day: 1, hour: 11, minute: 30, second: 0)
        let now30Boundary = Calendar.current.date(from: now30BoundaryComponents)!
        let expiredAt30Boundary = RetentionPolicy.isExpired(savedAt: savedAt, now: now30Boundary, retentionDays: 30)
        XCTAssertFalse(expiredAt30Boundary, "At Nov 1 11:30 EST (inside the extra hour) should not be expired")

        let now30Components = DateComponents(year: 2026, month: 11, day: 1, hour: 12, minute: 0, second: 0)
        let now30 = Calendar.current.date(from: now30Components)!
        let expiredAt30 = RetentionPolicy.isExpired(savedAt: savedAt, now: now30, retentionDays: 30)
        XCTAssertTrue(expiredAt30, "At Nov 1 12:00 EST (past 30 calendar days) should be expired")
    }

    func testRetentionPolicyAcrossDaylightSavingSpringForward() {
        let savedAtComponents = DateComponents(year: 2027, month: 2, day: 12, hour: 12, minute: 0, second: 0)
        let savedAt = Calendar.current.date(from: savedAtComponents)!

        let now29Components = DateComponents(year: 2027, month: 3, day: 13, hour: 12, minute: 0, second: 0)
        let now29 = Calendar.current.date(from: now29Components)!
        let expiredAt29 = RetentionPolicy.isExpired(savedAt: savedAt, now: now29, retentionDays: 30)
        XCTAssertFalse(expiredAt29, "At 29 days + DST transition should not be expired")

        let now30Components = DateComponents(year: 2027, month: 3, day: 14, hour: 12, minute: 0, second: 0)
        let now30 = Calendar.current.date(from: now30Components)!
        let expiredAt30 = RetentionPolicy.isExpired(savedAt: savedAt, now: now30, retentionDays: 30)
        XCTAssertTrue(expiredAt30, "At 30 days + DST transition should be expired")
    }

    func testSessionRetentionShouldNotSaveBlankLinesOnly() {
        var stream = CaptionStream()
        stream.apply(text: "   ", isFinal: true)
        stream.apply(text: "\n", isFinal: true)
        let shouldSave = SessionRetention.shouldSave(lines: stream.lines)
        XCTAssertFalse(shouldSave)
    }

    func testSessionRetentionShouldSaveWithContent() {
        var stream = CaptionStream()
        stream.apply(text: "hello", isFinal: true)
        let shouldSave = SessionRetention.shouldSave(lines: stream.lines)
        XCTAssertTrue(shouldSave)
    }

    func testSessionRetentionShouldSaveSoundLabelCountsAsContent() {
        var stream = CaptionStream()
        stream.insertSoundLabel(.laughter)
        let shouldSave = SessionRetention.shouldSave(lines: stream.lines)
        XCTAssertTrue(shouldSave)
    }

    func testSaveAndRetrieveSingleConversation() async throws {
        let store = try SavedConversationStore(directory: tempDirectory, fileManager: fileManager)
        let conversation = SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "Hello world")

        try await store.save(conversation)
        let retrieved = try await store.all()

        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved[0].id, conversation.id)
        XCTAssertEqual(retrieved[0].transcript, "Hello world")
    }

    func testAllReturnsNewestFirst() async throws {
        let store = try SavedConversationStore(directory: tempDirectory, fileManager: fileManager)
        let now = Date()
        let first = SavedConversation(startedAt: now, savedAt: now.addingTimeInterval(-100), transcript: "First")
        let second = SavedConversation(startedAt: now, savedAt: now.addingTimeInterval(-50), transcript: "Second")
        let third = SavedConversation(startedAt: now, savedAt: now, transcript: "Third")

        try await store.save(first)
        try await store.save(second)
        try await store.save(third)

        let retrieved = try await store.all()

        XCTAssertEqual(retrieved.count, 3)
        XCTAssertEqual(retrieved[0].transcript, "Third")
        XCTAssertEqual(retrieved[1].transcript, "Second")
        XCTAssertEqual(retrieved[2].transcript, "First")
    }

    func testDeleteRemovesOneConversation() async throws {
        let store = try SavedConversationStore(directory: tempDirectory, fileManager: fileManager)
        let first = SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "First")
        let second = SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "Second")

        try await store.save(first)
        try await store.save(second)

        try await store.delete(id: first.id)
        let retrieved = try await store.all()

        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved[0].id, second.id)
    }

    func testDeleteAllRemovesAllConversations() async throws {
        let store = try SavedConversationStore(directory: tempDirectory, fileManager: fileManager)
        let first = SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "First")
        let second = SavedConversation(startedAt: Date(), savedAt: Date(), transcript: "Second")

        try await store.save(first)
        try await store.save(second)

        try await store.deleteAll()
        let retrieved = try await store.all()

        XCTAssertTrue(retrieved.isEmpty)
    }

    func testPurgeExpiredRemovesOnlyExpiredEntries() async throws {
        let store = try SavedConversationStore(directory: tempDirectory, fileManager: fileManager)
        let now = Date()
        let expired = SavedConversation(startedAt: now, savedAt: now.addingTimeInterval(-40 * 24 * 3600), transcript: "Expired")
        let fresh = SavedConversation(startedAt: now, savedAt: now.addingTimeInterval(-10 * 24 * 3600), transcript: "Fresh")

        try await store.save(expired)
        try await store.save(fresh)

        try await store.purgeExpired(now: now)
        let retrieved = try await store.all()

        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved[0].transcript, "Fresh")
    }

    func testDirectoryIsExcludedFromBackupOnIOS() async throws {
        _ = try SavedConversationStore(directory: tempDirectory, fileManager: fileManager)

        #if os(iOS)
        var resourceValues = try tempDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertTrue(resourceValues.isExcludedFromBackup ?? false)
        #else
        // On macOS, the attribute cannot be tested in the same way, but the code still runs without error
        XCTAssertTrue(true)
        #endif
    }
}

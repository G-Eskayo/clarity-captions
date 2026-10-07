import Foundation

public enum RetentionPolicy {
    public static func isExpired(savedAt: Date, now: Date, retentionDays: Int = 30) -> Bool {
        let expiryDate = Calendar.current.date(byAdding: .day, value: retentionDays, to: savedAt) ?? savedAt
        return now >= expiryDate
    }
}

public enum SessionRetention {
    public static func shouldSave(lines: [CaptionLine]) -> Bool {
        lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

public protocol SavedConversationStoring: Sendable {
    func save(_ conversation: SavedConversation) async throws
    func all() async throws -> [SavedConversation]
    func delete(id: UUID) async throws
    func deleteAll() async throws
    func purgeExpired(now: Date) async throws
}

public final class SavedConversationStore: SavedConversationStoring {
    private let directory: URL

    public init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }

        #if os(iOS)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = directory
        try mutableURL.setResourceValues(resourceValues)
        #endif
    }

    public func save(_ conversation: SavedConversation) async throws {
        let filename = "\(conversation.id.uuidString).json"
        let fileURL = directory.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(conversation)

        try data.write(to: fileURL, options: .atomic)

        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
        #endif
    }

    public func all() async throws -> [SavedConversation] {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let jsonFiles = contents.filter { $0.pathExtension == "json" }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var conversations: [SavedConversation] = []
        for fileURL in jsonFiles {
            let data = try Data(contentsOf: fileURL)
            let conversation = try decoder.decode(SavedConversation.self, from: data)
            conversations.append(conversation)
        }

        return conversations.sorted { $0.savedAt > $1.savedAt }
    }

    public func delete(id: UUID) async throws {
        let filename = "\(id.uuidString).json"
        let fileURL = directory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    public func deleteAll() async throws {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for fileURL in contents {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    public func purgeExpired(now: Date = Date()) async throws {
        let conversations = try await all()
        for conversation in conversations {
            if RetentionPolicy.isExpired(savedAt: conversation.savedAt, now: now) {
                try await delete(id: conversation.id)
            }
        }
    }
}

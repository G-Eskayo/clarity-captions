import Foundation

public final class SavedConversationStore: Sendable {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        if let dir = directory {
            self.directory = dir
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = appSupport.appendingPathComponent("SavedConversations")
        }
        self.fileManager = fileManager
    }

    /// Load all saved conversations, apply retention policy (removing expired entries),
    /// and return sorted newest-first. Sets isExcludedFromBackup on the directory.
    public func all() -> [SavedConversation] {
        ensureDirectoryExists()
        setBackupExclusionOnDirectory()

        let allConversations = loadAll()
        let active = SavedConversationRetention.active(allConversations)

        let activeIDs = Set(active.map { $0.id })
        let expiredURLs = loadAllFileURLs().filter { url in
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            return !activeIDs.contains(id)
        }

        for url in expiredURLs {
            try? fileManager.removeItem(at: url)
        }

        return active.sorted { $0.date > $1.date }
    }

    /// Save a conversation to disk.
    public func save(_ conversation: SavedConversation) throws {
        ensureDirectoryExists()
        setBackupExclusionOnDirectory()

        let url = directory.appendingPathComponent(conversation.id.uuidString).appendingPathExtension("json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(conversation)
        try data.write(to: url, options: .atomic)

        #if os(iOS)
        try setDataProtectionOnFile(at: url)
        #endif
    }

    /// Delete a conversation by ID.
    public func delete(id: UUID) throws {
        let url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        try fileManager.removeItem(at: url)
    }

    /// Delete all conversations.
    public func deleteAll() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
        ensureDirectoryExists()
    }

    private func ensureDirectoryExists() {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func setBackupExclusionOnDirectory() {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = directory
        try? mutableURL.setResourceValues(resourceValues)
    }

    #if os(iOS)
    private func setDataProtectionOnFile(at url: URL) throws {
        let attributes = [FileAttributeKey.protectionKey: FileProtectionType.complete]
        try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
    }
    #endif

    private func loadAll() -> [SavedConversation] {
        let urls = loadAllFileURLs()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let conversation = try? decoder.decode(SavedConversation.self, from: data) else {
                return nil
            }
            return conversation
        }
    }

    private func loadAllFileURLs() -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }
}

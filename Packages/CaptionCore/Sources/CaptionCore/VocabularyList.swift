import Foundation

public struct VocabularyList: Equatable, Sendable {
    private static let maxEntryLength = 40
    private static let maxEntries = 200

    public let entries: [String]

    public init(rawText: String) {
        let lines = rawText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var seen: [String: Void] = [:]
        var result: [String] = []

        for line in lines {
            let lower = line.lowercased()
            guard seen[lower] == nil else { continue }
            guard line.count <= Self.maxEntryLength else { continue }
            guard result.count < Self.maxEntries else { break }

            seen[lower] = ()
            result.append(line)
        }

        self.entries = result
    }
}

/// Saves vocabulary between launches. Stores the raw text so the UI shows exactly what was typed.
public struct VocabularyStore {
    public static let key = "vocabulary.rawText.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadRawText() -> String {
        defaults.string(forKey: Self.key) ?? ""
    }

    public func save(rawText: String) {
        defaults.set(rawText, forKey: Self.key)
    }
}

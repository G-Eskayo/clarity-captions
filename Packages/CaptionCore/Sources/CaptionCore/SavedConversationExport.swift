import Foundation

/// What [ Share ] on a saved conversation hands out (#139): its text, and a .txt named for when it started.
public enum SavedConversationExport {
    public static func canShare(_ conversation: SavedConversation) -> Bool {
        !conversation.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func text(for conversation: SavedConversation) -> String {
        conversation.transcript.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    public static func data(for conversation: SavedConversation) -> Data {
        Data(text(for: conversation).utf8)
    }

    /// "Seal Speak 2026-10-18 09.02.txt": fixed digits whatever the locale, sorts by date in Files, no "/" or ":".
    public static func fileName(for conversation: SavedConversation, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: conversation.startedAt)
        let stamp = String(format: "%04d-%02d-%02d %02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        return "Seal Speak \(stamp).txt"
    }
}

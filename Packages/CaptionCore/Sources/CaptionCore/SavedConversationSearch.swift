import Foundation

public enum SavedConversationSearch {
    public static func filter(_ conversations: [SavedConversation], query: String) -> [SavedConversation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return conversations }
        return conversations.filter { $0.transcript.localizedCaseInsensitiveContains(trimmed) }
    }
}

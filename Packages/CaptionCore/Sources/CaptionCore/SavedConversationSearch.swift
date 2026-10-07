import Foundation

public enum SavedConversationSearch {
    /// Search conversations by case-insensitive substring match.
    /// Empty query returns all conversations.
    public static func matching(_ conversations: [SavedConversation], query: String) -> [SavedConversation] {
        guard !query.isEmpty else { return conversations }
        let lowerQuery = query.lowercased()
        return conversations.filter { $0.text.lowercased().contains(lowerQuery) }
    }
}

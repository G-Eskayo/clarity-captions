import Foundation

public enum SavedConversationRetention {
    public static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    public static func active(_ conversations: [SavedConversation], now: Date = Date()) -> [SavedConversation] {
        conversations.filter { conversation in
            now.timeIntervalSince(conversation.date) < maxAge
        }
    }
}

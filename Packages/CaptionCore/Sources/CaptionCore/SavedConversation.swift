import Foundation

public struct SavedConversation: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String

    public init(id: UUID = UUID(), date: Date = Date(), text: String) {
        self.id = id
        self.date = date
        self.text = text
    }
}

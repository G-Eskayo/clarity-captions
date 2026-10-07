import Foundation

public struct SavedConversation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let savedAt: Date
    public let transcript: String

    public init(id: UUID = UUID(), startedAt: Date, savedAt: Date, transcript: String) {
        self.id = id
        self.startedAt = startedAt
        self.savedAt = savedAt
        self.transcript = transcript
    }

    public static func from(sessionStart: Date, lines: [CaptionLine], speakerNames: SpeakerNames = SpeakerNames()) -> SavedConversation {
        let transcript = TranscriptFormatter.plainText(lines: lines, speakerNames: speakerNames)
        return SavedConversation(startedAt: sessionStart, savedAt: Date(), transcript: transcript)
    }
}

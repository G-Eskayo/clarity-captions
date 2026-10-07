import Foundation

public enum SavedConversationBuilder {
    /// Build a saved conversation from the caption lines, or nil if the transcript is empty.
    /// Returns a SavedConversation with the formatted plain-text transcript and the end time.
    public static func build(lines: [CaptionLine], speakerNames: SpeakerNames, endedAt: Date) -> SavedConversation? {
        let plainText = TranscriptFormatter.plainText(lines: lines, speakerNames: speakerNames)
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SavedConversation(date: endedAt, text: plainText)
    }
}

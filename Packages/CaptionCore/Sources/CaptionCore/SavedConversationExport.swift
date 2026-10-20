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

    /// The saved text as caption lines, so it's selected and copied with the live captions' gestures. Each line
    /// already reads "Speaker 1: …", so it has no speaker of its own and copying never names it twice.
    public static func lines(from transcript: String) -> [CaptionLine] {
        transcript.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .enumerated()
            .map { CaptionLine(id: $0.offset, committed: [CaptionWord(text: $0.element, emphasis: .normal)], tail: nil) }
    }

    /// Half of [ Copy ]'s height, and how far its center sits from the selection (46, as on the live screen).
    public static let copyButtonHalfHeight: CGFloat = 26
    static let copyButtonOffset: CGFloat = 46

    /// Where [ Copy ]'s center goes: above the selection when it fits, else just under the selection's last line.
    public static func copyButtonCenterY(selectionTop: CGFloat, selectionBottom: CGFloat) -> CGFloat {
        let above = selectionTop - copyButtonOffset
        return above - copyButtonHalfHeight >= 0 ? above : selectionBottom + copyButtonOffset
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

/// A saved conversation opens like a paused one (owner, #139): dimmed, with [ Share ] over [ Delete ]. A tap clears the
/// dim to read and copy; a press-and-hold on empty space brings it back. The hint about that shows once, ever.
public struct SavedConversationVeil: Equatable, Sendable {
    public private(set) var isVisible = true

    public init() {}

    /// Clears the dim. True when this is the first clear ever, so the page shows its hint.
    public mutating func tap(hintsShownBefore: Int) -> Bool {
        guard isVisible else { return false }
        isVisible = false
        return hintsShownBefore == 0
    }

    public mutating func holdOnEmptySpace() { isVisible = true }
}

import Foundation

/// Speaking sooner than the finished line (#233): how early the first words of a line stop changing on screen.
public enum PhraseTiming {
    /// The time from which the shown (volatile) text starts with the final line's first `words` words and keeps them
    /// until the line is finished. Nil when the line is shorter, or the words were never right before the final.
    public static func stableAt(updates: [(t: Double, text: String)], final: String, words: Int) -> Double? {
        let target = Array(EchoGuard.words(final).prefix(words))
        guard target.count == words else { return nil }
        var since: Double?
        for u in updates {
            if Array(EchoGuard.words(u.text).prefix(words)) == target { since = since ?? u.t } else { since = nil }
        }
        return since
    }
}

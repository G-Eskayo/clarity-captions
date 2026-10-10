import Foundation

/// Decides whether the caption view should keep following the newest text. Pure, so the rule is tested
/// and every platform scrolls the same way (issue: auto-scroll with "Jump to latest").
public enum AutoScroll {
    /// How far from the bottom still counts as "at the bottom", so a tiny nudge doesn't stop following.
    public static let tolerance: Double = 40

    public static func shouldFollow(offsetY: Double, viewportHeight: Double, contentHeight: Double) -> Bool {
        if contentHeight <= viewportHeight { return true }
        return offsetY + viewportHeight >= contentHeight - tolerance
    }

    /// "Jump to latest" shows only after she scrolls back while captions keep coming, and goes once she's at the
    /// newest line again (mock-up round3/04, approved in #120 as A: retro words).
    public static func showsJumpToLatest(following: Bool) -> Bool { !following }
    /// The word inside the retro brackets: [ ↓ Latest ].
    public static var jumpToLatestWord: String { "↓ " + String(localized: "Latest") }
}

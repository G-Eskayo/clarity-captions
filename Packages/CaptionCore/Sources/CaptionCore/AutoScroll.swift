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
}

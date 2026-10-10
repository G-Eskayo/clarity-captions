import Foundation

/// Plain, friendly guide text for each tour step. No technical terms.
public struct TourCopy: Equatable, Sendable {
    public let title: String
    public let message: String

    public static func `for`(_ step: HowToUseTour.TourStep) -> TourCopy {
        switch step {
        case .start:
            TourCopy(
                title: String(localized: "Here's the big button"),
                message: String(localized: "Tap it to start getting captions right now.")
            )
        case .pause:
            TourCopy(
                title: String(localized: "Stop anytime"),
                message: String(localized: "Tap the X when you want to pause. Nothing is lost — you can Save or keep going.")
            )
        case .save:
            TourCopy(
                title: String(localized: "Save this conversation"),
                message: String(localized: "Tap Save to keep what you just heard. You can replay it anytime.")
            )
        case .new:
            TourCopy(
                title: String(localized: "Start fresh"),
                message: String(localized: "New clears the screen so you can start another conversation.")
            )
        case .copy:
            TourCopy(
                title: String(localized: "Hold to copy words"),
                message: String(localized: "Press and hold on any caption, then tap Copy.")
            )
        case .gear:
            TourCopy(
                title: String(localized: "Settings"),
                message: String(localized: "Change the look, text size, and how long Seal waits before pausing.")
            )
        }
    }
}

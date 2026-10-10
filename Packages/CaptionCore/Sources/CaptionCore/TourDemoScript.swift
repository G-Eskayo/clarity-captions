import Foundation

/// A fixed set of scripted caption lines used to demonstrate the app during the tour.
/// No audio types involved — structurally guarantees "never record or save real audio".
public enum TourDemoScript {
    public static let lines: [CaptionLine] = [
        CaptionLine(
            id: 0,
            speaker: 0,
            soundLabel: nil,
            committed: [CaptionWord(text: "This", emphasis: .normal), CaptionWord(text: "is", emphasis: .normal), CaptionWord(text: "a", emphasis: .normal), CaptionWord(text: "demo.", emphasis: .normal)],
            tail: nil,
            tailRange: nil,
            startTime: nil,
            endTime: nil
        ),
        CaptionLine(
            id: 1,
            speaker: 1,
            soundLabel: nil,
            committed: [CaptionWord(text: "Save", emphasis: .normal), CaptionWord(text: "this", emphasis: .normal), CaptionWord(text: "when", emphasis: .normal), CaptionWord(text: "you're", emphasis: .normal), CaptionWord(text: "done.", emphasis: .normal)],
            tail: nil,
            tailRange: nil,
            startTime: nil,
            endTime: nil
        ),
    ]
}

import SwiftUI
import UIKit

/// Where each caption's words sit on screen, so a press-and-hold can tell empty space from words (#102). A plain
/// reference type: updating it while scrolling never re-renders the captions.
final class TextFrames {
    static let space = "captionViewport"
    private var frames: [String: CGRect] = [:]

    func set(_ key: String, _ frame: CGRect?) { frames[key] = frame }

    /// True when the point is on words, with a little slack so a finger on the edge of a word still counts.
    func contains(_ point: CGPoint) -> Bool {
        frames.values.contains { $0.insetBy(dx: -6, dy: -6).contains(point) }
    }

    /// The caption text (not a speaker label) under the point, with the same slack (#107: a hold there selects).
    func captionLine(at point: CGPoint) -> (id: Int, frame: CGRect)? {
        captionFrames.first { $0.frame.insetBy(dx: -6, dy: -6).contains(point) }
    }

    /// The caption text nearest the point vertically, for dragging a selection handle into the gap between lines.
    func nearestCaptionLine(to point: CGPoint) -> (id: Int, frame: CGRect)? {
        captionFrames.min { distance($0.frame, point) < distance($1.frame, point) }
    }

    /// Where a caption's text sits now, in the caption viewport.
    func captionFrame(_ id: Int) -> CGRect? { frames["text-\(id)"] }

    private var captionFrames: [(id: Int, frame: CGRect)] {
        frames.compactMap { key, frame in
            guard key.hasPrefix("text-"), let id = Int(key.dropFirst(5)) else { return nil }
            return (id, frame)
        }
    }

    private func distance(_ frame: CGRect, _ point: CGPoint) -> CGFloat {
        point.y < frame.minY ? frame.minY - point.y : point.y > frame.maxY ? point.y - frame.maxY : 0
    }
}

extension View {
    /// Records this text's frame in the caption viewport while it's on screen.
    func trackWords(in frames: TextFrames, key: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TextFrames.space)) } action: { frames.set(key, $0) }
            .onDisappear { frames.set(key, nil) }
    }
}

/// A press-and-hold that reports where it began, running alongside the text's own selection gesture rather than
/// replacing it, and never cancelling the scroll view's touches.
struct HoldLocationGesture: UIGestureRecognizerRepresentable {
    var minimumDuration: TimeInterval = 0.5
    let onHold: (CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        guard recognizer.state == .began else { return }
        onHold(context.converter.localLocation)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

import CaptionCore
import SwiftUI
import UIKit

/// Where each caption's characters sit, recorded as SwiftUI draws them (#107). Selection across lines needs character
/// positions SwiftUI's Text doesn't hand out, so a TextRenderer records them while drawing. A plain reference type:
/// recording never re-renders the captions.
final class CaptionGlyphs: @unchecked Sendable {
    struct Glyph {
        let offset: Int     // UTF-16 offset into the line's text
        let rect: CGRect    // in the caption text's own space
        let row: Int        // which visual row of the wrapped text
    }

    private let lock = NSLock()
    private var byLine: [Int: (glyphs: [Glyph], length: Int)] = [:]

    func set(_ lineID: Int, glyphs: [Glyph], length: Int) { lock.withLock { byLine[lineID] = (glyphs, length) } }
    func remove(_ lineID: Int) { _ = lock.withLock { byLine.removeValue(forKey: lineID) } }
    private func entry(_ lineID: Int) -> (glyphs: [Glyph], length: Int)? { lock.withLock { byLine[lineID] } }

    /// The caret offset nearest a point in the text's own space: the row closest vertically, then before a glyph when
    /// left of its middle, after it otherwise.
    func offset(at point: CGPoint, lineID: Int) -> Int? {
        guard let (glyphs, length) = entry(lineID), !glyphs.isEmpty else { return nil }
        let row = glyphs.min { abs($0.rect.midY - point.y) < abs($1.rect.midY - point.y) }!.row
        let inRow = glyphs.filter { $0.row == row }.sorted { $0.rect.minX < $1.rect.minX }
        guard let first = inRow.first, let last = inRow.last else { return nil }
        if point.x <= first.rect.minX { return first.offset }
        if point.x >= last.rect.maxX { return end(after: last, in: glyphs, length: length) }
        let hit = inRow.first { point.x < $0.rect.maxX } ?? last
        return point.x < hit.rect.midX ? hit.offset : end(after: hit, in: glyphs, length: length)
    }

    /// A thin caret at `offset`, in the text's own space: the leading edge of the glyph there, or the trailing edge of
    /// the last glyph before it.
    func caret(at offset: Int, lineID: Int) -> CGRect? {
        guard let (glyphs, _) = entry(lineID), let firstGlyph = glyphs.first else { return nil }
        func leading(_ g: Glyph) -> CGRect { CGRect(x: g.rect.minX, y: g.rect.minY, width: 0, height: g.rect.height) }
        func trailing(_ g: Glyph) -> CGRect { CGRect(x: g.rect.maxX, y: g.rect.minY, width: 0, height: g.rect.height) }
        if offset <= firstGlyph.offset { return leading(firstGlyph) }
        if let exact = glyphs.first(where: { $0.offset == offset }) { return leading(exact) }
        // Past the end, or inside a glyph that spans several UTF-16 units: after the glyph before it.
        return trailing(glyphs.last { $0.offset < offset } ?? firstGlyph)
    }

    private func end(after glyph: Glyph, in glyphs: [Glyph], length: Int) -> Int {
        glyphs.first { $0.offset > glyph.offset }?.offset ?? length
    }
}

/// Draws a caption line exactly as SwiftUI lays it out, with the selected part tinted behind the words, one rounded
/// band per wrapped row as in the copy mock-up (#96, image 05), and records where each character sits.
struct SelectableCaptionRenderer: TextRenderer {
    let lineID: Int
    let length: Int
    let selected: Range<Int>?
    let highlight: Color
    let glyphs: CaptionGlyphs

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var base: Text.Layout.CharacterIndex?
        for line in layout { for run in line { for index in run.characterIndices where base == nil || index < base! { base = index } } }

        var recorded: [CaptionGlyphs.Glyph] = []
        var bands: [CGRect] = []
        for (row, line) in layout.enumerated() {
            var band: CGRect?
            for run in line {
                let indices = run.characterIndices
                for (i, slice) in zip(indices.indices, run) {
                    guard let base else { continue }
                    let offset = base.distance(to: indices[i])
                    let rect = slice.typographicBounds.rect
                    recorded.append(.init(offset: offset, rect: rect, row: row))
                    if let selected, selected.contains(offset) { band = band.map { $0.union(rect) } ?? rect }
                }
            }
            if let band { bands.append(band) }
        }
        glyphs.set(lineID, glyphs: recorded, length: length)

        for band in bands {
            ctx.fill(Path(roundedRect: band.insetBy(dx: -2, dy: -1), cornerRadius: 4), with: .color(highlight))
        }
        for line in layout { ctx.draw(line) }
    }
}

/// A selection handle: a teal bar the height of the text with a round knob, on top for the start and below for the
/// end, as in the copy mock-up. It only draws; dragging is done by SelectionHandleGesture on the captions.
struct SelectionHandle: View {
    enum Edge { case start, end }
    let edge: Edge
    let caret: CGRect      // in the caption viewport
    let color: Color
    static let knob: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            if edge == .start { Circle().fill(color).frame(width: Self.knob, height: Self.knob) }
            Capsule().fill(color).frame(width: 2.5, height: caret.height)
            if edge == .end { Circle().fill(color).frame(width: Self.knob, height: Self.knob) }
        }
        .position(x: caret.minX, y: edge == .start ? caret.midY - Self.knob / 2 : caret.midY + Self.knob / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Dragging a selection handle. It begins only when the finger starts on a handle, so ordinary scrolling is never
/// held up, and the scroll view waits for it to fail before it scrolls.
struct SelectionHandleGesture: UIGestureRecognizerRepresentable {
    let canBegin: (CGPoint) -> Bool
    let onDrag: (CGPoint, Bool) -> Void   // location, finished

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator(converter: converter, canBegin: canBegin) }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.canBegin = canBegin
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: onDrag(context.converter.localLocation, false)
        case .ended, .cancelled, .failed: onDrag(context.converter.localLocation, true)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let converter: CoordinateSpaceConverter
        var canBegin: (CGPoint) -> Bool
        init(converter: CoordinateSpaceConverter, canBegin: @escaping (CGPoint) -> Bool) {
            self.converter = converter
            self.canBegin = canBegin
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Where the finger went down, not where it is now: the pan only begins after it has moved a little.
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let moved = pan.translation(in: pan.view)
            let now = converter.localLocation
            return canBegin(CGPoint(x: now.x - moved.x, y: now.y - moved.y))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other.view is UIScrollView)
        }
    }
}

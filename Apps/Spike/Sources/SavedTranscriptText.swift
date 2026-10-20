import CaptionCore
import SwiftUI
import UIKit

/// A saved conversation's words, selected and copied exactly as live captions are (#107, #139): press and hold a word,
/// drag the handles, and [ Copy ] fades in once the selection rests. It replaces the system's own text selection, whose
/// Copy gave no feedback (beta feedback, 2026-10-20). Everything is in the text's own coordinates, so it scrolls along.
struct SavedTranscriptText: View {
    let transcript: String
    let style: CaptionStyle
    /// Tall enough to fill the page, so a hold below the last line is a hold on empty space.
    var minHeight: CGFloat = 0
    /// While the page's dim is up, a selection can't stay underneath it.
    var dimmed = false
    /// A press-and-hold on empty space (not on words) brings back the dim with [ Share ] / [ Delete ] (owner, #139).
    var onHoldEmptySpace: () -> Void = {}
    @State private var selection: CaptionSelection?
    @State private var copyTiming = CopyButtonTiming()
    @State private var textFrames = TextFrames()
    @State private var glyphs = CaptionGlyphs()
    @State private var dragAnchor: CaptionPosition?
    @State private var draggingEdge: SelectionHandle.Edge?

    private var lines: [CaptionLine] { SavedConversationExport.lines(from: transcript) }

    var body: some View {
        let lines = lines
        let resolved = selection?.resolved(in: lines)
        let highlight = SelectionColors.highlight(on: style.background).color
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                let length = line.text.utf16.count
                Text(line.text)
                    .font(.body)
                    .textRenderer(SelectableCaptionRenderer(lineID: line.id, length: length,
                                                            selected: resolved?.range(forLineAt: index, length: length),
                                                            highlight: highlight, glyphs: glyphs))
                    .trackWords(in: textFrames, key: "text-\(line.id)")
                    .accessibilityAction(named: String(localized: "Copy")) { UIPasteboard.general.string = line.text }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .coordinateSpace(.named(TextFrames.space))
        .overlay { if selection != nil { selectionChrome } }
        .gesture(HoldLocationGesture { location in
            guard let hit = textFrames.captionLine(at: location) else {
                clearSelection()
                onHoldEmptySpace()
                return
            }
            beginSelection(lineID: hit.id, at: CGPoint(x: location.x - hit.frame.minX, y: location.y - hit.frame.minY))
        })
        .gesture(SelectionHandleGesture(canBegin: { point in
            guard let edge = handle(near: point) else { return false }
            draggingEdge = edge
            return true
        }, onDrag: dragHandle))
        .simultaneousGesture(SpatialTapGesture().onEnded { tap in
            if selection != nil, handle(near: tap.location) == nil { clearSelection() }
        })
        .onChange(of: dimmed) { _, dimmed in if dimmed { clearSelection() } }
        .task {
            // Debug only: a held selection for the #139 screenshot (simctl can't press and hold).
            guard DemoMode.select, let first = lines.first, let second = lines.dropFirst().first else { return }
            setSelection(CaptionSelection(anchor: CaptionPosition(lineID: first.id, offset: 11),
                                          focus: CaptionPosition(lineID: second.id, offset: min(14, second.text.utf16.count))))
        }
    }

    private func beginSelection(lineID: Int, at local: CGPoint) {
        guard let line = lines.first(where: { $0.id == lineID }),
              let offset = glyphs.offset(at: local, lineID: lineID),
              let word = CaptionSelection.word(at: offset, in: line) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        setSelection(word)
    }

    private func setSelection(_ new: CaptionSelection) {
        selection = new
        copyTiming.selectionChanged(at: Date(), isEmpty: new.isEmpty(in: lines))
        // Copy shows once the selection has rested for half a second; a later change just moves it.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(CopyButtonTiming.settle + 0.02))
            withAnimation(.easeOut(duration: 0.2)) { _ = copyTiming.update(now: Date()) }
        }
    }

    private func clearSelection() {
        guard selection != nil else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            selection = nil
            copyTiming.selectionChanged(at: Date(), isEmpty: true)
        }
        dragAnchor = nil
    }

    private func copySelection() {
        guard let selection else { return }
        UIPasteboard.general.string = selection.copyText(lines: lines)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        clearSelection()
    }

    /// The two ends of the selection as carets in the text's coordinates.
    private func selectionEnds() -> (start: CGRect, end: CGRect)? {
        let lines = lines
        guard let selection, let r = selection.resolved(in: lines) else { return nil }
        func caret(_ index: Int, _ offset: Int) -> CGRect? {
            let line = lines[index]
            guard let frame = textFrames.captionFrame(line.id),
                  let caret = glyphs.caret(at: min(offset, line.text.utf16.count), lineID: line.id) else { return nil }
            return caret.offsetBy(dx: frame.minX, dy: frame.minY)
        }
        guard let start = caret(r.startLine, r.startOffset), let end = caret(r.endLine, r.endOffset) else { return nil }
        return (start, end)
    }

    /// Which handle a finger at this point is on, with a generous target (44 pt, the minimum for a touch target).
    private func handle(near point: CGPoint) -> SelectionHandle.Edge? {
        guard let ends = selectionEnds() else { return nil }
        func target(_ caret: CGRect, _ edge: SelectionHandle.Edge) -> CGRect {
            let knob = SelectionHandle.knob
            let tall = CGRect(x: caret.minX, y: edge == .start ? caret.minY - knob : caret.minY,
                              width: 0, height: caret.height + knob)
            return tall.insetBy(dx: -22, dy: -12)
        }
        if target(ends.end, .end).contains(point) { return .end }
        if target(ends.start, .start).contains(point) { return .start }
        return nil
    }

    /// Dragging a handle: the other end stays put and this one follows the finger, across lines.
    private func dragHandle(_ location: CGPoint, finished: Bool) {
        let lines = lines
        if finished { dragAnchor = nil; draggingEdge = nil; return }
        guard let selection, let r = selection.resolved(in: lines) else { return }
        if dragAnchor == nil {
            let start = CaptionPosition(lineID: lines[r.startLine].id, offset: r.startOffset)
            let end = CaptionPosition(lineID: lines[r.endLine].id, offset: r.endOffset)
            dragAnchor = draggingEdge == .start ? end : start
        }
        guard let anchor = dragAnchor, let hit = textFrames.nearestCaptionLine(to: location),
              let offset = glyphs.offset(at: CGPoint(x: location.x - hit.frame.minX, y: location.y - hit.frame.minY), lineID: hit.id)
        else { return }
        let moved = CaptionSelection(anchor: anchor, focus: CaptionPosition(lineID: hit.id, offset: offset))
        if moved != selection, !moved.isEmpty(in: lines) { setSelection(moved) }
    }

    /// The handles at both ends and, once the selection has rested, one Copy button above it (mock-up 05).
    private var selectionChrome: some View {
        GeometryReader { geo in
            if let ends = selectionEnds() {
                let handleColor = SelectionColors.handle(on: style.background).color
                SelectionHandle(edge: .start, caret: ends.start, color: handleColor)
                SelectionHandle(edge: .end, caret: ends.end, color: handleColor)
                if copyTiming.isShown {
                    Button(action: copySelection) {
                        Label(String(localized: "Copy"), systemImage: "doc.on.doc")
                            .font(.title3.bold())
                            .padding(.horizontal, 26).padding(.vertical, 12)
                    }
                    .buttonStyle(GummyButtonStyle(style: style))
                    .accessibilityHint(String(localized: "Copies the selected words"))
                    .position(x: geo.size.width / 2,
                              y: SavedConversationExport.copyButtonCenterY(selectionTop: ends.start.minY,
                                                                           selectionBottom: ends.end.maxY))
                    .transition(.opacity)
                }
            }
        }
    }
}

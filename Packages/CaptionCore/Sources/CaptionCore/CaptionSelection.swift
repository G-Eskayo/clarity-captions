import Foundation

/// A place in the transcript: a caption line and a UTF-16 offset into its text. Positions name lines by their stable
/// id, so a selection survives scrolling and new captions arriving underneath it.
public struct CaptionPosition: Equatable, Sendable {
    public var lineID: Int
    public var offset: Int
    public init(lineID: Int, offset: Int) {
        self.lineID = lineID
        self.offset = offset
    }
}

/// What the copied text carries (#107 Decision: speaker names on a one-line copy or not).
public enum CopyNaming: Sendable {
    /// One line copies just the selected words; two or more lines copy one line per caption with speaker names.
    case multiLineOnly
    /// Every copy carries speaker names, like the transcript export.
    case always
}

/// A press-and-hold selection of caption text (#107). The anchor is where it started, the focus is the end being
/// dragged; either can come first in reading order.
public struct CaptionSelection: Equatable, Sendable {
    public var anchor: CaptionPosition
    public var focus: CaptionPosition

    public init(anchor: CaptionPosition, focus: CaptionPosition) {
        self.anchor = anchor
        self.focus = focus
    }

    /// The word under a press-and-hold, as iOS selects it: letters and apostrophes, not the punctuation after it.
    /// On a space it picks the word before; outside the text it picks the nearest word. Nil when the line has no words.
    public static func word(at offset: Int, in line: CaptionLine) -> CaptionSelection? {
        let text = line.text as NSString
        var words: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            words.append(range)
        }
        guard !words.isEmpty else { return nil }
        let at = max(0, min(offset, text.length))
        let word = words.first { at >= $0.location && at < NSMaxRange($0) }
            ?? words.last { $0.location <= at }
            ?? words[0]
        return CaptionSelection(anchor: CaptionPosition(lineID: line.id, offset: word.location),
                                focus: CaptionPosition(lineID: line.id, offset: NSMaxRange(word)))
    }

    /// The selection placed against the current lines: endpoints in reading order. Nil if either line is gone.
    public func resolved(in lines: [CaptionLine]) -> Resolved? {
        guard let a = lines.firstIndex(where: { $0.id == anchor.lineID }),
              let f = lines.firstIndex(where: { $0.id == focus.lineID }) else { return nil }
        let first = (a, anchor.offset), second = (f, focus.offset)
        let (start, end) = (first.0, first.1) <= (second.0, second.1) ? (first, second) : (second, first)
        return Resolved(startLine: start.0, startOffset: start.1, endLine: end.0, endOffset: end.1)
    }

    /// True when nothing would be copied.
    public func isEmpty(in lines: [CaptionLine]) -> Bool { copyText(lines: lines).isEmpty }

    /// The text the Copy button puts on the clipboard.
    public func copyText(lines: [CaptionLine], speakerNames: SpeakerNames = SpeakerNames(), naming: CopyNaming = .multiLineOnly) -> String {
        guard let r = resolved(in: lines) else { return "" }
        let pieces: [(line: CaptionLine, text: String)] = (r.startLine...r.endLine).compactMap { i in
            let line = lines[i]
            guard let range = r.range(forLineAt: i, length: line.text.utf16.count) else { return nil }
            return (line, Self.substring(line.text, utf16: range))
        }.filter { !$0.text.isEmpty }
        let named = naming == .always || pieces.count > 1
        return pieces.map { piece in
            guard named else { return piece.text }
            return TranscriptFormatter.speakerPrefix(for: piece.line, speakerNames: speakerNames) + piece.text
        }.joined(separator: "\n")
    }

    /// A UTF-16 range of `text`, widened so an emoji or accented letter is never cut in half.
    static func substring(_ text: String, utf16 range: Range<Int>) -> String {
        let ns = text as NSString
        guard ns.length > 0, !range.isEmpty else { return "" }
        let r = NSRange(location: range.lowerBound, length: range.count)
        let whole = ns.rangeOfComposedCharacterSequences(for: r)
        return ns.substring(with: whole)
    }

    /// The endpoints in reading order, by line index in the transcript.
    public struct Resolved: Equatable, Sendable {
        public let startLine: Int
        public let startOffset: Int
        public let endLine: Int
        public let endOffset: Int

        /// The selected UTF-16 range of the line at `index`, clamped to its current length, or nil if none of it is selected.
        public func range(forLineAt index: Int, length: Int) -> Range<Int>? {
            guard index >= startLine, index <= endLine else { return nil }
            let lower = index == startLine ? max(0, min(startOffset, length)) : 0
            let upper = index == endLine ? max(0, min(endOffset, length)) : length
            return lower < upper ? lower..<upper : nil
        }
    }
}

/// When the Copy button shows (#107): half a second after the selection stops changing. Once shown it follows the
/// selection while it's resized, and it hides when the selection is cleared.
public struct CopyButtonTiming: Sendable {
    public static let settle: TimeInterval = 0.5
    private var lastChange: Date?
    public private(set) var isShown = false

    public init() {}

    public mutating func selectionChanged(at now: Date, isEmpty: Bool) {
        if isEmpty {
            lastChange = nil
            isShown = false
        } else {
            lastChange = now
        }
    }

    /// Advances the clock; returns whether the button shows.
    @discardableResult
    public mutating func update(now: Date) -> Bool {
        if !isShown, let lastChange, now.timeIntervalSince(lastChange) >= Self.settle { isShown = true }
        return isShown
    }
}

extension AutoScroll {
    /// New captions scroll the screen only while following, and never while something is selected: the selection
    /// would slide away from her finger.
    public static func followsNewCaptions(following: Bool, selecting: Bool) -> Bool { following && !selecting }
}

/// The selection's teal, from the icon's palette as the copy mock-up (#96, image 05) draws it. The handles stand out
/// from every theme (at least 3:1, the bar for controls) and text on the highlight keeps the themes' 7:1.
public enum SelectionColors {
    public static func handle(on background: RGBA) -> RGBA {
        background.isDark ? RGBA(hex: "#6FD3C3") : RGBA(hex: "#1E7F74")
    }

    /// The tint behind selected words, already composited onto the background.
    public static func highlight(on background: RGBA) -> RGBA {
        let tint = background.isDark ? RGBA(hex: "#14665D") : RGBA(hex: "#1E7F74")
        return RGBA(tint.r, tint.g, tint.b, background.isDark ? 0.6 : 0.26).composited(over: background)
    }
}

import Foundation

/// The live translation of the caption stream (#53). Pure bookkeeping: which finished lines still need translating,
/// and which translation each line shows. The app's translator (Apple's Translation framework, #159) does the work.
/// Only finished words are translated, since translating words that are still changing would flicker and lag.
public struct CaptionTranslations: Equatable, Sendable {
    public struct Work: Equatable, Sendable {
        public let lineID: Int
        public let text: String
    }

    private struct Done: Equatable, Sendable { let source: String; let text: String }
    private var done: [Int: Done] = [:]
    private var asked: [Int: String] = [:]

    public init() {}

    /// Finished spoken lines whose words haven't been translated or asked for yet, oldest first. Marks them asked.
    public mutating func take(from lines: [CaptionLine]) -> [Work] {
        var work: [Work] = []
        for line in lines where line.isFinal && !line.isSoundLabel {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, done[line.id]?.source != text, asked[line.id] != text else { continue }
            asked[line.id] = text
            work.append(Work(lineID: line.id, text: text))
        }
        return work
    }

    /// A line's words came back translated. Lines only grow, so an answer for fewer words than one already shown is
    /// a late one and is dropped.
    public mutating func finished(lineID: Int, source: String, translation: String) {
        if asked[lineID] == source { asked[lineID] = nil }
        if let shown = done[lineID], shown.source.count > source.count { return }
        done[lineID] = Done(source: source, text: translation)
    }

    /// The translator couldn't do it; the line is offered again next time.
    public mutating func failed(lineID: Int, source: String) {
        if asked[lineID] == source { asked[lineID] = nil }
    }

    /// The translation to show above a line, or nil. An older translation stays until the newer one lands.
    public func translation(for line: CaptionLine) -> String? { done[line.id]?.text }

    /// A new conversation, or translation switched off.
    public mutating func reset() {
        done = [:]
        asked = [:]
    }
}

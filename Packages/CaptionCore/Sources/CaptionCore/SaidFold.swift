import Foundation

/// #246 (owner, PR #255: look C, "Folded", with a tap that hides or shows what was said). Every translated caption
/// shows just its translation with a small mark after it; a tap on the line shows what was said underneath, and
/// another tap hides it. This holds which lines are open, by line id, for one list of captions.
public struct SaidFold: Equatable, Sendable {
    /// The lines whose said words are showing.
    public private(set) var opened: Set<Int>

    public init(opened: Set<Int> = []) { self.opened = opened }

    public func isOpen(_ id: Int) -> Bool { opened.contains(id) }

    /// A tap on a translated line: opens it when folded, folds it when open. While words are selected (#107) a tap
    /// only lets go of the selection, so the line stays as it is. Returns whether the line changed.
    @discardableResult
    public mutating func tap(_ id: Int, selecting: Bool = false) -> Bool {
        guard !selecting else { return false }
        if opened.remove(id) == nil { opened.insert(id) }
        return true
    }

    /// Folds the lines that are gone. Line ids start again at 0 in a new conversation, so without this an old open
    /// line would open the new one that reuses its id.
    public mutating func keep(only ids: some Sequence<Int>) {
        opened.formIntersection(ids)
    }
}

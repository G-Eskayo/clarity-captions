import Foundation

/// One caption line. `id` stays stable while a volatile result is revised, so UI
/// doesn't flicker or re-animate on every partial update.
public struct CaptionLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public var text: String
    public var isFinal: Bool
}

/// The live caption transcript. Pure value type -- no audio, no UI, no platform
/// APIs -- so it is tested on the host and shared by every platform target.
public struct CaptionStream: Sendable {
    public private(set) var lines: [CaptionLine] = []
    private var nextID = 0

    public init() {}

    public mutating func apply(text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if var last = lines.last, !last.isFinal {
            last.text = trimmed
            last.isFinal = isFinal
            lines[lines.count - 1] = last
        } else {
            lines.append(CaptionLine(id: nextID, text: trimmed, isFinal: isFinal))
            nextID += 1
        }
    }
}

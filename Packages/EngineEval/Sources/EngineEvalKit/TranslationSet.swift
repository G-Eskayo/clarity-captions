import Foundation

/// One segment of a translation test set (#159), as written by `translation_eval.sets`.
public struct TranslationSegment: Codable, Equatable, Sendable {
    public let id: String
    public let set: String
    public let group: String
    public let source: String
    public let reference: String?

    /// The segment as a #145 clip, so the result store and run plan are reused unchanged: the set name rides in
    /// `accent`, there is no audio.
    public var asClip: ManifestClip { ManifestClip(clipID: id, file: "", accent: set, audioSeconds: 0) }
}

public enum TranslationSet {
    public static func load(_ url: URL) throws -> [TranslationSegment] {
        let data = try Data(contentsOf: url)
        return try data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .filter { !$0.allSatisfy { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\r") } }
            .map { try JSONDecoder().decode(TranslationSegment.self, from: Data($0)) }
    }
}

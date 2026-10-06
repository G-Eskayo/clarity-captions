import Foundation

/// User-provided custom names for speakers, with trimming and length enforcement.
public struct SpeakerNames: Equatable, Sendable {
    private var namesBySpeaker: [Int: String] = [:]

    /// The maximum character count for a speaker name (by `Character`, not UTF-8 bytes).
    public static let maxLength = 30

    /// Create an empty speaker names collection.
    public init() {}

    /// Return the custom name for a speaker, or nil if unset.
    public func name(for speaker: Int) -> String? {
        namesBySpeaker[speaker]
    }

    /// Apply a user-provided name to a speaker.
    /// Trims whitespace and newlines; truncates to `maxLength` by character count;
    /// treats a resulting empty string as a clear (removal).
    public mutating func apply(_ rawInput: String, to speaker: Int) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clear(speaker: speaker)
            return
        }

        let truncated = String(trimmed.prefix(Self.maxLength))
        namesBySpeaker[speaker] = truncated
    }

    /// Remove the custom name for a speaker, reverting to "Speaker N" on display.
    public mutating func clear(speaker: Int) {
        namesBySpeaker.removeValue(forKey: speaker)
    }
}

public enum SpeakerNaming {
    /// The maximum length for a speaker name.
    public static let maxLength = SpeakerNames.maxLength
}

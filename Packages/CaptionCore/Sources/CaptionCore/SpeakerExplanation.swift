import Foundation

public enum SpeakerExplanation {
    public static var sentence: String {
        String(localized: "Seal tells voices apart as people talk.")
    }
}

/// Remembers whether the user has seen the speaker explanation banner.
public struct SpeakerExplanationStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var hasSeen: Bool { defaults.bool(forKey: "speakerExplanation.seen") }
    public func markSeen() { defaults.set(true, forKey: "speakerExplanation.seen") }
}

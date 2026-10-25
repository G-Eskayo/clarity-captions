import Foundation

/// The payload sent to the watch: the latest caption line and its speaker.
public struct WatchCaptionPayload: Equatable, Sendable {
    public let line: String
    public let speakerLabel: String

    public init(line: String, speakerLabel: String) {
        self.line = line
        self.speakerLabel = speakerLabel
    }
}

/// Throttles and deduplicates caption updates sent to the watch. Prevents excessive Watch Connectivity
/// traffic by suppressing redundant or rapidly-revising updates; only settled text is sent.
public struct WatchCompanionBridge: Sendable {
    /// Minimum time between updates, in seconds. Partial revisions arriving faster than this are suppressed.
    public let minimumSendInterval: TimeInterval
    /// The last update we sent successfully.
    private var lastSentLine: String = ""
    private var lastSentSpeaker: String = ""
    /// When the last update was sent. Used to throttle rapid revisions.
    private var lastSentTime: Date?

    public init(minimumSendInterval: TimeInterval = 1.0) {
        self.minimumSendInterval = minimumSendInterval
    }

    /// Decide whether to send this update to the watch. Returns a payload if one should be sent, nil otherwise.
    /// - Parameters:
    ///   - line: The current caption line text. Empty strings during live captioning are suppressed; final empty lines are sent as explicit clears.
    ///   - speakerLabel: The speaker label (e.g., "Speaker 1"). Empty is allowed (no speaker yet).
    ///   - isFinal: Whether this is a final result (overrides throttling; always sends immediately).
    ///   - now: The current time, for throttling decisions.
    /// - Returns: A payload to send, or nil if throttling or deduplication suppresses this update.
    public mutating func update(line: String, speakerLabel: String, isFinal: Bool, now: Date) -> WatchCaptionPayload? {
        // Empty lines during live captioning are suppressed; final empty lines are sent as explicit clears.
        if line.isEmpty && !isFinal { return nil }

        // Identical line and speaker pair — suppress it.
        if line == lastSentLine && speakerLabel == lastSentSpeaker { return nil }

        // Throttle non-final revisions to avoid rapid chatter, but allow speaker changes even within the window
        // (a speaker change is a discrete event, not a partial revision of the same text).
        let speakerChanged = speakerLabel != lastSentSpeaker
        if !isFinal && !speakerChanged {
            if let lastTime = lastSentTime, now.timeIntervalSince(lastTime) < minimumSendInterval {
                return nil
            }
        }

        // Send this update.
        lastSentLine = line
        lastSentSpeaker = speakerLabel
        lastSentTime = now
        return WatchCaptionPayload(line: line, speakerLabel: speakerLabel)
    }
}

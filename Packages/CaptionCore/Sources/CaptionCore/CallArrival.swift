import Foundation

/// A call arriving while the Mac captions the room (#178). Pure: the Mac app feeds it what the call watcher saw and
/// what was tapped, and carries out the effects it hands back, in order.
///
/// - Ringing while the room is captioned: a banner, nothing else changes. [ Not now ] or ignoring it: still nothing.
/// - [ Caption call ]: the room's conversation is paused (kept), the call is captioned.
/// - The call ends: captioning stops and the banner asks to save the call's transcript; either answer resumes the room,
///   if it was being captioned when the call came.
/// - Every call rings, captions on or off (owner, 2026-10-28 ~21:05 UTC: Seal Speak always offers to caption a call).
///   With captions off, the conversation on screen comes back after the call, and captions stay off.
public struct CallArrival: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// No call, or none we're involved in.
        case room
        /// A call is live and the banner is asking.
        case ringing
        /// A call is live and they said [ Not now ]: keep captioning the room.
        case declined
        /// Captioning the call; the room's conversation is paused.
        case call
        /// The call ended: asking whether to save its transcript.
        case ended
    }

    public enum Event: Equatable, Sendable {
        case callStarted, callEnded
        case captionCall, notNow
        case saveTranscript, returnToConversation
    }

    public enum Effect: Equatable, Sendable {
        /// Stop captioning the room and set its conversation aside, kept.
        case pauseRoom
        /// Start captioning the call in a fresh conversation.
        case startCall
        case stopCall
        /// Keep the call's transcript with the saved conversations.
        case saveCall
        /// Bring the room's conversation back and carry on captioning it.
        case resumeRoom
        /// Bring the conversation that was on screen back, captions still off (they were off when the call came).
        case restoreRoom
    }

    public enum Banner: Equatable, Sendable { case ringing, ended }

    public private(set) var step: Step = .room
    /// Whether the room was being captioned when the call came, so it's resumed only then.
    private var resumeRoomAfter = false

    public init() {}

    public var banner: Banner? {
        switch step {
        case .ringing: .ringing
        case .ended: .ended
        case .room, .declined, .call: nil
        }
    }

    /// `captioning`: whether the room is being captioned right now.
    public mutating func handle(_ event: Event, captioning: Bool) -> [Effect] {
        switch (step, event) {
        case (.room, .callStarted):
            step = .ringing
            return []
        case (.ringing, .captionCall):
            step = .call
            resumeRoomAfter = captioning
            return [.pauseRoom, .startCall]
        case (.ringing, .notNow):
            step = .declined
            return []
        case (.ringing, .callEnded), (.declined, .callEnded):
            step = .room
            return []
        case (.call, .callEnded):
            step = .ended
            return [.stopCall]
        case (.ended, .saveTranscript), (.ended, .returnToConversation):
            step = .room
            var effects: [Effect] = event == .saveTranscript ? [.saveCall] : []
            effects.append(resumeRoomAfter ? .resumeRoom : .restoreRoom)
            resumeRoomAfter = false
            return effects
        default:
            // Repeats (a call's sound reported twice) and stale taps (a banner button after the call ended) change nothing.
            return []
        }
    }
}

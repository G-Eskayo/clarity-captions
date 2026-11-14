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
/// - Multiple concurrent calls: a second call can ring while the first is active. The user can hold the first and accept
///   the second, or end the first and accept the second. Calls are stacked; each one's transcript is saved (or discarded)
///   independently when it ends.
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
        case secondCallStarted(app: String)
        case secondCallEnded
        case holdAndAccept(heldApp: String)
        case endAndAccept
        case callHeld
        case callResumedFromHold
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
        /// Hold the current call's conversation aside (like pauseRoom, but for a call).
        case holdCall
        /// Announce that a second call is ringing (via notification).
        case announceSecondCall(app: String)
        /// Resume a call that was held, or a room that was paused.
        case resumeHeldCall
    }

    public enum Banner: Equatable, Sendable { case ringing, ended }

    /// A paused conversation: either the room (with a flag for whether it was being captioned) or a held call.
    public enum Frame: Equatable, Sendable {
        case room(captioning: Bool)
        case heldCall(app: String)
    }

    public private(set) var step: Step = .room
    /// Stack of paused conversations: room pauses when a call starts, calls pause when a hold&accept happens.
    private var paused: [Frame] = []
    /// Tracks which second-call app is currently announced, to avoid duplicate announcements for repeated Core Audio signals.
    private var announcedSecondApp: String?
    /// The app of the incoming second call, recorded when secondCallStarted fires, used if endAndAccept is chosen.
    private var pendingIncomingApp: String?

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
            paused.append(.room(captioning: captioning))
            return [.pauseRoom, .startCall]
        case (.ringing, .notNow):
            step = .declined
            return []
        case (.ringing, .callEnded), (.declined, .callEnded):
            step = .room
            return []
        case (.call, .callStarted):
            // Repeat signal, no change.
            return []
        case (.call, .secondCallStarted(let app)):
            // Second call ringing during active call: announce but don't change state.
            // Only announce if this is the first time we're hearing about this app.
            if announcedSecondApp == app {
                // Repeated signal for the same app; don't announce again.
                return []
            }
            announcedSecondApp = app
            pendingIncomingApp = app
            return [.announceSecondCall(app: app)]
        case (.call, .secondCallEnded):
            // Second call stopped ringing; clear the announced app.
            announcedSecondApp = nil
            return []
        case (.call, .holdAndAccept(let heldApp)):
            // Hold the current call, start the second one.
            announcedSecondApp = nil
            pendingIncomingApp = nil
            paused.append(.heldCall(app: heldApp))
            return [.holdCall, .startCall]
        case (.call, .endAndAccept):
            // End the current call and start the second one, but the save prompt happens first.
            // Record that call2 is pending so it starts after the save is answered.
            announcedSecondApp = nil
            if let incomingApp = pendingIncomingApp {
                paused.append(.heldCall(app: incomingApp))
            }
            step = .ended
            return [.stopCall]
        case (.call, .callEnded):
            step = .ended
            return [.stopCall]
        case (.call, .callHeld):
            // Plain hold (not a second-call situation): pause the call in place (without changing step).
            // Push a frame to keep the paused stack in sync with CallFlow's state.
            // The app is unknown in this pure state machine, so we use a placeholder.
            paused.append(.heldCall(app: ""))
            return [.holdCall]
        case (.call, .callResumedFromHold):
            // Resume the call from a plain hold state.
            return [.resumeHeldCall]
        case (.ended, .saveTranscript), (.ended, .returnToConversation):
            // Pop the next frame from the stack and resume it.
            var effects: [Effect] = event == .saveTranscript ? [.saveCall] : []

            if paused.isEmpty {
                // Nothing on the stack; go back to room.
                step = .room
                // restoreRoom/resumeRoom decided by the caller based on the last popped frame's captioning flag.
                effects.append(.restoreRoom) // Default; caller may override
            } else {
                // Pop the last frame (which should be a room or heldCall).
                let popped = paused.removeLast()
                switch popped {
                case .room(let captioning):
                    step = .room
                    effects.append(captioning ? .resumeRoom : .restoreRoom)
                case .heldCall:
                    step = .call
                    effects.append(.resumeHeldCall)
                }
            }
            return effects
        default:
            // Repeats (a call's sound reported twice) and stale taps (a banner button after the call ended) change nothing.
            return []
        }
    }
}

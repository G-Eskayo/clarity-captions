import Foundation

/// A call arriving while the Mac captions the room (#178, #212). Pure: the Mac app feeds it what the call watcher saw and
/// what was tapped, and carries out the effects it hands back, in order.
///
/// - Ringing while the room is captioned: a banner, nothing else changes. [ Not now ] or ignoring it: still nothing.
/// - [ Caption call ]: the room's conversation is paused (kept), the call is captioned.
/// - The call ends: captioning stops and the banner asks to save the call's transcript; either answer resumes the room,
///   if it was being captioned when the call came.
/// - Every call rings, captions on or off (owner, 2026-10-28 ~21:05 UTC: Seal Speak always offers to caption a call).
///   With captions off, the conversation on screen comes back after the call, and captions stay off.
/// - Second call ringing while call 1 is active (#212): announced in Notification Center, call 1 stays active.
///   Hold & Accept or End & Accept actions hold/end call 1 and start call 2, with save prompts at each step.
///   No depth limit: call 3 can ring while call 2 is active, etc.
public struct CallArrival: Equatable, Sendable {
    /// A paused context: either the room (before any call) or a held call (while another call is active).
    public enum Frame: Equatable, Sendable {
        case room(captioning: Bool)
        case heldCall(app: String)
    }

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
        case secondCallStarted(app: String), secondCallEnded
        case holdAndAccept, endAndAccept
        case callHeld, callResumedFromHold
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
        /// Hold the active call without stopping it.
        case holdCall
        /// Resume a held call or the room.
        case resumeHeldCall
        /// Announce a second call in Notification Center.
        case announceSecondCall(app: String)
    }

    public enum Banner: Equatable, Sendable { case ringing, ended }

    public private(set) var step: Step = .room
    /// Stack of paused contexts: room (before any call) or held calls.
    private var paused: [Frame] = []
    /// Track which second call app has been announced to deduplicate signals.
    private var announcedSecondCallApp: String? = nil

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

        case (.call, .callEnded):
            step = .ended
            return [.stopCall]

        case (.call, .secondCallStarted(let app)):
            // Announce the second call but keep call 1 active, deduplicating repeated signals.
            if announcedSecondCallApp != app {
                announcedSecondCallApp = app
                return [.announceSecondCall(app: app)]
            }
            return []

        case (.call, .secondCallEnded):
            // Second call ended without being answered; clear the announcement.
            announcedSecondCallApp = nil
            return []

        case (.call, .holdAndAccept):
            // Hold call 1 and accept call 2 (which is about to start).
            announcedSecondCallApp = nil
            paused.append(.heldCall(app: "unknown"))
            step = .call
            return [.holdCall, .startCall]

        case (.call, .endAndAccept):
            // End call 1 (save prompt), then start call 2 after answer.
            step = .ended
            return [.stopCall]

        case (.call, .callHeld):
            // Hold the current call without accepting another.
            paused.append(.heldCall(app: "unknown"))
            return [.holdCall]

        case (.call, .callResumedFromHold):
            // Resume the held call (unresumed-after-hold, not a second call scenario).
            if !paused.isEmpty, case .heldCall = paused.last {
                paused.removeLast()
            }
            return [.resumeHeldCall]

        case (.ended, .saveTranscript), (.ended, .returnToConversation):
            var effects: [Effect] = event == .saveTranscript ? [.saveCall] : []

            // Determine what to resume: a held call, or the room.
            if !paused.isEmpty {
                let last = paused.removeLast()
                switch last {
                case .room(let wasCapitioning):
                    step = .room
                    effects.append(wasCapitioning ? .resumeRoom : .restoreRoom)
                case .heldCall:
                    effects.append(.resumeHeldCall)
                    // After resuming a held call, check if there's a room below it.
                    // If so, skip the call and go back to room instead.
                    if !paused.isEmpty, case .room(let wasCapitioning) = paused.last {
                        paused.removeLast()
                        step = .room
                        effects.append(wasCapitioning ? .resumeRoom : .restoreRoom)
                    } else {
                        // No room below, resume the call normally.
                        step = .call
                    }
                }
            } else {
                step = .room
                effects.append(.resumeRoom)
            }

            return effects

        default:
            // Repeats and stale taps change nothing.
            return []
        }
    }
}

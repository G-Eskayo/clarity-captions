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
/// - Multiple calls can arrive one after another, each with its own save prompt and pause/resume cycle (#178).
public struct CallArrival: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// No call, or none we're involved in.
        case room
        /// A call is live and the banner is asking.
        case ringing
        /// A call is live and they said [ Not now ]: keep captioning the room.
        case declined
        /// Captioning the call; room or earlier calls are on the stack, paused.
        case call
        /// The active call ended: asking whether to save its transcript.
        case ended
    }

    public enum Frame: Equatable, Sendable {
        case room(captioning: Bool)
        case heldCall(app: String, captioning: Bool)
        case secondCallAwaiting(app: String)
    }

    public enum Event: Equatable, Sendable {
        case callStarted, callEnded
        case secondCallStarted(app: String)
        case secondCallEnded
        case captionCall, notNow
        case holdAndAccept(heldApp: String)
        case endAndAccept(heldApp: String)
        case callHeld, callResumedFromHold
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
        /// Hold the current call, pausing it; the next call will be started on top.
        case holdCall
        /// Announce that a second call is incoming (app name included for context).
        case announceSecondCall(app: String)
        /// Resume a call that was held.
        case resumeHeldCall
    }

    public enum Banner: Equatable, Sendable { case ringing, ended }

    public private(set) var step: Step = .room
    /// Stack of paused contexts. Invariant: while in `.ended`, the stack contains at least the room frame.
    /// If a call was active, it was preceded by pushing `.room` when transitioning to `.call`.
    private var paused: [Frame] = []
    /// Track which app has an active second call announcement; nil if no second call is available.
    private var secondCallApp: String?
    /// Whether a call was queued while waiting for a save answer; cleared after handling the answer.
    private(set) var queuedCall = false

    public init() {}

    /// Clear the queued call flag (called after processing a queued call in the view layer).
    mutating func clearQueuedCall() {
        queuedCall = false
    }

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
        case (.call, .secondCallStarted(let app)):
            // Second call detected while the first is captioning; announce but don't switch.
            // Only emit an announcement if this is a different app than we already announced.
            if secondCallApp != app {
                secondCallApp = app
                return [.announceSecondCall(app: app)]
            }
            return []
        case (.call, .secondCallEnded):
            // Second call ended without being accepted; clear the availability.
            secondCallApp = nil
            return []
        case (.call, .callEnded):
            // If we have a plain hold on the stack, the call ending means the hold is released too
            if !paused.isEmpty, case .heldCall(let app, _) = paused.last, app == "paused-by-user" {
                paused.removeLast()
            }
            step = .ended
            secondCallApp = nil
            return [.stopCall]
        case (.call, .holdAndAccept(let heldApp)):
            // Hold the current call, start the second. Only valid if a second call is currently available.
            guard secondCallApp != nil else { return [] }
            paused.append(.heldCall(app: heldApp, captioning: captioning))
            secondCallApp = nil
            return [.holdCall, .startCall]
        case (.call, .endAndAccept(let heldApp)):
            // Stop the current call, queue the second to start after the save prompt.
            // Only valid if a second call is currently available.
            guard secondCallApp != nil else { return [] }
            paused.append(.secondCallAwaiting(app: secondCallApp!))
            step = .ended
            secondCallApp = nil
            return [.stopCall]
        case (.call, .callHeld):
            // User tapped Hold; pause the call (same mechanism as pausing the room for a call).
            paused.append(.heldCall(app: "paused-by-user", captioning: captioning))
            return [.holdCall]
        case (.call, .callResumedFromHold):
            // User tapped Resume; resume the held call.
            guard !paused.isEmpty, case .heldCall(let app, _) = paused.last, app == "paused-by-user" else { return [] }
            paused.removeLast()
            return [.resumeHeldCall]
        case (.ended, .saveTranscript), (.ended, .returnToConversation):
            let saveEffect: [Effect] = event == .saveTranscript ? [.saveCall] : []
            guard !paused.isEmpty else {
                // Stack is empty; go back to room. No paused conversation to resume.
                step = .room
                return saveEffect + [.restoreRoom]
            }
            let frame = paused.removeLast()
            switch frame {
            case .room(let wasCaptioning):
                let resumeEffect: Effect = wasCaptioning ? .resumeRoom : .restoreRoom
                step = .room
                return saveEffect + [resumeEffect]
            case .heldCall:
                // Resuming a call that was held; transition back to .call state.
                step = .call
                return saveEffect + [.resumeHeldCall]
            case .secondCallAwaiting:
                // Starting a second call after save; stay in .ended, let the first effect trigger startCall.
                step = .call
                return saveEffect + [.startCall]
            }
        case (.ended, .callStarted):
            // A new call arrived while waiting for save answer; queue it (stay in .ended).
            queuedCall = true
            return []
        default:
            // Repeats (a call's sound reported twice) and stale taps (a banner button after the call ended) change nothing.
            return []
        }
    }
}

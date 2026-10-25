import Foundation

/// The six steps of the guided tour, in order. Each step waits for one specific action that the user
/// must take on a real control that's already on screen.
public enum TourStep: Int, CaseIterable, Equatable, Sendable {
    case start = 0, listening, pause, save, copy, gear

    /// The trigger that advances from this step to the next.
    public var requiredTrigger: TourTrigger {
        switch self {
        case .start: return .startedCaptioning
        case .listening: return .captionArrived
        case .pause: return .paused
        case .save: return .saved
        case .copy: return .copied
        case .gear: return .openedSettings
        }
    }

    /// The step that comes after this one, or nil if this is the last step.
    public var next: TourStep? {
        TourStep(rawValue: self.rawValue + 1)
    }

    /// The step that comes before this one, or nil if this is the first step.
    public var previous: TourStep? {
        guard self.rawValue > 0 else { return nil }
        return TourStep(rawValue: self.rawValue - 1)
    }
}

/// The six actions that can advance the tour. Each matches exactly one step's `requiredTrigger`.
public enum TourTrigger: Equatable, Sendable {
    case startedCaptioning, captionArrived, paused, saved, copied, openedSettings
}

/// The tour state machine: which step the user is on, and whether the tour is still active.
/// Once `isActive == false` (via skip or finish), all further commands are no-ops.
public struct TourState: Equatable, Sendable {
    public var step: TourStep = .start
    public var isActive: Bool = true

    public init(startingStep: TourStep = .start) {
        self.step = startingStep
    }

    /// If the tour is active and the trigger matches the current step's required trigger, advance to the next step.
    /// If this was the last step, deactivate instead.
    public mutating func handle(_ trigger: TourTrigger) {
        guard isActive, trigger == step.requiredTrigger else { return }
        next()
    }

    /// Advance to the next step without requiring the action. If on the last step, deactivate.
    public mutating func next() {
        guard isActive else { return }
        if let nextStep = step.next {
            step = nextStep
        } else {
            isActive = false
        }
    }

    /// Return to the previous step, or do nothing if on the first step.
    public mutating func back() {
        guard isActive, let prevStep = step.previous else { return }
        step = prevStep
    }

    /// Deactivate the tour immediately, regardless of which step.
    public mutating func skip() {
        isActive = false
    }
}

/// Copy text for each step of the tour, matching the mock-up in spec §7.
/// English only for now; all text is localized via String(localized:).
public struct TourCopy: Equatable, Sendable {
    public let title: String
    public let body: String

    public static func `for`(_ step: TourStep) -> TourCopy {
        switch step {
        case .start:
            TourCopy(
                title: String(localized: "Hi! Let's get started."),
                body: String(localized: "I'll show you how to use Seal. Tap the big button to start captioning.")
            )
        case .listening:
            TourCopy(
                title: String(localized: "I'm listening."),
                body: String(localized: "I'm turned on and picking up what people say around you. Keep talking—I'll show you the words on screen.")
            )
        case .pause:
            TourCopy(
                title: String(localized: "Pause any time."),
                body: String(localized: "Tap Stop to pause. You can scroll back through the conversation, or copy what you want to remember.")
            )
        case .save:
            TourCopy(
                title: String(localized: "Save it."),
                body: String(localized: "Tap Save to keep this conversation on your phone. Saved conversations stick around for 30 days.")
            )
        case .copy:
            TourCopy(
                title: String(localized: "Copy words."),
                body: String(localized: "Hold your finger on any words to copy them. You can send them to anyone, anytime.")
            )
        case .gear:
            TourCopy(
                title: String(localized: "All set!"),
                body: String(localized: "That's the whole thing. Tap the gear to change how the words look.")
            )
        }
    }
}

/// Remembers whether the user has seen the tour at least once.
public struct TourStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var hasSeenTour: Bool { defaults.bool(forKey: "tour.hasSeenTour") }
    public func markSeen() { defaults.set(true, forKey: "tour.hasSeenTour") }
}

/// The scripted demo line played when the room is quiet, so the user sees captions working
/// even before anyone nearby speaks. Once there is real speech, the demo line is gone from future saves.
public struct TourDemoLine {
    public static let text = String(localized: "Hi! Can you read what I'm saying?")

    /// Returns true if we should inject the demo line (room is quiet, tour is on the save step).
    /// The demo line only injects during the tour's Save step, never during a normal Save outside the tour.
    public static func isNeeded(hasRealConversation: Bool, tourStepIsSave: Bool) -> Bool {
        tourStepIsSave && !hasRealConversation
    }
}

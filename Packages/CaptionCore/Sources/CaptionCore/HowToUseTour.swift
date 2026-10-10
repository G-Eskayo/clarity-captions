import Foundation

/// The "How to use Seal" guided tour: a lightweight state machine that walks the user through the main controls.
/// Reuses the `FirstRun.step(for:)` pattern: tour position is always re-derived from real facts, never trusted from memory.
public struct HowToUseTour: Equatable, Sendable {
    public enum TourStep: CaseIterable, Equatable, Sendable {
        case start, pause, save, new, copy, gear
    }

    private var stepIndex: Int?

    public var currentStep: TourStep? {
        guard let idx = stepIndex else { return nil }
        guard idx >= 0 && idx < TourStep.allCases.count else { return nil }
        return TourStep.allCases[idx]
    }

    public var isFinished: Bool { stepIndex == nil }

    public init() {
        self.stepIndex = 0
    }

    public mutating func didPerform(_ action: TourStep) {
        guard !isFinished, let current = currentStep, action == current else { return }
        advance()
    }

    public mutating func next() {
        advance()
    }

    public mutating func back() {
        guard let idx = stepIndex, idx > 0 else { return }
        stepIndex = idx - 1
    }

    public mutating func skip() {
        stepIndex = nil
    }

    private mutating func advance() {
        guard let idx = stepIndex else { return }
        let nextIdx = idx + 1
        if nextIdx >= TourStep.allCases.count {
            stepIndex = nil
        } else {
            stepIndex = nextIdx
        }
    }

    /// Which step to start the tour on, as a pure function of what is true right now.
    /// Mirrors `FirstRun.step(for:)`: a real conversation resumes at `.pause`, otherwise starts at `.start`.
    public static func initialStep(state: CaptionState, hasConversation: Bool) -> TourStep {
        if hasConversation {
            return .pause
        }
        return .start
    }

    /// Whether to show demo content for a given step.
    /// Demo lines are shown only on `.save` and `.copy` steps when there's no real conversation yet.
    /// Once a real conversation starts, the demo content disappears and the real transcript shows.
    public static func showsDemoContent(step: TourStep?, hasConversation: Bool) -> Bool {
        guard let step else { return false }
        return (step == .save || step == .copy) && !hasConversation
    }

    /// Whether to keep the pause veil and its controls visible during a step, even without a real conversation.
    /// This ensures [Save] and [New] can be spotlighted during the demo, though nothing is recorded.
    public static func showsSpotlightTarget(step: TourStep?, hasConversation: Bool) -> Bool {
        guard let step else { return false }
        return (step == .save || step == .new || step == .copy) && !hasConversation
    }

    /// Maps a tour step to a frame-tracking key for spotlight rendering.
    /// Used to look up on-screen coordinates of controls being toured.
    /// Guard against silent mismatches if TourStep is renamed.
    public static func frameKey(for step: TourStep) -> String {
        switch step {
        case .start: "start"
        case .pause: "pause"
        case .save: "save"
        case .new: "new"
        case .copy: "copy"
        case .gear: "gear"
        }
    }
}

/// Remembers whether the user has seen the tour (one-time, then replayable on demand).
public struct HowToUseTourStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasSeenTour: Bool {
        defaults.bool(forKey: "howToUseTour.seen")
    }

    public func markSeen() {
        defaults.set(true, forKey: "howToUseTour.seen")
    }
}

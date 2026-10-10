import Foundation

/// The how-to-use tour (#108, spec §7, mock-up 09): six steps on the real main screen. A spotlight sits on the real
/// control and each step moves on when she actually does the thing. Next moves on without doing it, Back goes to the
/// step before, Skip ends it; there are no timers, so she goes as fast or as slow as she wants.
public enum TourStep: Int, CaseIterable, Equatable, Sendable {
    case start, captions, pause, saveOrNew, copy, gear

    /// The real action that completes this step.
    func isCompleted(by action: TourAction) -> Bool {
        switch (self, action) {
        case (.start, .tappedStart), (.captions, .captionShown), (.pause, .tappedStop),
             (.saveOrNew, .tappedSave), (.saveOrNew, .tappedNew), (.copy, .copied), (.gear, .openedSettings):
            true
        default:
            false
        }
    }
}

/// Something she did on the real screen, reported to the tour.
public enum TourAction: Equatable, Sendable {
    case tappedStart, captionShown, tappedStop, tappedSave, tappedNew, copied, openedSettings
}

public struct HowToUseTour: Equatable, Sendable {
    public enum Ending: Equatable, Sendable { case finished, skipped }

    /// The step on screen, or nil when the tour isn't running.
    public private(set) var step: TourStep?
    /// How the last run ended; nil while running or before the first run.
    public private(set) var ending: Ending?

    public init(step: TourStep? = nil) {
        self.step = step
    }

    public var isRunning: Bool { step != nil }
    public var isLastStep: Bool { step == TourStep.allCases.last }
    public var canGoBack: Bool { (step?.rawValue ?? 0) > 0 }
    /// 0-based, for the progress dots.
    public var position: Int { step?.rawValue ?? 0 }

    /// Starts (or restarts, for a replay) at the first step.
    public mutating func begin() {
        step = .start
        ending = nil
    }

    /// She did something on the real screen; the tour moves on only if it's what this step asks for.
    public mutating func did(_ action: TourAction) {
        guard let step, step.isCompleted(by: action) else { return }
        advance(from: step)
    }

    public mutating func next() {
        guard let step else { return }
        advance(from: step)
    }

    public mutating func back() {
        guard let step, let previous = TourStep(rawValue: step.rawValue - 1) else { return }
        self.step = previous
    }

    public mutating func skip() {
        guard step != nil else { return }
        step = nil
        ending = .skipped
    }

    private mutating func advance(from current: TourStep) {
        if let following = TourStep(rawValue: current.rawValue + 1) {
            step = following
        } else {
            step = nil
            ending = .finished
        }
    }
}

/// When the tour may start. Never in the middle of a conversation: it walks her through starting one.
public enum TourGate {
    /// The one automatic run, after first run and after the launch animation: only on an idle, empty screen.
    public static func startsByItself(hasSeen: Bool, state: CaptionState, hasConversation: Bool, launchCovering: Bool) -> Bool {
        !hasSeen && !launchCovering && state == .idle && !hasConversation
    }

    /// Replay from Settings: any time captioning isn't running.
    public static func canReplay(state: CaptionState) -> Bool {
        switch state {
        case .idle, .failed, .pausedQuiet: true
        case .preparing, .listening: false
        }
    }
}

/// A quiet room has nothing to caption, so the tour can show one example line instead. It's text only: no audio is
/// recorded or saved, and a conversation that is nothing but the example is never written to the saved list.
public enum TourExample {
    public static var text: String { String(localized: "Hi! Can you read what I'm saying?") }
    /// How long with no caption before the tour offers the example.
    public static let quietSeconds: Double = 6

    public static func offersExample(secondsWithoutCaption: Double, isCaptioning: Bool) -> Bool {
        isCaptioning && secondsWithoutCaption >= quietSeconds
    }

    public static func isOnlyExample(lines: [CaptionLine], exampleIDs: Set<Int>) -> Bool {
        let spoken = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !spoken.isEmpty && spoken.allSatisfy { exampleIDs.contains($0.id) }
    }
}

/// The words on each step's card (mock-up 09; step 4 follows the owner's note on [ New ]: it just clears, after one
/// confirmation so a stray tap can't wipe the conversation).
public struct TourCopy: Equatable, Sendable {
    public let title: String
    public let message: String

    public static func `for`(_ step: TourStep) -> TourCopy {
        switch step {
        case .start:
            TourCopy(title: String(localized: "Tap Start captions"),
                     message: String(localized: "Put the phone on the table between you and the people talking. Go ahead, tap it."))
        case .captions:
            TourCopy(title: String(localized: "Say something"),
                     message: String(localized: "Your words show up here as people talk. Each new voice gets its own label."))
        case .pause:
            TourCopy(title: String(localized: "Tap X to pause"),
                     message: String(localized: "Nothing is lost. Start captions carries on where you left off."))
        case .saveOrNew:
            TourCopy(title: String(localized: "Tap [ Save ] to keep it"),
                     message: String(localized: "Saved conversations stay for 30 days. [ New ] clears the screen for a fresh one. It asks first, so a stray tap won't wipe it."))
        case .copy:
            TourCopy(title: String(localized: "Hold on words to copy them"),
                     message: String(localized: "Press and hold, stretch the selection, then tap Copy."))
        case .gear:
            TourCopy(title: String(localized: "Make it yours"),
                     message: String(localized: "The gear changes colors, text size and lettering. You can take this tour again there."))
        }
    }
}

/// Whether the tour has been seen. Stored on the device only.
public struct TourStore {
    private let defaults: UserDefaults
    private static let key = "howToUseTourSeen"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var hasSeen: Bool { defaults.bool(forKey: Self.key) }
    public func markSeen() { defaults.set(true, forKey: Self.key) }
}

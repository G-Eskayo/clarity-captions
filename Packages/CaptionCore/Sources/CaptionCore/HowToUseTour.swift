import Foundation

/// The how-to-use tour v3 (#137; approved 2026-10-15, mock-ups round4/01). Four steps the person controls: every step
/// but the last has [ Next ›], and the real action (Start, ✕) moves its step on too. Nothing is on a timer and nothing
/// is hidden after a few seconds. Back and Skip tour are on every step; the last has [ Done ].
/// Replaces tour v2 (#121), whose action-only steps looked frozen when the action wasn't obvious (TestFlight build 3:
/// "it wasn't on a timer, just hung").
public enum TourStep: Int, CaseIterable, Equatable, Sendable {
    case start, captions, pause, done

    /// Whether `action` moves this step on.
    static func completes(_ step: TourStep, _ action: TourAction) -> Bool {
        switch (step, action) {
        case (.start, .tappedStart), (.pause, .tappedStop), (.done, .tappedDone): true
        case (.start, .tappedNext), (.captions, .tappedNext), (.pause, .tappedNext): true
        default: false
        }
    }
}

/// Kept for callers; tour v3 has a single phase (no follow-up beats, no waiting inside Settings).
public enum TourPhase: Equatable, Sendable {
    case waiting
}

/// Something that happened on the real screen, reported to the tour. Tour v3 acts on tappedStart, tappedStop,
/// tappedNext and tappedDone; the rest are still reported by the app and ignored.
public enum TourAction: Equatable, Sendable {
    case tappedStart, captionShown, tappedStop, tappedSave, saveMomentFinished, clearedDim, restoredDim,
         openedSettings, closedSettings, tappedDone, followUpRead
    /// [ Next ›], on every step but the last.
    case tappedNext
}

/// The words a step shows, straight on the dim (no card).
public struct TourWords: Equatable, Sendable {
    public let title: String
    public let message: String
    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

/// The parts of the real screen the tour points at.
public enum TourSpot: Hashable, Sendable {
    case start, stop, save, gear, captions
    /// The list icon at the top right (#137): lit with the gear on the last step, which names both.
    case savedList
    case veil
    case captionArea
    case everything
}

/// What's lit and what answers on a step. `lit` gets the spotlight; touches pass only to `answers` (plus the tour's own
/// Next, Back, Skip and Done); `dims` says whether the tour lays its own dim over the screen.
public struct TourFocus: Equatable, Sendable {
    public let lit: TourSpot?
    public let answers: TourSpot?
    public let dims: Bool
    public init(lit: TourSpot?, answers: TourSpot?, dims: Bool) {
        self.lit = lit
        self.answers = answers
        self.dims = dims
    }
}

public struct HowToUseTour: Equatable, Sendable {
    public enum Ending: Equatable, Sendable { case finished, skipped }

    public private(set) var step: TourStep?
    public private(set) var phase: TourPhase = .waiting
    public private(set) var ending: Ending?

    public init(step: TourStep? = nil, phase: TourPhase = .waiting) {
        self.step = step
        self.phase = phase
    }

    public var isRunning: Bool { step != nil }
    public var canGoBack: Bool { (step?.rawValue ?? 0) > 0 }
    /// [ Next ›] on every step but the last.
    public var hasNextButton: Bool { isRunning && step != .done }
    /// [ Done ] only on the last.
    public var hasDoneButton: Bool { step == .done }
    /// "3 of 4".
    public var progress: String {
        let number = (step?.rawValue ?? 0) + 1
        let total = TourStep.allCases.count
        return String(localized: "\(number) of \(total)")
    }
    /// Words are always shown while the tour runs: nothing disappears on a timer.
    public var showsWords: Bool { isRunning }

    public mutating func begin() {
        step = .start
        phase = .waiting
        ending = nil
    }

    public mutating func did(_ action: TourAction) {
        guard let step, TourStep.completes(step, action) else { return }
        phase = .waiting
        if let following = TourStep(rawValue: step.rawValue + 1) {
            self.step = following
        } else {
            self.step = nil
            ending = .finished
        }
    }

    public mutating func back() {
        guard let step, let previous = TourStep(rawValue: step.rawValue - 1) else { return }
        self.step = previous
        phase = .waiting
    }

    public mutating func skip() {
        guard step != nil else { return }
        step = nil
        phase = .waiting
        ending = .skipped
    }

    public var focus: TourFocus {
        switch step {
        case .start?: TourFocus(lit: .start, answers: .start, dims: true)
        case .captions?: TourFocus(lit: .captionArea, answers: nil, dims: true)
        case .pause?: TourFocus(lit: .stop, answers: .stop, dims: true)
        case .done?: TourFocus(lit: .gear, answers: nil, dims: true)
        case nil: TourFocus(lit: nil, answers: nil, dims: true)
        }
    }

    /// The approved words (round4/01). The last step names where saved conversations are (option A, top right).
    public var words: TourWords {
        switch step {
        case .start?:
            TourWords(title: String(localized: "Set the phone flat on the table."),
                      message: String(localized: "Between you and whoever's talking. Then tap Start captions."))
        case .captions?:
            TourWords(title: String(localized: "Words show up here as people talk."),
                      message: String(localized: "A new voice gets its own line. Seal goes by the sound of the voice, so it can mix people up. Scroll up any time to reread."))
        case .pause?:
            TourWords(title: String(localized: "Tap ✕ to pause."),
                      message: String(localized: "[ Save ] keeps the conversation on this phone for 30 days. [ New ] starts a clean page."))
        case .done?, nil:
            TourWords(title: String(localized: "That's it."),
                      message: String(localized: "The gear has colors, text size and lettering. Your saved conversations are at the top right. Open one to share it, or hold on words to copy.\n\nYou can replay this in Settings."))
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

/// A quiet room has nothing to caption, so step 2 can show an example: two voices, so "Each voice gets its own line"
/// has something to point at. Text only: no audio is recorded or saved, and a conversation that is nothing but the
/// example is never written to the saved list.
public enum TourExample {
    public struct Line: Equatable, Sendable {
        public let text: String
        public let speaker: Int
    }

    public static var lines: [Line] {
        [Line(text: String(localized: "Hi, is this working? I can see what I'm saying."), speaker: 0),
         Line(text: String(localized: "Yep, it put me on my own line."), speaker: 1)]
    }

    /// How long with no caption before step 2 offers [ Show an example ].
    public static let quietSeconds: Double = 6

    public static func offersExample(secondsWithoutCaption: Double, isCaptioning: Bool) -> Bool {
        isCaptioning && secondsWithoutCaption >= quietSeconds
    }

    public static func isOnlyExample(lines: [CaptionLine], exampleIDs: Set<Int>) -> Bool {
        let spoken = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !spoken.isEmpty && spoken.allSatisfy { exampleIDs.contains($0.id) }
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

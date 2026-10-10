import Foundation

/// The how-to-use tour v2 (#121; approved in #120, mock-ups round3/01-02, flow from #117): eight steps on the real
/// screen. Each step moves on only when she really does it: there is no Next on an action step, and nothing but the lit
/// control answers. Back and Skip tour are on every step; only the last has a button, [ Done ]. Copy and [ New ] aren't
/// taught (copy works like every other app, and practising [ New ] would wipe her practice); the last step mentions them.
public enum TourStep: Int, CaseIterable, Equatable, Sendable {
    case start, captions, pause, save, clearDim, holdBack, gear, done

    /// Whether `action` is the one that moves this step on from `phase`.
    static func completes(_ step: TourStep, phase: TourPhase, _ action: TourAction) -> Bool {
        switch (step, phase, action) {
        case (.start, .waiting, .tappedStart), (.captions, .waiting, .captionShown), (.captions, .followUp, .followUpRead),
             (.pause, .waiting, .tappedStop), (.save, .waiting, .tappedSave), (.save, .savingMoment, .saveMomentFinished),
             (.save, .followUp, .followUpRead), (.clearDim, .waiting, .clearedDim), (.holdBack, .waiting, .restoredDim),
             (.gear, .waiting, .openedSettings), (.gear, .inSettings, .closedSettings), (.done, .waiting, .tappedDone):
            true
        default:
            false
        }
    }
}

/// Where a step is. Two steps have a second moment: her words appearing brings "That's you." (step 2), and [ Save ]
/// plays [ ✔ ] → [ Saved ] before "Saved." (step 4). Step 7 waits while Settings is open.
public enum TourPhase: Equatable, Sendable {
    case waiting, savingMoment, followUp, inSettings
}

/// Something that happened on the real screen, reported to the tour.
public enum TourAction: Equatable, Sendable {
    case tappedStart, captionShown, tappedStop, tappedSave, saveMomentFinished, clearedDim, restoredDim,
         openedSettings, closedSettings, tappedDone
    /// The reading beat after a follow-up's words.
    case followUpRead
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
    /// The pause dim itself (step 5: "the whole dim is lit").
    case veil
    /// The captions' empty space, where holding brings the dim back (step 6).
    case captionArea
    /// Everything works (Settings, while step 7 waits for her to come back).
    case everything
}

/// What's lit and what answers on a step. `lit` gets the spotlight; touches pass only to `answers`; `dims` says whether
/// the tour lays its own dim over the screen (steps 5 and 6 use the pause dim and the captions themselves instead).
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

    /// The step on screen, or nil when the tour isn't running.
    public private(set) var step: TourStep?
    public private(set) var phase: TourPhase = .waiting
    /// How the last run ended; nil while running or before the first run.
    public private(set) var ending: Ending?

    public init(step: TourStep? = nil, phase: TourPhase = .waiting) {
        self.step = step
        self.phase = phase
    }

    public var isRunning: Bool { step != nil }
    public var canGoBack: Bool { (step?.rawValue ?? 0) > 0 }
    /// Only the last step has a button to finish; every other step waits for the real action.
    public var hasDoneButton: Bool { step == .done }
    /// "3 of 8".
    public var progress: String {
        let number = (step?.rawValue ?? 0) + 1
        let total = TourStep.allCases.count
        return String(localized: "\(number) of \(total)")
    }
    /// The words are off only while [ ✔ ] → [ Saved ] plays.
    public var showsWords: Bool { isRunning && phase != .savingMoment }

    /// Starts (or restarts, for a replay) at the first step.
    public mutating func begin() {
        step = .start
        phase = .waiting
        ending = nil
    }

    /// Something happened on the real screen; the tour moves on only if it's what this step and phase wait for.
    public mutating func did(_ action: TourAction) {
        guard let step, TourStep.completes(step, phase: phase, action) else { return }
        switch (step, phase) {
        case (.captions, .waiting), (.save, .savingMoment):
            phase = .followUp
        case (.save, .waiting):
            phase = .savingMoment
        case (.gear, .waiting):
            phase = .inSettings
        default:
            advance(from: step)
        }
    }

    /// Back on the Save step after it was already saved (nothing new said since): straight to "Saved.".
    public mutating func alreadySaved() {
        guard step == .save, phase == .waiting else { return }
        phase = .followUp
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

    private mutating func advance(from current: TourStep) {
        phase = .waiting
        if let following = TourStep(rawValue: current.rawValue + 1) {
            step = following
        } else {
            step = nil
            ending = .finished
        }
    }

    /// What's lit and what answers right now (round3/01: "Only Start is lit. Nothing else answers.").
    public var focus: TourFocus {
        switch (step, phase) {
        case (.start?, _): TourFocus(lit: .start, answers: .start, dims: true)
        case (.captions?, .followUp): TourFocus(lit: .captions, answers: nil, dims: true)
        case (.captions?, _): TourFocus(lit: nil, answers: nil, dims: true)
        case (.pause?, _): TourFocus(lit: .stop, answers: .stop, dims: true)
        case (.save?, .waiting): TourFocus(lit: .save, answers: .save, dims: true)
        case (.save?, _): TourFocus(lit: .save, answers: nil, dims: true)
        case (.clearDim?, _): TourFocus(lit: nil, answers: .veil, dims: false)
        case (.holdBack?, _): TourFocus(lit: nil, answers: .captionArea, dims: false)
        case (.gear?, .inSettings): TourFocus(lit: nil, answers: .everything, dims: false)
        case (.gear?, _): TourFocus(lit: .gear, answers: .gear, dims: true)
        case (.done?, _), (nil, _): TourFocus(lit: nil, answers: nil, dims: true)
        }
    }

    /// The approved words (#120, every step "keep as drafted").
    public var words: TourWords {
        switch (step, phase) {
        case (.start?, _):
            TourWords(title: String(localized: "Set the phone flat on the table."),
                      message: String(localized: "Between you and whoever's talking. Then tap Start captions."))
        case (.captions?, .followUp):
            TourWords(title: String(localized: "That's you."),
                      message: String(localized: "Each voice gets its own line and label. Seal goes by the sound of the voice, so it can mix people up. It doesn't know who anyone is."))
        case (.captions?, _):
            TourWords(title: String(localized: "Say something."),
                      message: String(localized: "Your words show up here as you talk."))
        case (.pause?, _):
            TourWords(title: String(localized: "Tap ✕ to pause."),
                      message: String(localized: "Nothing gets lost. Start captions picks up where you left off."))
        case (.save?, .followUp):
            TourWords(title: String(localized: "Saved."),
                      message: String(localized: "It stays green until somebody says something new."))
        case (.save?, _):
            TourWords(title: String(localized: "Tap [ Save ]."),
                      message: String(localized: "Keeps it on this phone for 30 days."))
        case (.clearDim?, _):
            TourWords(title: String(localized: "Tap anywhere on the dim."),
                      message: String(localized: "It clears so you can read and scroll back."))
        case (.holdBack?, _):
            TourWords(title: String(localized: "Hold an empty spot."),
                      message: String(localized: "The buttons come back."))
        case (.gear?, _):
            TourWords(title: String(localized: "Tap the gear."),
                      message: String(localized: "Colors, text size and lettering. Tap it again to come back."))
        case (.done?, _), (nil, _):
            TourWords(title: String(localized: "That's it."),
                      message: String(localized: "[ New ] clears the screen for the next conversation. It asks once first.\n\nHold on any words to copy them.\n\nIf it goes quiet for a while, captions pause on their own.\n\nYou can replay this in Settings."))
        }
    }
}

/// The tour's beats. The app waits these out; the model only hears `followUpRead` when they're over.
public enum TourTiming {
    /// After her first words show, how long before "That's you." replaces "Say something." (she sees her words first).
    public static let captionSeenSeconds: Double = 1.2

    /// How long a follow-up's words stay before the next step fades in.
    public static func followUpSeconds(for step: TourStep) -> Double {
        switch step {
        case .captions: 6.0   // "That's you." is the longest message
        default: 3.5          // "Saved."
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

import Foundation

public enum MicrophoneAccess: Equatable, Sendable { case undetermined, granted, denied }

public enum FirstRunStep: Equatable, Sendable, CaseIterable {
    case unsupported, welcome, microphone, microphoneDenied, speechModel, speakerModel, done
}

/// Everything the first-run flow needs to know, as plain facts.
public struct FirstRunFacts: Equatable, Sendable {
    public var hasSeenWelcome: Bool
    public var microphone: MicrophoneAccess
    public var speechModelInstalled: Bool
    public var speakerModelWarm: Bool
    /// Whether this device can caption at all (#80). Defaults to supported so callers that don't check are unchanged.
    public var speechSupport: SpeechSupport
    public init(hasSeenWelcome: Bool, microphone: MicrophoneAccess, speechModelInstalled: Bool, speakerModelWarm: Bool,
                speechSupport: SpeechSupport = .supported) {
        self.speechSupport = speechSupport
        self.hasSeenWelcome = hasSeenWelcome
        self.microphone = microphone
        self.speechModelInstalled = speechModelInstalled
        self.speakerModelWarm = speakerModelWarm
    }
}

/// Which screen to show, as a pure function of what is true right now -- not of what happened before.
/// That makes an interrupted first run resume in the right place, and brings back the right screen if
/// the microphone is switched off later.
public enum FirstRun {
    public static func step(for f: FirstRunFacts) -> FirstRunStep {
        // First, before the welcome: nothing else on this device can lead to captions.
        if !f.speechSupport.canCaption { return .unsupported }
        if !f.hasSeenWelcome { return .welcome }
        switch f.microphone {
        case .undetermined: return .microphone
        case .denied: return .microphoneDenied
        case .granted: break
        }
        if !f.speechModelInstalled { return .speechModel }
        if !f.speakerModelWarm { return .speakerModel }
        return .done
    }
}

/// Plain, friendly words (Delight principle, ADR 0013). No technical terms: a test enforces it.
public struct FirstRunCopy: Equatable, Sendable {
    public let title: String
    public let message: String
    /// nil for steps that run by themselves.
    public let button: String?

    public static func `for`(_ step: FirstRunStep) -> FirstRunCopy {
        switch step {
        case .unsupported:
            FirstRunCopy(title: String(localized: "This device can't show captions"),
                         message: String(localized: "Captions need a newer iPhone or iPad that can turn speech into words by itself. Sorry about that!"),
                         button: nil)
        case .welcome:
            FirstRunCopy(title: String(localized: "Hi! Let's get you set up."),
                         message: String(localized: "I'll help you follow conversations by showing what people say. This takes about a minute."),
                         button: String(localized: "Let's go"))
        case .microphone:
            FirstRunCopy(title: String(localized: "I need to hear the room"),
                         message: String(localized: "On the next screen, tap Allow so I can turn speech into words. Everything stays on your phone."),
                         button: String(localized: "Continue"))
        case .microphoneDenied:
            FirstRunCopy(title: String(localized: "I can't hear yet"),
                         message: String(localized: "Captions need the microphone. Tap the button, then switch Microphone on."),
                         button: String(localized: "Open Settings"))
        case .speechModel:
            FirstRunCopy(title: String(localized: "Learning English"),
                         message: String(localized: "A one-time download. Please keep Wi-Fi on. It only happens once."),
                         button: nil)
        case .speakerModel:
            FirstRunCopy(title: String(localized: "Getting ready to tell voices apart"),
                         message: String(localized: "Almost there! This is a one-time warm-up so you never wait later."),
                         button: nil)
        case .done:
            FirstRunCopy(title: String(localized: "All set!"),
                         message: String(localized: "Tap the big button any time you want captions."),
                         button: String(localized: "Start captioning"))
        }
    }
}

/// Remembers what the user has already seen. The warm-up is tied to the OS and app build because an
/// update can drop the Neural Engine's prepared copy of the speaker model.
public struct FirstRunStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var hasSeenWelcome: Bool { defaults.bool(forKey: "firstRun.welcomeSeen") }
    public func markWelcomeSeen() { defaults.set(true, forKey: "firstRun.welcomeSeen") }

    public func isSpeakerModelWarm(forBuild build: String) -> Bool {
        defaults.string(forKey: "firstRun.speakerWarmBuild") == build
    }
    public func markSpeakerModelWarm(forBuild build: String) {
        defaults.set(build, forKey: "firstRun.speakerWarmBuild")
    }
}

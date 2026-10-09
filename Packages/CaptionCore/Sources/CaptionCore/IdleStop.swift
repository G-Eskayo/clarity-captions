import Foundation

/// How long captioning may go without captioned speech before it stops on its own (ADR 0019).
/// The one behavior setting: presets only, and Never is available but never the default.
public enum IdleStopSetting: String, CaseIterable, Sendable {
    case fiveMinutes, fifteenMinutes, thirtyMinutes, never

    public static let `default`: IdleStopSetting = .fiveMinutes

    public var minutes: Int? {
        switch self {
        case .fiveMinutes: 5
        case .fifteenMinutes: 15
        case .thirtyMinutes: 30
        case .never: nil
        }
    }

    public var title: String {
        switch self {
        case .fiveMinutes: String(localized: "5 minutes")
        case .fifteenMinutes: String(localized: "15 minutes")
        case .thirtyMinutes: String(localized: "30 minutes")
        case .never: String(localized: "Never")
        }
    }
}

public struct IdleStopStore {
    public static let key = "idleStop"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> IdleStopSetting {
        defaults.string(forKey: Self.key).flatMap(IdleStopSetting.init(rawValue:)) ?? .default
    }

    public func save(_ setting: IdleStopSetting) { defaults.set(setting.rawValue, forKey: Self.key) }
}

/// The quiet clock: time since the last captioned speech (or since Start, or since the app came back).
/// Pure, with the time passed in, so every rule is checked without waiting.
public struct IdleStopClock {
    private var quietSince: Date?
    public private(set) var setting: IdleStopSetting

    public init(setting: IdleStopSetting) { self.setting = setting }

    public mutating func begin(at now: Date) { quietSince = now }
    public mutating func end() { quietSince = nil }
    public mutating func recordSpeech(at now: Date) { if quietSince != nil { quietSince = now } }

    /// After the app was suspended, time away isn't silence the app heard: start the stretch again.
    public mutating func resumed(at now: Date) { if quietSince != nil { quietSince = now } }

    /// A different setting applies at once, and restarts the stretch so she isn't stopped while still in Settings.
    public mutating func change(to newSetting: IdleStopSetting, at now: Date) {
        guard newSetting != setting else { return }
        setting = newSetting
        if quietSince != nil { quietSince = now }
    }

    public mutating func shouldStop(now: Date) -> Bool {
        guard let since = quietSince, let minutes = setting.minutes else { return false }
        if now < since {            // the clock jumped backwards: restart from here rather than wait out the jump
            quietSince = now
            return false
        }
        return now.timeIntervalSince(since) >= Double(minutes) * 60
    }
}

/// The screen stays awake only while captioning, and only while the app is on screen (ADR 0019).
public enum ScreenAwakePolicy {
    public static func keepAwake(state: CaptionState, appIsActive: Bool) -> Bool {
        guard appIsActive else { return false }
        switch state {
        case .preparing, .listening: return true
        case .idle, .failed, .pausedQuiet: return false
        }
    }
}

/// Applies `ScreenAwakePolicy` through an injected setter (the app passes `UIApplication.isIdleTimerDisabled`),
/// calling it only when the answer changes.
@MainActor
public final class ScreenAwakeKeeper {
    private let apply: (Bool) -> Void
    private var state: CaptionState = .idle
    private var appIsActive = true
    private var applied = false

    public init(apply: @escaping (Bool) -> Void) { self.apply = apply }

    public func update(state: CaptionState) { self.state = state; reapply() }
    public func update(appIsActive: Bool) { self.appIsActive = appIsActive; reapply() }

    private func reapply() {
        let wanted = ScreenAwakePolicy.keepAwake(state: state, appIsActive: appIsActive)
        guard wanted != applied else { return }
        applied = wanted
        apply(wanted)
    }
}

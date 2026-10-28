import Foundation

/// Which speech recognizer captions run on (ADR 0025). Changed only from the developer panel; users never see it.
public enum CaptionEngineChoice: String, CaseIterable, Sendable {
    case parakeet
    case apple

    public static let key = "captionEngine.v1"

    /// The developer panel's pick, Parakeet unless set. Only an Xcode build has the panel (owner, PR #155), so any
    /// other build ignores a pick saved earlier: nobody can be pinned to a choice they can't reach.
    public static func stored(in defaults: UserDefaults = .standard, developerBuild: Bool) -> CaptionEngineChoice {
        guard developerBuild else { return .parakeet }
        return defaults.string(forKey: key).flatMap(CaptionEngineChoice.init(rawValue:)) ?? .parakeet
    }
}

/// Why a session runs on Apple's engine when Parakeet was asked for. Goes in diagnostics and the beta report.
public enum FallbackReason: String, Sendable, Equatable {
    case modelMissing, loadFailed, lowMemory, locale, repeatedFallbacks, noWordsFromSpeech, memoryWarning, thermalCritical
}

public struct EngineSelection: Sendable, Equatable {
    public let engine: CaptionEngineChoice
    public let reason: FallbackReason?
    public init(engine: CaptionEngineChoice, reason: FallbackReason?) {
        self.engine = engine
        self.reason = reason
    }
}

public enum FallbackTrigger: Sendable, Equatable {
    case loadFailed
    case noWordsFromSpeech
    case memoryWarning
    case thermal(ProcessInfo.ThermalState)
}

public enum FallbackAction: Sendable, Equatable {
    case none
    case normalHop
    case doubleHop
    case switchToApple

    /// Switches count toward the two-in-a-day pin; hop changes don't.
    public var countsAsFallback: Bool { self == .switchToApple }
}

/// The design's fallback table (§5), pure.
public enum EngineFallbackPolicy {
    /// Available memory below this before loading Parakeet: Apple for the session (start value, tuned by check C3).
    public static let memoryFloor: UInt64 = 400 * 1_048_576
    public static let pinWindow: TimeInterval = 86_400

    public static func engine(for choice: CaptionEngineChoice, now: Date, recentFallbacks: [Date], availableMemory: UInt64,
                              locale: Locale, modelPresent: Bool) -> EngineSelection {
        guard choice == .parakeet else { return EngineSelection(engine: .apple, reason: nil) }
        if !modelPresent { return EngineSelection(engine: .apple, reason: .modelMissing) }
        if locale.language.languageCode != .english { return EngineSelection(engine: .apple, reason: .locale) }
        let inWindow = recentFallbacks.filter { $0 <= now && now.timeIntervalSince($0) <= pinWindow }
        if inWindow.count >= 2 { return EngineSelection(engine: .apple, reason: .repeatedFallbacks) }
        if availableMemory < memoryFloor { return EngineSelection(engine: .apple, reason: .lowMemory) }
        return EngineSelection(engine: .parakeet, reason: nil)
    }

    public static func action(for trigger: FallbackTrigger, running: CaptionEngineChoice) -> FallbackAction {
        guard running == .parakeet else { return .none }
        switch trigger {
        case .loadFailed, .noWordsFromSpeech, .memoryWarning: return .switchToApple
        case .thermal(.serious): return .doubleHop
        case .thermal(.critical): return .switchToApple
        case .thermal: return .normalHop
        }
    }

    public static func reason(for trigger: FallbackTrigger) -> FallbackReason? {
        switch trigger {
        case .loadFailed: .loadFailed
        case .noWordsFromSpeech: .noWordsFromSpeech
        case .memoryWarning: .memoryWarning
        case .thermal(.critical): .thermalCritical
        case .thermal: nil
        }
    }
}

/// When Parakeet last fell back on this device, kept for a day. Bounded: anything older is dropped on write.
public struct EngineFallbackHistory {
    public static let key = "captionEngine.fallbacks.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func recent(now: Date) -> [Date] {
        let stamps = defaults.array(forKey: Self.key) as? [Double] ?? []
        return stamps.map(Date.init(timeIntervalSince1970:))
            .filter { $0 <= now && now.timeIntervalSince($0) <= EngineFallbackPolicy.pinWindow }
    }

    /// Forget every fallback: the developer picked an engine on purpose (phone checks, ADR 0025).
    public mutating func clear() { defaults.removeObject(forKey: Self.key) }

    public mutating func record(_ date: Date, now: Date) {
        let kept = (recent(now: now) + [date]).map(\.timeIntervalSince1970)
        defaults.set(kept, forKey: Self.key)
    }
}

/// Trips once if Parakeet is producing nothing at the start of a session (design §5): no words at all through 20 s of
/// loud audio, or three failed decodes in a row. (The design's first draft said 10 s; a loud room where nobody has
/// spoken yet would have tripped it.) One word disarms it for the session.
public struct SilentEngineWatchdog: Sendable {
    public static let limit = 20.0
    public static let failuresInARow = 3
    private var speechSeconds = 0.0
    private var failures = 0
    private var done = false

    public init() {}

    /// `speech`: the last stretch was loud enough to be someone talking. Returns true exactly once, when it trips.
    public mutating func observe(seconds: Double, speech: Bool, words: Int, failed: Bool = false) -> Bool {
        guard !done else { return false }
        if words > 0 { done = true; return false }
        failures = failed ? failures + 1 : 0
        if speech { speechSeconds += seconds }
        if speechSeconds >= Self.limit - 1e-9 || failures >= Self.failuresInARow { done = true; return true }
        return false
    }
}

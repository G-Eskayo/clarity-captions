import Foundation

/// Everything one replayed session did (#273), written as one JSON file per session. Times (`at`) are seconds since
/// the audio source started, the same zero as the engine's own lag clock; audio times (`start`, `end`) are seconds
/// of audio fed, so a word at audio time t was "spoken" at t on the same clock.
public struct SessionLog: Codable, Sendable {
    public static let harnessVersion = "system-replay 1"

    public struct Plan: Codable, Sendable {
        /// What `CaptionEnginePlan.make` chose before the session: "parakeet" or "apple".
        public var engine: String
        /// Its `FallbackReason`, nil when Parakeet was chosen.
        public var reason: String?
        public var locale: String
        public var choice: String
        public var availableMemoryBytes: UInt64
        /// Where the memory figure came from: on the Mac there is no per-app limit, so it is physical memory.
        public var memorySource: String
        public var modelPresent: Bool
        public init(engine: String, reason: String?, locale: String, choice: String, availableMemoryBytes: UInt64,
                    memorySource: String, modelPresent: Bool) {
            self.engine = engine; self.reason = reason; self.locale = locale; self.choice = choice
            self.availableMemoryBytes = availableMemoryBytes; self.memorySource = memorySource; self.modelPresent = modelPresent
        }
    }

    public struct EngineSeen: Codable, Sendable, Equatable {
        public var name: String
        public var firstAt: Double
        public init(name: String, firstAt: Double) { self.name = name; self.firstAt = firstAt }
    }

    public struct Fallback: Codable, Sendable, Equatable {
        public var reason: String
        public var at: Double
        public init(reason: String, at: Double) { self.reason = reason; self.at = at }
    }

    public struct State: Codable, Sendable, Equatable {
        public var state: String
        public var at: Double
        public init(state: String, at: Double) { self.state = state; self.at = at }
    }

    public struct Word: Codable, Sendable, Equatable {
        public var text: String
        public var start: Double?
        public var end: Double?
        public init(text: String, start: Double? = nil, end: Double? = nil) {
            self.text = text; self.start = start; self.end = end
        }
    }

    public struct Update: Codable, Sendable {
        public var at: Double
        public var text: String
        public var isFinal: Bool
        /// The engine's own lag sample (WordLagTracker, ADR 0015), nil when it saw no new word end.
        public var lag: Double?
        public var speaker: Int?
        public var start: Double?
        public var end: Double?
        public var engine: String
        public var fallback: String?
        /// Per-word timing: text and start/end for each word in the caption.
        public var words: [Word]?
        public init(at: Double, text: String, isFinal: Bool, lag: Double?, speaker: Int?, start: Double?, end: Double?,
                    engine: String, fallback: String?, words: [Word]? = nil) {
            self.at = at; self.text = text; self.isFinal = isFinal; self.lag = lag; self.speaker = speaker
            self.start = start; self.end = end; self.engine = engine; self.fallback = fallback; self.words = words
        }
    }

    public struct Line: Codable, Sendable {
        public var text: String
        public var speaker: Int?
        public var soundLabel: String?
        /// Audio time range for this line.
        public var start: Double?
        public var end: Double?
        public init(text: String, speaker: Int?, soundLabel: String?, start: Double? = nil, end: Double? = nil) {
            self.text = text; self.speaker = speaker; self.soundLabel = soundLabel; self.start = start; self.end = end
        }
    }

    public struct Seam: Codable, Sendable {
        /// Window start time (session audio seconds) when Parakeet took a hop.
        public var windowStart: Double
        /// Audio end time of this hop.
        public var audioEnd: Double
        public init(windowStart: Double, audioEnd: Double) {
            self.windowStart = windowStart; self.audioEnd = audioEnd
        }
    }

    public var harness = SessionLog.harnessVersion
    /// Which app code ran, e.g. "main@f7e2596" or "build-9@3c56e56" (passed in; the harness can't know).
    public var label: String
    /// "source": an AudioSource into TranscriptionEngine.start(), as the microphone (1.1.0 (9) on). "replaying": the
    /// engine's own startReplaying(fileURL:), the only file path 1.0 has; every build has it, so 1.0 vs 10 is fair.
    public var path: String = "source"
    public var audio: String
    public var audioSeconds: Double
    public var tailSeconds: Double
    public var deliveryRate: Double
    public var framesPerBuffer: Int
    public var host: String
    public var os: String
    public var startedAt: String
    public var plan: Plan
    public var loadSeconds: Double?
    public var startupReport: String = ""
    public var enginesSeen: [EngineSeen] = []
    public var fallbacks: [Fallback] = []
    public var finalEngine: String = ""
    public var finalFallbackReason: String?
    public var fallbackDetail: String?
    public var decodeP50: Double?
    public var decodeP95: Double?
    public var states: [State] = []
    public var updates: [Update] = []
    /// The caption lines as the app's CaptionStream built them, which is what she reads.
    public var lines: [Line] = []
    /// Parakeet decode window boundaries: each hop's window start and audio end. Nil for older session logs.
    public var seams: [Seam]?
    public var wallSeconds: Double = 0
    /// The session ended with a Stop tap at the end of the recording (replaying path), not by its stream ending.
    public var stoppedByTap = false
    /// How long Stop took to give everything back (1.0's touches the mic's input node, slow on a Mac with no mic).
    public var stopSeconds: Double?
    /// Stop hadn't given everything back within the harness's wait (`--stop-wait`); the lines are as they were then.
    public var stopTimedOut = false
    /// Set when the session failed or timed out; the scorer refuses a session with an error.
    public var error: String?

    public init(label: String, audio: String, audioSeconds: Double, tailSeconds: Double, deliveryRate: Double,
                framesPerBuffer: Int, host: String, os: String, startedAt: String, plan: Plan) {
        self.label = label; self.audio = audio; self.audioSeconds = audioSeconds; self.tailSeconds = tailSeconds
        self.deliveryRate = deliveryRate; self.framesPerBuffer = framesPerBuffer; self.host = host; self.os = os
        self.startedAt = startedAt; self.plan = plan
    }

    /// Records an update and, the first time an engine name appears, that engine (a mid-session switch shows here
    /// even if no fallback callback fired).
    public mutating func record(_ update: Update) {
        updates.append(update)
        if !update.engine.isEmpty, enginesSeen.last?.name != update.engine {
            enginesSeen.append(EngineSeen(name: update.engine, firstAt: update.at))
        }
    }

    /// True when any part of the session ran on something other than Parakeet: the plan said Apple, a fallback
    /// fired, or an update came from another engine. The scorer reports these sessions separately.
    public var leftParakeet: Bool {
        plan.engine != "parakeet" || !fallbacks.isEmpty || enginesSeen.contains { !$0.name.hasPrefix("parakeet") }
    }
}

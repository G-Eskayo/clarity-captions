import Foundation

/// What the session controller needs from a captioning engine. The real engine is `TranscriptionEngine`;
/// tests use a fake, so the lifecycle rules below are checked without a microphone or a speech model.
public protocol CaptioningEngine: AnyObject {
    var startupReport: String { get }
    func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error>
    func soundLabelsStream() -> AsyncStream<SoundLabelKind>
    func audioLevelStream() -> AsyncStream<Double>
    /// Must be safe to call more than once, and safe to call after a failed start.
    func stop() async
}

extension TranscriptionEngine: CaptioningEngine {}

/// Owns one captioning session at a time: start, run, stop, and cleanup.
///
/// Rules this exists to guarantee (a regression test covers each):
/// - The state stays `listening` for as long as the engine runs, and returns to `idle` only after it has stopped.
/// - Tapping Start while a session exists does nothing, so engines (and speech recognizers, which the system
///   limits) can never pile up.
/// - A start that fails, or a session that errors, always releases the engine before reporting the failure.
/// - Stop always gets back to `idle`, even if the engine leaves its sound-label or level stream open (#89).
@MainActor
public final class CaptionSessionController {
    public private(set) var state: CaptionState = .idle {
        didSet { if state != oldValue { onStateChange(state) } }
    }
    public var onStateChange: (CaptionState) -> Void = { _ in }
    public var onUpdate: (CaptionUpdate) -> Void = { _ in }
    public var onSoundLabel: (SoundLabelKind) -> Void = { _ in }
    public var onAudioLevel: (Double) -> Void = { _ in }
    public var onStartup: (String) -> Void = { _ in }

    private let makeEngine: () throws -> CaptioningEngine
    private var task: Task<Void, Never>?
    private var engine: CaptioningEngine?
    private var stopRequested = false
    private let now: () -> Date
    private let idleStopSetting: () -> IdleStopSetting
    private var idleClock = IdleStopClock(setting: .never)
    /// Set when the idle stop ends the session, so it ends as `.pausedQuiet` rather than `.idle`.
    private var quietStopMinutes: Int?

    /// - Parameters:
    ///   - now: the clock for the idle stop; injected so tests don't wait.
    ///   - idleStopSetting: read on every `tick()`, so a change in Settings applies mid-session. Defaults to
    ///     `.never` so a caller that doesn't opt in (the Mac app) never stops on its own.
    public init(
        makeEngine: @escaping () throws -> CaptioningEngine,
        now: @escaping () -> Date = { Date() },
        idleStopSetting: @escaping () -> IdleStopSetting = { .never }
    ) {
        self.makeEngine = makeEngine
        self.now = now
        self.idleStopSetting = idleStopSetting
    }

    /// Begins a session. Does nothing if one is already starting or running.
    public func start() {
        guard task == nil else { return }
        stopRequested = false
        quietStopMinutes = nil
        state = .preparing
        let engine: CaptioningEngine
        do { engine = try makeEngine() } catch {
            state = .failed(FailureReason.plainLanguage(for: error))
            return
        }
        self.engine = engine
        task = Task { await self.run(engine) }
    }

    /// Checks the idle stop (ADR 0019). The app calls this about once a second while listening; cheap, and does
    /// nothing in any other state.
    public func tick() {
        guard state == .listening, task != nil, quietStopMinutes == nil else { return }
        let t = now()
        idleClock.change(to: idleStopSetting(), at: t)
        guard idleClock.shouldStop(now: t), let minutes = idleClock.setting.minutes else { return }
        quietStopMinutes = minutes
        stop()
    }

    /// The app came back after being suspended: time away isn't silence, so the quiet stretch starts again.
    public func noteResumed() { idleClock.resumed(at: now()) }

    /// Ends the session, if any, without waiting.
    public func stop() { Task { await self.stopAndWait() } }

    /// Ends the session and returns once everything has been released.
    public func stopAndWait() async {
        guard let engine, let task else { return }
        stopRequested = true
        await engine.stop()
        await task.value
    }

    private var endedState: CaptionState { quietStopMinutes.map { .pausedQuiet(minutes: $0) } ?? .idle }

    private func recordIfSpeech(_ update: CaptionUpdate) {
        if !update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { idleClock.recordSpeech(at: now()) }
    }

    private func run(_ engine: CaptioningEngine) async {
        defer { task = nil; self.engine = nil; idleClock.end() }
        do {
            let updates = try await engine.start()
            onStartup(engine.startupReport)
            if stopRequested { await engine.stop(); state = .idle; return }
            idleClock = IdleStopClock(setting: idleStopSetting())
            idleClock.begin(at: now())
            state = .listening
            let labels = engine.soundLabelsStream()
            let levels = engine.audioLevelStream()
            // The caption stream is the session: when it ends or fails, the side streams are cancelled rather than
            // waited for. Waiting for all three hung Stop on a real device, where the level stream was never
            // finished (#89), and also held back a caption failure until every side stream had ended.
            try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask { @MainActor [weak self] in
                    for try await u in updates { self?.recordIfSpeech(u); self?.onUpdate(u) }
                    return true
                }
                group.addTask { @MainActor [weak self] in
                    for await l in labels { self?.onSoundLabel(l) }
                    return false
                }
                group.addTask { @MainActor [weak self] in
                    for await level in levels { self?.onAudioLevel(level) }
                    return false
                }
                while let captionsEnded = try await group.next() {
                    if captionsEnded { group.cancelAll(); break }
                }
            }
            await engine.stop()
            state = endedState
        } catch {
            await engine.stop()
            state = stopRequested ? endedState : .failed(FailureReason.plainLanguage(for: error))
        }
    }
}

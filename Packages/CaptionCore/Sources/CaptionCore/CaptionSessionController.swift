import Foundation

public enum InterruptionReason: Sendable {
    case phoneCall
    case otherApp
}

public enum CaptionEngineEvent: Sendable {
    case interruptionBegan(InterruptionReason)
    case interruptionEnded
}

/// What the session controller needs from a captioning engine. The real engine is `TranscriptionEngine`;
/// tests use a fake, so the lifecycle rules below are checked without a microphone or a speech model.
public protocol CaptioningEngine: AnyObject {
    var startupReport: String { get }
    func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error>
    func soundLabelsStream() -> AsyncStream<SoundLabelKind>
    func events() -> AsyncStream<CaptionEngineEvent>
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
@MainActor
public final class CaptionSessionController {
    public private(set) var state: CaptionState = .idle {
        didSet { if state != oldValue { onStateChange(state) } }
    }
    public var onStateChange: (CaptionState) -> Void = { _ in }
    public var onUpdate: (CaptionUpdate) -> Void = { _ in }
    public var onSoundLabel: (SoundLabelKind) -> Void = { _ in }
    public var onStartup: (String) -> Void = { _ in }

    private let makeEngine: () throws -> CaptioningEngine
    private let pauseTimeout: Duration
    private var task: Task<Void, Never>?
    private var engine: CaptioningEngine?
    private var stopRequested = false

    public init(makeEngine: @escaping () throws -> CaptioningEngine, pauseTimeout: Duration = .seconds(30)) {
        self.makeEngine = makeEngine
        self.pauseTimeout = pauseTimeout
    }

    /// Begins a session. Does nothing if one is already starting or running.
    public func start() {
        guard task == nil else { return }
        stopRequested = false
        state = .preparing
        let engine: CaptioningEngine
        do { engine = try makeEngine() } catch {
            state = .failed(String(describing: error))
            return
        }
        self.engine = engine
        task = Task { await self.run(engine) }
    }

    /// Ends the session, if any, without waiting.
    public func stop() { Task { await self.stopAndWait() } }

    /// Ends the session and returns once everything has been released.
    public func stopAndWait() async {
        guard let engine, let task else { return }
        stopRequested = true
        await engine.stop()
        await task.value
    }

    private func run(_ engine: CaptioningEngine) async {
        defer { task = nil; self.engine = nil }
        do {
            let updates = try await engine.start()
            onStartup(engine.startupReport)
            if stopRequested { await engine.stop(); state = .idle; return }
            state = .listening
            let labels = engine.soundLabelsStream()
            let events = engine.events()
            let pauseState = PauseTimeoutState()

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor [weak self] in
                    for try await u in updates { self?.onUpdate(u) }
                }
                group.addTask { @MainActor [weak self] in
                    for await l in labels { self?.onSoundLabel(l) }
                }
                group.addTask { @MainActor [weak self] in
                    for await e in events {
                        guard let self else { return }
                        switch e {
                        case .interruptionBegan(let reason):
                            if self.state == .listening {
                                let reasonText = reason == .phoneCall ? String(localized: "Phone call") : String(localized: "Another app")
                                self.state = .paused(reasonText)

                                pauseState.task?.cancel()
                                pauseState.task = Task {
                                    try? await Task.sleep(for: self.pauseTimeout)
                                    if !Task.isCancelled {
                                        pauseState.reason = reasonText
                                        await self.engine?.stop()
                                    }
                                }
                            }
                        case .interruptionEnded:
                            if case .paused = self.state {
                                pauseState.task?.cancel()
                                pauseState.task = nil
                                self.state = .listening
                            }
                        }
                    }
                }
                try await group.waitForAll()
            }
            await engine.stop()
            if let reason = pauseState.reason {
                state = stopRequested ? .idle : .failed(reason)
            } else {
                state = .idle
            }
        } catch {
            await engine.stop()
            state = stopRequested ? .idle : .failed(String(describing: error))
        }
    }

    private class PauseTimeoutState {
        var task: Task<Void, Never>?
        var reason: String?
    }
}

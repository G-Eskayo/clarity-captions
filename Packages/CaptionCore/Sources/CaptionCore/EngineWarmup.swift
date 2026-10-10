import Foundation

/// Loads the captioning engine before she taps Start (#119). The owner, on #117: "The loading screen at the beginning
/// is supposed to cover the getting-ready." The launch animation covers this load, so Start is instant; inside the app
/// the only sign of getting ready is the status row.
///
/// Rules (EngineWarmupTests covers each):
/// - Loading never starts the engine: the microphone stays closed and nothing prompts for permission.
/// - At most one engine is loaded or loading at a time (the system limits speech recognizers).
/// - A session takes the engine, loaded or still loading, exactly once; after that it belongs to the session.
/// - A failed load frees what it opened and reports `.failed`; Start then makes its own engine and shows the
///   problem the normal way.
/// - `release()` frees an engine nobody took (going to the background, low memory); a load that finishes after a
///   release never comes back as ready.
@MainActor
public final class EngineWarmup {
    public enum State: Equatable, Sendable {
        case idle
        /// `step` of `EngineWarmup.steps` loading steps finished.
        case preparing(step: Int)
        case ready
        case failed
    }

    /// The speech model, the speaker model, the sound classifier (TranscriptionEngine.prepare).
    public static let steps = 3

    public private(set) var state: State = .idle {
        didSet { if state != oldValue { onChange(state) } }
    }
    public var onChange: (State) -> Void = { _ in }

    private let make: () throws -> CaptioningEngine
    private var engine: CaptioningEngine?
    /// Bumped whenever the engine is taken or released, so a load still in flight knows it's no longer wanted.
    private var generation = 0

    public init(make: @escaping () throws -> CaptioningEngine) {
        self.make = make
    }

    /// Starts loading, unless an engine is already loaded or loading.
    public func prepare() {
        guard engine == nil else { return }
        let made: CaptioningEngine
        do { made = try make() } catch {
            state = .failed
            return
        }
        engine = made
        generation += 1
        let mine = generation
        state = .preparing(step: 0)
        Task { [weak self] in
            do {
                try await made.prepare { step in
                    Task { @MainActor [weak self] in self?.stepFinished(step, generation: mine) }
                }
                self?.finished(generation: mine, ok: true)
            } catch {
                await made.stop()
                self?.finished(generation: mine, ok: false)
            }
        }
    }

    /// Hands the loaded (or still loading) engine to a session. Nil when nothing is loaded.
    public func take() -> CaptioningEngine? {
        guard let engine else { return nil }
        self.engine = nil
        generation += 1
        state = .idle
        return engine
    }

    /// Frees an engine nobody has taken.
    public func release() async {
        guard let engine else { return }
        self.engine = nil
        generation += 1
        state = .idle
        await engine.stop()
    }

    private func stepFinished(_ step: Int, generation: Int) {
        guard generation == self.generation, case .preparing(let current) = state, step > current else { return }
        state = .preparing(step: min(step, Self.steps))
    }

    private func finished(generation: Int, ok: Bool) {
        guard generation == self.generation else { return }
        if ok {
            state = .ready
        } else {
            engine = nil
            state = .failed
        }
    }
}

/// Whether the launch animation can hand over to the app (#119): first-run setup is done and the engine has loaded.
/// A load that failed or never started doesn't hold the launch (Start loads the engine itself and shows any problem),
/// and neither does a slow one past `maxWaitPastDance`, so a hung load can never trap her on the launch screen.
public enum LaunchReadiness {
    public static let maxWaitPastDance: TimeInterval = 6

    public static func isReady(firstRunReady: Bool, warmup: EngineWarmup.State, waitedPastDance: TimeInterval) -> Bool {
        guard firstRunReady else { return false }
        switch warmup {
        case .idle, .ready, .failed: return true
        case .preparing: return waitedPastDance >= maxWaitPastDance
        }
    }
}

public extension LaunchProgress {
    /// The bar while the engine loads: each finished step fills its third; the step in progress pulses (none of the
    /// three reports a percentage, so the bar never pretends to move within one).
    static func engine(step: Int) -> LaunchProgress {
        let n = Double(EngineWarmup.steps)
        let done = min(Double(max(0, step)), n)
        guard done < n else { return LaunchProgress(fill: 1, pulse: nil) }
        return LaunchProgress(fill: done / n, pulse: (done / n)...((done + 1) / n))
    }
}

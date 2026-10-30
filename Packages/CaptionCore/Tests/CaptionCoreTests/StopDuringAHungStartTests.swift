import XCTest
@testable import CaptionCore

/// #245 item 1 (owner, TestFlight 1.1 (9), iPad Pro 12.9"): face to face could not be stopped. A language whose speech
/// engine wasn't on the iPad started a silent download inside the engine's start; Stop waited for that start to finish,
/// and every later tap in the split waited behind Stop. Stop must always leave, at once, whatever is still starting.
@MainActor
final class StopDuringAHungStartTests: XCTestCase {
    /// An engine whose start doesn't return until released: a speech download, a model load that never ends.
    final class HungEngine: CaptioningEngine, @unchecked Sendable {
        var startupReport = "hung"
        private var release: CheckedContinuation<Void, Never>?
        private(set) var stopCount = 0
        private(set) var started = false
        private var updates: AsyncThrowingStream<CaptionUpdate, Error>.Continuation?

        func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
            started = true
            await withCheckedContinuation { release = $0 }
            let (stream, cont) = AsyncThrowingStream.makeStream(of: CaptionUpdate.self)
            updates = cont
            return stream
        }
        func finishStarting() { release?.resume(); release = nil }
        func soundLabelsStream() -> AsyncStream<SoundLabelKind> { AsyncStream { $0.finish() } }
        func audioLevelStream() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
        func stop() async { stopCount += 1; updates?.finish() }
    }

    final class QuickEngine: CaptioningEngine, @unchecked Sendable {
        var startupReport = "quick"
        private var updates: AsyncThrowingStream<CaptionUpdate, Error>.Continuation?
        func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
            let (stream, cont) = AsyncThrowingStream.makeStream(of: CaptionUpdate.self)
            updates = cont
            return stream
        }
        func soundLabelsStream() -> AsyncStream<SoundLabelKind> { AsyncStream { $0.finish() } }
        func audioLevelStream() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
        func stop() async { updates?.finish() }
    }

    private func eventually(_ what: String, timeout: Double = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition(), "timed out waiting for: \(what)")
    }

    /// Runs `work`, failing (instead of hanging the suite) when it takes longer than `seconds`.
    private func finishes(within seconds: Double, _ work: @escaping @MainActor () async -> Void) async -> Bool {
        var done = false
        Task { @MainActor in await work(); done = true }
        let deadline = Date().addingTimeInterval(seconds)
        while !done && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        return done
    }

    func testStopWhileTheEngineIsStillStartingReturnsAtOnce() async {
        let hung = HungEngine()
        let c = CaptionSessionController(makeEngine: { hung })
        c.start()
        await eventually("the engine is starting") { hung.started }
        XCTAssertEqual(c.state, .preparing)

        let returned = await finishes(within: 1) { await c.stopAndWait() }
        XCTAssertTrue(returned, "Stop waited for a start that never ends")
        XCTAssertEqual(c.state, .idle)
        hung.finishStarting()   // let the abandoned task end so the test leaves nothing running
        await eventually("the abandoned engine is stopped once its start returns") { hung.stopCount >= 1 }
    }

    func testTheAbandonedStartNeverChangesTheStateLater() async {
        let hung = HungEngine()
        let c = CaptionSessionController(makeEngine: { hung })
        var states: [CaptionState] = []
        c.onStateChange = { states.append($0) }
        c.start()
        await eventually("the engine is starting") { hung.started }
        await c.stopAndWait()
        let afterStop = states
        hung.finishStarting()
        await eventually("the abandoned engine is stopped") { hung.stopCount >= 1 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(states, afterStop, "a start that finishes after Stop mustn't say Listening")
        XCTAssertEqual(c.state, .idle)
    }

    func testStartAgainAfterStoppingAHungStartRunsANewEngine() async {
        let hung = HungEngine()
        let quick = QuickEngine()
        var engines: [CaptioningEngine] = [hung, quick]
        let c = CaptionSessionController(makeEngine: { engines.removeFirst() })
        c.start()
        await eventually("the first engine is starting") { hung.started }
        await c.stopAndWait()
        c.start()
        await eventually("the second engine listens") { c.state == .listening }
        hung.finishStarting()
        await eventually("the abandoned engine is stopped") { hung.stopCount >= 1 }
        XCTAssertEqual(c.state, .listening, "the old start ending must not touch the new session")
        await c.stopAndWait()
        XCTAssertEqual(c.state, .idle)
    }
}


/// #245: Stop leaves the split even when the engines don't finish stopping. It waits a moment for them, never longer.
final class WaitAtMostTests: XCTestCase {
    func testWorkThatNeverFinishesIsLeftAfterTheLimit() async {
        let start = ContinuousClock.now
        let finished = await waitAtMost(.milliseconds(200)) { try? await Task.sleep(for: .seconds(30)) }
        XCTAssertFalse(finished)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
    }

    func testWorkThatFinishesIsWaitedFor() async {
        let done = DoneFlag()
        let finished = await waitAtMost(.seconds(5)) { try? await Task.sleep(for: .milliseconds(20)); done.set() }
        XCTAssertTrue(finished)
        XCTAssertTrue(done.isSet)
    }
}

private final class DoneFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func set() { lock.withLock { done = true } }
    var isSet: Bool { lock.withLock { done } }
}

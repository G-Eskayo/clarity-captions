import XCTest
@testable import CaptionCore

/// The start / run / stop lifecycle. Regression for the "Maximum number of recognizers reached" bug: the
/// screen went back to idle while the engine was still running, so repeated Start taps piled up engines.
/// A fake engine stands in for the speech engine so these run anywhere, in milliseconds.
@MainActor
final class CaptionSessionControllerTests: XCTestCase {

    // MARK: fakes

    final class FakeEngine: CaptioningEngine, @unchecked Sendable {
        var startupReport = "fake startup"
        var startError: Error?
        var updates: [CaptionUpdate] = []
        var failAfterUpdates: Error?          // stream throws after yielding `updates`
        var holdOpen = false                  // keep the streams open until stop()
        var labels: [SoundLabelKind] = []
        private(set) var stopCount = 0
        private var updateCont: AsyncThrowingStream<CaptionUpdate, Error>.Continuation?
        private var labelCont: AsyncStream<SoundLabelKind>.Continuation?
        private var labelStream: AsyncStream<SoundLabelKind>?

        func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
            if let startError { throw startError }
            let (ls, lc) = AsyncStream.makeStream(of: SoundLabelKind.self)
            labelStream = ls; labelCont = lc
            let (stream, cont) = AsyncThrowingStream.makeStream(of: CaptionUpdate.self)
            updateCont = cont
            for u in updates { cont.yield(u) }
            for l in labels { lc.yield(l) }
            if !holdOpen {
                if let failAfterUpdates { cont.finish(throwing: failAfterUpdates) } else { cont.finish() }
                lc.finish()
            }
            return stream
        }
        func soundLabelsStream() -> AsyncStream<SoundLabelKind> { labelStream ?? AsyncStream { $0.finish() } }
        func stop() async {
            stopCount += 1
            updateCont?.finish(); labelCont?.finish()
        }
    }

    struct Boom: Error, Equatable {}

    private func update(_ text: String) -> CaptionUpdate {
        CaptionUpdate(text: text, isFinal: true, lagSeconds: nil, speaker: nil, startSeconds: nil, endSeconds: nil, diagnostics: "", wordEmphasis: [])
    }

    /// Waits (briefly) for a condition that depends on background work.
    private func eventually(_ what: String, timeout: Double = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition(), "timed out waiting for: \(what)")
    }

    private func make(_ engines: @escaping () -> FakeEngine) -> (CaptionSessionController, Log) {
        let log = Log()
        let c = CaptionSessionController(makeEngine: { log.created += 1; return engines() })
        c.onStateChange = { log.states.append($0) }
        c.onUpdate = { log.updates.append($0.text) }
        c.onSoundLabel = { log.labels.append($0) }
        c.onStartup = { log.startup = $0 }
        return (c, log)
    }
    final class Log { var created = 0; var states: [CaptionState] = []; var updates: [String] = []; var labels: [SoundLabelKind] = []; var startup = "" }

    // MARK: tests

    func testStaysListeningWhileTheEngineRunsAndOnlyThenReturnsToIdle() async {
        let engine = FakeEngine(); engine.holdOpen = true; engine.updates = [update("hello")]
        let (c, log) = make { engine }
        c.start()
        await eventually("listening") { c.state == .listening }
        try? await Task.sleep(nanoseconds: 100_000_000)          // the old bug flipped to idle within a moment
        XCTAssertEqual(c.state, .listening, "must not fall back to idle while the engine is still running")
        XCTAssertFalse(log.states.contains(.idle))
        await c.stopAndWait()
        XCTAssertEqual(c.state, .idle)
        XCTAssertGreaterThanOrEqual(engine.stopCount, 1)
    }

    func testPressingStartRepeatedlyCreatesOnlyOneEngine() async {
        let engine = FakeEngine(); engine.holdOpen = true
        let (c, log) = make { engine }
        c.start(); c.start(); c.start()
        await eventually("listening") { c.state == .listening }
        c.start(); c.start()
        XCTAssertEqual(log.created, 1, "extra Start taps while a session exists must do nothing")
        await c.stopAndWait()
    }

    func testFailedStartReleasesTheEngineAndReportsTheFailure() async {
        let engine = FakeEngine(); engine.startError = Boom()
        let (c, _) = make { engine }
        c.start()
        await eventually("failed") { if case .failed = c.state { return true } else { return false } }
        XCTAssertGreaterThanOrEqual(engine.stopCount, 1, "a failed start must release what it opened")
    }

    func testTryAgainAfterAFailureUsesAFreshEngineAndWorks() async {
        var n = 0
        let (c, log) = make { n += 1; let e = FakeEngine(); if n == 1 { e.startError = Boom() } else { e.updates = [self.update("ok")] }; return e }
        c.start()
        await eventually("first fails") { if case .failed = c.state { return true } else { return false } }
        c.start()
        await eventually("second finishes") { c.state == .idle && log.updates == ["ok"] }
        XCTAssertEqual(log.created, 2)
    }

    func testStreamEndingNormallyCleansUpAndReturnsToIdle() async {
        let engine = FakeEngine(); engine.updates = [update("one"), update("two")]
        let (c, log) = make { engine }
        c.start()
        await eventually("idle after finishing") { c.state == .idle && log.updates.count == 2 }
        XCTAssertEqual(log.updates, ["one", "two"])
        XCTAssertGreaterThanOrEqual(engine.stopCount, 1)
        XCTAssertEqual(log.startup, "fake startup")
    }

    func testAnErrorMidSessionBecomesFailedAndCleansUp() async {
        let engine = FakeEngine(); engine.updates = [update("partial")]; engine.failAfterUpdates = Boom()
        let (c, log) = make { engine }
        c.start()
        await eventually("failed mid-session") { if case .failed = c.state { return true } else { return false } }
        XCTAssertEqual(log.updates, ["partial"])
        XCTAssertGreaterThanOrEqual(engine.stopCount, 1)
    }

    func testStopWhenNothingIsRunningIsHarmless() async {
        let (c, log) = make { FakeEngine() }
        await c.stopAndWait()
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(log.created, 0)
    }

    func testSoundLabelsAndSpeechBothArriveBeforeIdle() async {
        let engine = FakeEngine(); engine.updates = [update("a")]; engine.labels = [.knock, .laughter]
        let (c, log) = make { engine }
        c.start()
        await eventually("everything delivered") { c.state == .idle && log.labels.count == 2 && log.updates == ["a"] }
        XCTAssertEqual(log.labels, [.knock, .laughter])
    }

    func testAtMostOneEngineIsEverAliveAtATime() async {
        var alive = 0, peak = 0
        let (c, _) = make { alive += 1; peak = max(peak, alive); let e = FakeEngine(); e.startError = Boom(); return e }
        for _ in 0..<5 {
            c.start()
            await eventually("settled") { if case .failed = c.state { return true } else { return c.state == .idle } }
            alive -= 1                                              // the controller has cleaned up by now
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(peak, 1)
    }
}

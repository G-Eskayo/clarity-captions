import XCTest
@testable import CaptionCore

/// The captioning engine loads during the launch animation (#119, owner on #117: "The loading screen at the beginning
/// is supposed to cover the getting-ready"), so Start is instant. Loading never opens the microphone; a session takes
/// the loaded engine; anything nobody takes is freed again.
@MainActor
final class EngineWarmupTests: XCTestCase {

    final class FakeEngine: CaptioningEngine, @unchecked Sendable {
        var startupReport = ""
        var prepareCount = 0
        var stopCount = 0
        var startCount = 0
        var prepareError: Error?
        /// Steps reported while preparing.
        var steps = 3
        /// Holds prepare() until released, to observe the in-between state.
        var holdPrepare = false
        private var release: CheckedContinuation<Void, Never>?

        func prepare(onStep: @escaping @Sendable (Int) -> Void) async throws {
            prepareCount += 1
            for s in 1...steps { onStep(s) }
            if holdPrepare { await withCheckedContinuation { release = $0 } }
            if let prepareError { throw prepareError }
        }
        func finishPreparing() { release?.resume(); release = nil }
        func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
            startCount += 1
            return AsyncThrowingStream { $0.finish() }
        }
        func soundLabelsStream() -> AsyncStream<SoundLabelKind> { AsyncStream { $0.finish() } }
        func audioLevelStream() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
        func stop() async { stopCount += 1 }
    }

    struct Boom: Error {}

    private func eventually(_ what: String, timeout: Double = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertTrue(condition(), "timed out waiting for: \(what)")
    }

    private func make(_ engines: @escaping () -> FakeEngine) -> (EngineWarmup, () -> Int) {
        var made = 0
        let warmup = EngineWarmup(make: { made += 1; return engines() })
        return (warmup, { made })
    }

    func testPrepareLoadsOneEngineAndBecomesReady() async {
        let engine = FakeEngine()
        let (warmup, made) = make { engine }
        XCTAssertEqual(warmup.state, .idle)
        warmup.prepare()
        await eventually("ready") { warmup.state == .ready }
        XCTAssertEqual(made(), 1)
        XCTAssertEqual(engine.prepareCount, 1)
        XCTAssertEqual(engine.startCount, 0, "loading must never start the engine (the microphone stays closed)")
    }

    func testTheStateReportsEachLoadingStep() async {
        let engine = FakeEngine(); engine.holdPrepare = true
        let (warmup, _) = make { engine }
        var seen: [EngineWarmup.State] = []
        warmup.onChange = { seen.append($0) }
        warmup.prepare()
        await eventually("all steps reported") { warmup.state == .preparing(step: 3) }
        engine.finishPreparing()
        await eventually("ready") { warmup.state == .ready }
        XCTAssertEqual(seen.first, .preparing(step: 0))
        XCTAssertTrue(seen.contains(.preparing(step: 1)) && seen.contains(.preparing(step: 2)))
        XCTAssertEqual(seen.last, .ready)
    }

    func testPreparingTwiceNeverLoadsTwoEngines() async {
        let (warmup, made) = make { FakeEngine() }
        warmup.prepare(); warmup.prepare(); warmup.prepare()
        await eventually("ready") { warmup.state == .ready }
        warmup.prepare()
        XCTAssertEqual(made(), 1, "a loaded or loading engine is reused; speech recognizers are limited by the system")
    }

    func testTakeHandsOverTheLoadedEngineOnce() async {
        let engine = FakeEngine()
        let (warmup, _) = make { engine }
        warmup.prepare()
        await eventually("ready") { warmup.state == .ready }
        XCTAssertTrue(warmup.take() === engine)
        XCTAssertNil(warmup.take(), "the same engine is never handed to two sessions")
        XCTAssertEqual(warmup.state, .idle)
    }

    func testTakeWhileStillLoadingHandsOverTheSameEngine() async {
        let engine = FakeEngine(); engine.holdPrepare = true
        let (warmup, made) = make { engine }
        warmup.prepare()
        await eventually("loading") { warmup.state == .preparing(step: 3) }
        XCTAssertTrue(warmup.take() === engine, "Start during the launch takes the engine that's already loading")
        engine.finishPreparing()
        XCTAssertEqual(made(), 1)
        XCTAssertEqual(engine.stopCount, 0, "a taken engine belongs to the session; the warmup never stops it")
    }

    func testTakeWithNothingLoadedReturnsNil() {
        let (warmup, made) = make { FakeEngine() }
        XCTAssertNil(warmup.take())
        XCTAssertEqual(made(), 0)
    }

    func testAFailedLoadIsReleasedAndReportedNotHung() async {
        let engine = FakeEngine(); engine.prepareError = Boom()
        let (warmup, _) = make { engine }
        warmup.prepare()
        await eventually("failed") { warmup.state == .failed }
        XCTAssertEqual(engine.stopCount, 1, "a failed load frees whatever it opened")
        XCTAssertNil(warmup.take(), "a session then makes its own engine and reports the failure the normal way")
    }

    func testAFailingFactoryIsReportedAsFailed() async {
        let warmup = EngineWarmup(make: { throw Boom() })
        warmup.prepare()
        await eventually("failed") { warmup.state == .failed }
    }

    func testReleaseFreesALoadedEngineNobodyTook() async {
        let engine = FakeEngine()
        let (warmup, made) = make { engine }
        warmup.prepare()
        await eventually("ready") { warmup.state == .ready }
        await warmup.release()
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertEqual(warmup.state, .idle)
        warmup.prepare()
        await eventually("ready again") { warmup.state == .ready }
        XCTAssertEqual(made(), 2, "after a release the next prepare loads a fresh engine")
    }

    func testReleaseWhileLoadingStopsItAndALateFinishDoesNotResurrectIt() async {
        let engine = FakeEngine(); engine.holdPrepare = true
        let (warmup, _) = make { engine }
        warmup.prepare()
        await eventually("loading") { warmup.state == .preparing(step: 3) }
        await warmup.release()
        engine.finishPreparing()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(warmup.state, .idle, "a load that finishes after a release must not come back as ready")
        XCTAssertNil(warmup.take())
        XCTAssertEqual(engine.stopCount, 1)
    }

    func testReleaseAfterTakeLeavesTheSessionsEngineAlone() async {
        let engine = FakeEngine()
        let (warmup, _) = make { engine }
        warmup.prepare()
        await eventually("ready") { warmup.state == .ready }
        _ = warmup.take()
        await warmup.release()
        XCTAssertEqual(engine.stopCount, 0)
    }

    // MARK: the session uses it

    func testASessionStartedFromAWarmEngineDoesNotLoadAnother() async {
        let engine = FakeEngine()
        let (warmup, made) = make { engine }
        warmup.prepare()
        await eventually("ready") { warmup.state == .ready }
        var fresh = 0
        let controller = CaptionSessionController(makeEngine: {
            if let warm = warmup.take() { return warm }
            fresh += 1
            return FakeEngine()
        })
        controller.start()
        await eventually("ran") { engine.startCount == 1 }
        XCTAssertEqual(fresh, 0)
        XCTAssertEqual(made(), 1)
    }

    // MARK: the launch waits for it, but never forever

    func testTheLaunchIsReadyOnlyWhenSetupAndTheEngineAre() {
        XCTAssertFalse(LaunchReadiness.isReady(firstRunReady: false, warmup: .ready, waitedPastDance: 0))
        XCTAssertFalse(LaunchReadiness.isReady(firstRunReady: true, warmup: .preparing(step: 1), waitedPastDance: 0))
        XCTAssertTrue(LaunchReadiness.isReady(firstRunReady: true, warmup: .ready, waitedPastDance: 0))
    }

    func testAFailedOrSkippedLoadNeverHoldsTheLaunch() {
        XCTAssertTrue(LaunchReadiness.isReady(firstRunReady: true, warmup: .failed, waitedPastDance: 0),
                      "Start then loads the engine itself and shows any problem the normal way")
        XCTAssertTrue(LaunchReadiness.isReady(firstRunReady: true, warmup: .idle, waitedPastDance: 0),
                      "nothing to wait for when no load was started (first run still asking for the microphone, demo)")
    }

    func testASlowLoadStopsHoldingTheLaunchAfterTheCap() {
        XCTAssertFalse(LaunchReadiness.isReady(firstRunReady: true, warmup: .preparing(step: 2),
                                               waitedPastDance: LaunchReadiness.maxWaitPastDance - 0.1))
        XCTAssertTrue(LaunchReadiness.isReady(firstRunReady: true, warmup: .preparing(step: 2),
                                              waitedPastDance: LaunchReadiness.maxWaitPastDance),
                      "a hung load can't trap her on the launch screen; Start finishes the load")
    }

    func testTheBarFollowsTheEnginesRealSteps() {
        let start = LaunchProgress.engine(step: 0)
        XCTAssertEqual(start.fill, 0)
        XCTAssertEqual(start.pulse, 0...(1.0 / 3))
        let mid = LaunchProgress.engine(step: 2)
        XCTAssertEqual(mid.fill, 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(mid.pulse!.lowerBound, 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(LaunchProgress.engine(step: 3).fill, 1)
        XCTAssertNil(LaunchProgress.engine(step: 3).pulse)
        XCTAssertEqual(LaunchProgress.engine(step: 9).fill, 1, "never overfills")
    }
}

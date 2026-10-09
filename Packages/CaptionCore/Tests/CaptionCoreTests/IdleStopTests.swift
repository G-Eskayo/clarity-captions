import XCTest
@testable import CaptionCore

/// ADR 0019: captioning stops on its own after a stretch with no captioned speech (5 / 15 / 30 min / Never,
/// default 5), and the screen stays awake only while captioning. These try to break the quiet clock and the
/// screen-awake seam with clock jumps, long suspensions, failures, setting changes and rapid Start/Stop.
final class IdleStopClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    func testSettingPresetsAndDefault() {
        XCTAssertEqual(IdleStopSetting.allCases, [.fiveMinutes, .fifteenMinutes, .thirtyMinutes, .never])
        XCTAssertEqual(IdleStopSetting.default, .fiveMinutes, "Never must never be the default (ADR 0019)")
        XCTAssertEqual(IdleStopSetting.fiveMinutes.minutes, 5)
        XCTAssertEqual(IdleStopSetting.fifteenMinutes.minutes, 15)
        XCTAssertEqual(IdleStopSetting.thirtyMinutes.minutes, 30)
        XCTAssertNil(IdleStopSetting.never.minutes)
        for s in IdleStopSetting.allCases { XCTAssertFalse(s.title.isEmpty) }
    }

    func testStopsOnlyAfterTheFullQuietStretchFromStart() {
        var clock = IdleStopClock(setting: .fiveMinutes)
        clock.begin(at: at(0))
        XCTAssertFalse(clock.shouldStop(now: at(299)))
        XCTAssertTrue(clock.shouldStop(now: at(300)))
    }

    func testEveryCaptionedWordRestartsTheQuietStretch() {
        var clock = IdleStopClock(setting: .fiveMinutes)
        clock.begin(at: at(0))
        clock.recordSpeech(at: at(200))
        XCTAssertFalse(clock.shouldStop(now: at(300)), "counted from Start instead of the last speech")
        XCTAssertFalse(clock.shouldStop(now: at(499)))
        XCTAssertTrue(clock.shouldStop(now: at(500)))
    }

    func testNeverDoesNotStop() {
        var clock = IdleStopClock(setting: .never)
        clock.begin(at: at(0))
        XCTAssertFalse(clock.shouldStop(now: at(60 * 60 * 24)))
    }

    func testNotBegunNeverStops() {
        var clock = IdleStopClock(setting: .fiveMinutes)
        XCTAssertFalse(clock.shouldStop(now: at(10_000)))
    }

    func testClockJumpingBackwardsNeitherStopsNorLeavesATimerThatNeverFires() {
        var clock = IdleStopClock(setting: .fiveMinutes)
        clock.begin(at: at(1000))
        XCTAssertFalse(clock.shouldStop(now: at(0)), "a backwards jump must not stop captions")
        // The quiet stretch restarts from the jumped-to time, so it still fires 5 minutes later, not 5 + 1000 s.
        XCTAssertFalse(clock.shouldStop(now: at(299)))
        XCTAssertTrue(clock.shouldStop(now: at(300)))
    }

    func testResumingAfterALongSuspensionDoesNotStopInstantly() {
        var clock = IdleStopClock(setting: .fiveMinutes)
        clock.begin(at: at(0))
        clock.resumed(at: at(3600))          // app was suspended for an hour
        XCTAssertFalse(clock.shouldStop(now: at(3601)))
        XCTAssertTrue(clock.shouldStop(now: at(3900)))
    }

    func testChangingTheSettingAppliesImmediatelyAndRestartsTheQuietStretch() {
        var clock = IdleStopClock(setting: .thirtyMinutes)
        clock.begin(at: at(0))
        clock.change(to: .fiveMinutes, at: at(600))   // 10 quiet minutes already passed
        XCTAssertFalse(clock.shouldStop(now: at(600)), "must not stop while she is still in Settings")
        XCTAssertTrue(clock.shouldStop(now: at(900)))
        clock.change(to: .never, at: at(900))
        XCTAssertFalse(clock.shouldStop(now: at(100_000)))
    }

    func testChangingToTheSameSettingDoesNotRestartTheStretch() {
        var clock = IdleStopClock(setting: .fiveMinutes)
        clock.begin(at: at(0))
        clock.change(to: .fiveMinutes, at: at(299))
        XCTAssertTrue(clock.shouldStop(now: at(300)), "a no-op change (called every tick) must not postpone the stop forever")
    }
}

final class IdleStopStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "IdleStopStoreTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaultsToFiveMinutesWhenNothingSaved() {
        XCTAssertEqual(IdleStopStore(defaults: freshDefaults()).load(), .fiveMinutes)
    }

    func testRoundTrips() {
        let d = freshDefaults()
        for s in IdleStopSetting.allCases {
            IdleStopStore(defaults: d).save(s)
            XCTAssertEqual(IdleStopStore(defaults: d).load(), s)
        }
    }

    func testGarbageFallsBackToTheDefault() {
        let d = freshDefaults()
        d.set("forever", forKey: IdleStopStore.key)
        XCTAssertEqual(IdleStopStore(defaults: d).load(), .fiveMinutes)
        d.set(42, forKey: IdleStopStore.key)
        XCTAssertEqual(IdleStopStore(defaults: d).load(), .fiveMinutes)
    }
}

final class PausedQuietStateTests: XCTestCase {
    func testPausedQuietIsGentleAndOffersStartAgain() {
        let state = CaptionState.pausedQuiet(minutes: 5)
        XCTAssertEqual(PrimaryControl.for(state).action, .start)
        XCTAssertEqual(PrimaryControl.for(state).title, "Start again")
        XCTAssertEqual(StatusWords.headline(for: state), "Captions paused")
        XCTAssertNotEqual(StatusWords.headline(for: state), StatusWords.headline(for: .failed("x")), "not shown as an error")
        XCTAssertEqual(StatusWords.detail(for: state), "No one talked for 5 minutes")
        XCTAssertEqual(StatusWords.detail(for: .pausedQuiet(minutes: 30)), "No one talked for 30 minutes")
        XCTAssertEqual(StatusWords.announcement(for: state), "Captions paused. No one talked for 5 minutes")
    }

    func testPausedQuietSavesTheConversationLikeAnyOtherStop() {
        var stream = CaptionStream()
        stream.apply(text: "hello there", isFinal: true)
        let action = CaptionSessionLifecycle.action(for: .pausedQuiet(minutes: 5), sessionStartedAt: Date(), lines: stream.lines)
        if case .save = action {} else { XCTFail("an idle stop must still save the conversation, got \(action)") }
    }
}

@MainActor
final class ScreenAwakeKeeperTests: XCTestCase {
    func testPolicy() {
        XCTAssertTrue(ScreenAwakePolicy.keepAwake(state: .listening, appIsActive: true))
        XCTAssertTrue(ScreenAwakePolicy.keepAwake(state: .preparing, appIsActive: true))
        for s: CaptionState in [.idle, .failed("x"), .pausedQuiet(minutes: 5)] {
            XCTAssertFalse(ScreenAwakePolicy.keepAwake(state: s, appIsActive: true), "\(s)")
        }
        XCTAssertFalse(ScreenAwakePolicy.keepAwake(state: .listening, appIsActive: false))
    }

    private func keeper() -> (ScreenAwakeKeeper, () -> [Bool]) {
        var applied: [Bool] = []
        let k = ScreenAwakeKeeper(apply: { applied.append($0) })
        return (k, { applied })
    }

    func testAwakeWhileCaptioningRestoredOnStop() {
        let (k, applied) = keeper()
        k.update(state: .preparing); k.update(state: .listening); k.update(state: .idle)
        XCTAssertEqual(applied(), [true, false], "applies only on change, and restores on Stop")
    }

    func testRestoredOnIdleStopAndOnFailure() {
        let (k, applied) = keeper()
        k.update(state: .listening); k.update(state: .pausedQuiet(minutes: 5))
        k.update(state: .listening); k.update(state: .failed("mic busy"))
        XCTAssertEqual(applied(), [true, false, true, false])
    }

    func testRestoredWhenTheAppGoesToTheBackgroundAndReappliedOnReturn() {
        let (k, applied) = keeper()
        k.update(state: .listening)
        k.update(appIsActive: false)
        k.update(appIsActive: true)
        XCTAssertEqual(applied(), [true, false, true])
    }

    func testReturningToTheForegroundAfterStoppingDoesNotKeepTheScreenOn() {
        let (k, applied) = keeper()
        k.update(state: .listening); k.update(appIsActive: false); k.update(state: .idle); k.update(appIsActive: true)
        XCTAssertEqual(applied(), [true, false])
    }

    func testRapidStartStopEndsRestored() {
        let (k, applied) = keeper()
        for _ in 0..<20 { k.update(state: .preparing); k.update(state: .listening); k.update(state: .idle) }
        XCTAssertEqual(applied().last, false)
    }
}

/// The controller wires the clock into a real session: it records captioned speech itself and stops with
/// `.pausedQuiet` when `tick()` finds the stretch has passed.
@MainActor
final class CaptionSessionIdleStopTests: XCTestCase {
    final class Engine: CaptioningEngine, @unchecked Sendable {
        var startupReport = ""
        private(set) var stopCount = 0
        var failWith: Error?
        private var cont: AsyncThrowingStream<CaptionUpdate, Error>.Continuation?
        private var labelCont: AsyncStream<SoundLabelKind>.Continuation?
        private var levelCont: AsyncStream<Double>.Continuation?
        private var labels: AsyncStream<SoundLabelKind>?
        private var levels: AsyncStream<Double>?
        func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error> {
            let (s, c) = AsyncThrowingStream.makeStream(of: CaptionUpdate.self)
            cont = c
            (labels, labelCont) = AsyncStream.makeStream(of: SoundLabelKind.self)
            (levels, levelCont) = AsyncStream.makeStream(of: Double.self)
            return s
        }
        func emit(_ text: String) {
            cont?.yield(CaptionUpdate(text: text, isFinal: true, lagSeconds: nil, speaker: nil, startSeconds: nil, endSeconds: nil, diagnostics: "", wordEmphasis: []))
        }
        func fail(_ e: Error) { cont?.finish(throwing: e); labelCont?.finish(); levelCont?.finish() }
        func soundLabelsStream() -> AsyncStream<SoundLabelKind> { labels ?? AsyncStream { $0.finish() } }
        func audioLevelStream() -> AsyncStream<Double> { levels ?? AsyncStream { $0.finish() } }
        func stop() async { stopCount += 1; cont?.finish(); labelCont?.finish(); levelCont?.finish() }
    }
    struct Boom: Error {}

    final class Clock { var now = Date(timeIntervalSince1970: 1_000_000); func advance(_ s: Double) { now = now.addingTimeInterval(s) } }

    private func eventually(_ what: String, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition(), "timed out waiting for: \(what)")
    }

    private func make(setting: @escaping () -> IdleStopSetting = { .fiveMinutes }) -> (CaptionSessionController, Engine, Clock) {
        let engine = Engine(), clock = Clock()
        let c = CaptionSessionController(makeEngine: { engine }, now: { clock.now }, idleStopSetting: setting)
        return (c, engine, clock)
    }

    func testStopsWithPausedQuietAfterTheStretchAndReleasesTheEngine() async {
        let (c, engine, clock) = make()
        c.start()
        await eventually("listening") { c.state == .listening }
        clock.advance(299); c.tick()
        XCTAssertEqual(c.state, .listening)
        clock.advance(1); c.tick()
        await eventually("paused") { c.state == .pausedQuiet(minutes: 5) }
        XCTAssertGreaterThanOrEqual(engine.stopCount, 1)
    }

    func testCaptionedSpeechKeepsItRunningButBlankUpdatesDoNot() async {
        let (c, engine, clock) = make()
        c.start()
        await eventually("listening") { c.state == .listening }
        clock.advance(200); engine.emit("hello")
        try? await Task.sleep(nanoseconds: 50_000_000)
        clock.advance(200); c.tick()
        XCTAssertEqual(c.state, .listening, "speech 200 s ago must keep it running")
        engine.emit("   ")   // a blank update is not captioned speech (ADR 0019: count captioned speech, not sound)
        try? await Task.sleep(nanoseconds: 50_000_000)
        clock.advance(100); c.tick()
        await eventually("paused") { c.state == .pausedQuiet(minutes: 5) }
    }

    func testSettingIsReadEveryTickSoAChangeAppliesMidSession() async {
        var setting = IdleStopSetting.never
        let (c, _, clock) = make(setting: { setting })
        c.start()
        await eventually("listening") { c.state == .listening }
        clock.advance(3600); c.tick()
        XCTAssertEqual(c.state, .listening)
        setting = .fifteenMinutes
        c.tick()
        XCTAssertEqual(c.state, .listening, "switching mid-session restarts the stretch rather than stopping at once")
        clock.advance(900); c.tick()
        await eventually("paused") { c.state == .pausedQuiet(minutes: 15) }
    }

    func testResumedAfterLongSuspensionDoesNotStopInstantly() async {
        let (c, _, clock) = make()
        c.start()
        await eventually("listening") { c.state == .listening }
        clock.advance(3600); c.noteResumed(); c.tick()
        XCTAssertEqual(c.state, .listening)
    }

    func testTickWhenNotListeningDoesNothing() async {
        let (c, _, clock) = make()
        clock.advance(10_000); c.tick()
        XCTAssertEqual(c.state, .idle)
    }

    func testUserStopAfterAnIdleStopIsRequestedStillEndsPausedNotFailed() async {
        let (c, _, clock) = make()
        c.start()
        await eventually("listening") { c.state == .listening }
        clock.advance(300); c.tick(); c.stop()
        await eventually("ended") { c.state != .listening }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(c.state, .pausedQuiet(minutes: 5))
    }

    func testAFailureMidSessionIsStillAFailureAndTheNextSessionStartsClean() async {
        let (c, engine, clock) = make()
        c.start()
        await eventually("listening") { c.state == .listening }
        engine.fail(Boom())
        await eventually("failed") { if case .failed = c.state { return true } else { return false } }
        c.start()
        await eventually("listening again") { c.state == .listening }
        clock.advance(299); c.tick()
        XCTAssertEqual(c.state, .listening, "the quiet stretch restarts with each session")
        await c.stopAndWait()
        XCTAssertEqual(c.state, .idle, "a normal Stop after a fresh session is plain idle, not a stale pause")
    }

    func testDefaultControllerNeverIdleStops() async {
        let engine = Engine()
        let c = CaptionSessionController(makeEngine: { engine })
        c.start()
        await eventually("listening") { c.state == .listening }
        c.tick()
        XCTAssertEqual(c.state, .listening)
        await c.stopAndWait()
    }
}

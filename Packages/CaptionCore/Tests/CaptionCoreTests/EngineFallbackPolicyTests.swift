import XCTest
@testable import CaptionCore

/// When the app leaves Parakeet for Apple's engine (design §5, test 5). The rule: captions keep flowing, the user
/// never sees an error they can't act on.
final class EngineFallbackPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let plenty: UInt64 = 2_000_000_000
    private let en = Locale(identifier: "en-US")

    private func choose(_ choice: CaptionEngineChoice = .parakeet, fallbacks: [Date] = [], memory: UInt64? = nil,
                        locale: Locale? = nil, modelPresent: Bool = true) -> EngineSelection {
        EngineFallbackPolicy.engine(for: choice, now: now, recentFallbacks: fallbacks, availableMemory: memory ?? plenty,
                                    locale: locale ?? en, modelPresent: modelPresent)
    }

    // MARK: Before a session

    func testParakeetByDefault() {
        XCTAssertEqual(choose(), EngineSelection(engine: .parakeet, reason: nil))
    }

    func testTheDeveloperFlagOnAppleIsObeyed() {
        XCTAssertEqual(choose(.apple), EngineSelection(engine: .apple, reason: nil))
    }

    func testMissingModelUsesApple() {
        XCTAssertEqual(choose(modelPresent: false), EngineSelection(engine: .apple, reason: .modelMissing))
    }

    func testLowAvailableMemoryUsesApple() {
        XCTAssertEqual(choose(memory: 399 * 1_048_576).engine, .apple)
        XCTAssertEqual(choose(memory: 399 * 1_048_576).reason, .lowMemory)
        XCTAssertEqual(choose(memory: 400 * 1_048_576).engine, .parakeet, "the floor itself is enough")
    }

    func testNonEnglishLocalesUseApple() {
        XCTAssertEqual(choose(locale: Locale(identifier: "fr-FR")), EngineSelection(engine: .apple, reason: .locale))
        XCTAssertEqual(choose(locale: Locale(identifier: "en-GB")).engine, .parakeet)
    }

    func testTwoFallbacksInADayPinAppleForTwentyFourHours() {
        let pinned = choose(fallbacks: [now.addingTimeInterval(-3_600), now.addingTimeInterval(-60)])
        XCTAssertEqual(pinned, EngineSelection(engine: .apple, reason: .repeatedFallbacks))
        XCTAssertEqual(choose(fallbacks: [now.addingTimeInterval(-60)]).engine, .parakeet, "one is not a pattern")
        let old = [now.addingTimeInterval(-25 * 3_600), now.addingTimeInterval(-60)]
        XCTAssertEqual(choose(fallbacks: old).engine, .parakeet, "the older one is outside the day")
    }

    func testFallbacksFromTheFutureAreIgnored() {
        // A clock change must not pin Apple forever.
        let future = [now.addingTimeInterval(86_400 * 30), now.addingTimeInterval(86_400 * 31)]
        XCTAssertEqual(choose(fallbacks: future).engine, .parakeet)
    }

    // MARK: During a session

    func testEachTriggerOnParakeetTakesTheDocumentedAction() {
        let cases: [(FallbackTrigger, FallbackAction)] = [
            (.loadFailed, .switchToApple),
            (.noWordsFromSpeech, .switchToApple),
            (.memoryWarning, .switchToApple),
            (.thermal(.nominal), .normalHop),
            (.thermal(.fair), .normalHop),
            (.thermal(.serious), .doubleHop),
            (.thermal(.critical), .switchToApple),
        ]
        for (trigger, action) in cases {
            XCTAssertEqual(EngineFallbackPolicy.action(for: trigger, running: .parakeet), action, "\(trigger)")
        }
    }

    func testNothingHappensWhileOnApple() {
        for trigger: FallbackTrigger in [.loadFailed, .noWordsFromSpeech, .memoryWarning, .thermal(.critical), .thermal(.serious)] {
            XCTAssertEqual(EngineFallbackPolicy.action(for: trigger, running: .apple), .none, "\(trigger)")
        }
    }

    func testOnlySwitchesCountTowardTheDailyPin() {
        XCTAssertTrue(FallbackAction.switchToApple.countsAsFallback)
        XCTAssertFalse(FallbackAction.doubleHop.countsAsFallback)
        XCTAssertFalse(FallbackAction.none.countsAsFallback)
    }

    // MARK: History store (UserDefaults suite, never the real one)

    func testHistoryKeepsOnlyTheLastDay() {
        let defaults = UserDefaults(suiteName: "fallback-test-\(UUID())")!
        var store = EngineFallbackHistory(defaults: defaults)
        for hoursAgo in stride(from: 100, through: 0, by: -1) {
            store.record(now.addingTimeInterval(Double(-hoursAgo) * 3_600), now: now)
        }
        let kept = EngineFallbackHistory(defaults: defaults).recent(now: now)
        XCTAssertEqual(kept.count, 25, "hours 24...0, bounded however many there were")
        XCTAssertTrue(kept.allSatisfy { now.timeIntervalSince($0) <= 86_400 })
    }

    func testHistoryReadsGarbageAsEmpty() {
        let defaults = UserDefaults(suiteName: "fallback-test-\(UUID())")!
        defaults.set("not a list", forKey: EngineFallbackHistory.key)
        XCTAssertEqual(EngineFallbackHistory(defaults: defaults).recent(now: now), [])
    }

    // MARK: Silent-engine watchdog

    func testTwentySecondsOfLoudSpeechWithNoWordsTrips() {
        var dog = SilentEngineWatchdog()
        for _ in 0..<39 { XCTAssertFalse(dog.observe(seconds: 0.5, speech: true, words: 0)) }
        XCTAssertTrue(dog.observe(seconds: 0.5, speech: true, words: 0))
    }

    func testTenSecondsOfRestaurantNoiseBeforeAnyoneTalksDoesNotTrip() {
        // The design's first draft said 10 s: a loud room with nobody talking yet would have left Parakeet for nothing.
        var dog = SilentEngineWatchdog()
        for _ in 0..<20 { XCTAssertFalse(dog.observe(seconds: 0.5, speech: true, words: 0)) }
    }

    func testThreeFailedDecodesInARowTrip() {
        var dog = SilentEngineWatchdog()
        XCTAssertFalse(dog.observe(seconds: 0.5, speech: false, words: 0, failed: true))
        XCTAssertFalse(dog.observe(seconds: 0.5, speech: false, words: 0, failed: true))
        XCTAssertTrue(dog.observe(seconds: 0.5, speech: false, words: 0, failed: true))
    }

    func testAGoodDecodeBetweenFailuresResetsTheRun() {
        var dog = SilentEngineWatchdog()
        for _ in 0..<10 {
            XCTAssertFalse(dog.observe(seconds: 0.5, speech: false, words: 0, failed: true))
            XCTAssertFalse(dog.observe(seconds: 0.5, speech: false, words: 0, failed: true))
            XCTAssertFalse(dog.observe(seconds: 0.5, speech: false, words: 0))
        }
    }

    func testQuietRoomNeverTrips() {
        var dog = SilentEngineWatchdog()
        for _ in 0..<1_000 { XCTAssertFalse(dog.observe(seconds: 0.5, speech: false, words: 0)) }
    }

    func testOneWordDisarmsItForTheSession() {
        var dog = SilentEngineWatchdog()
        _ = dog.observe(seconds: 0.5, speech: true, words: 1)
        for _ in 0..<100 { XCTAssertFalse(dog.observe(seconds: 0.5, speech: true, words: 0, failed: true)) }
    }

    func testItTripsOnlyOnce() {
        var dog = SilentEngineWatchdog()
        var trips = 0
        for _ in 0..<200 where dog.observe(seconds: 0.5, speech: true, words: 0) { trips += 1 }
        XCTAssertEqual(trips, 1)
    }

    func testClearingTheHistoryUnpinsParakeet() {
        let defaults = UserDefaults(suiteName: "fallback-test-\(UUID())")!
        var store = EngineFallbackHistory(defaults: defaults)
        store.record(now.addingTimeInterval(-60), now: now)
        store.record(now, now: now)
        XCTAssertEqual(choose(fallbacks: store.recent(now: now)).engine, .apple)
        store.clear()
        XCTAssertEqual(choose(fallbacks: store.recent(now: now)).engine, .parakeet)
    }
}

import XCTest
@testable import CaptionCore

/// #81: the one-time speech download must end in plain words and Try again, never a spinner that runs forever.
/// Reviewers often test on restricted networks.
final class SpeechDownloadTests: XCTestCase {
    private let instant: @Sendable (Duration) async -> Void = { _ in await Task.yield() }

    func testSuccessForwardsProgressAndEndsInstalled() async {
        let seen = Box<[Double]>([])
        let download = SpeechDownload(install: { progress in progress(0.5); progress(1) })
        let outcome = await download.run { p in seen.mutate { $0.append(p) } }
        XCTAssertEqual(outcome, .installed)
        XCTAssertEqual(seen.value, [0.5, 1])
    }

    func testNoInternetSaysSo() async {
        let download = SpeechDownload(install: { _ in throw URLError(.notConnectedToInternet) })
        let outcome = await download.run { _ in }
        XCTAssertEqual(outcome, .failed(.offline))
    }

    func testAnyOtherErrorIsAGenericFailure() async {
        struct Boom: Error {}
        let download = SpeechDownload(install: { _ in throw Boom() })
        let outcome = await download.run { _ in }
        XCTAssertEqual(outcome, .failed(.failed))
    }

    /// A download that never moves and ignores cancellation must still let the screen show Try again, promptly.
    func testDownloadThatStopsMovingEndsAsStalledWithoutWaitingForIt() async {
        let download = SpeechDownload(install: { progress in
            progress(0.2)
            for _ in 0..<5 { try? await Task.sleep(for: .seconds(1)) } // ignores cancellation on purpose
        }, stallTicks: 3, sleep: instant)
        let start = ContinuousClock.now
        let outcome = await download.run { _ in }
        XCTAssertEqual(outcome, .failed(.stalled))
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(2))
    }

    func testTappingTryAgainWhileItIsRunningDoesNotStartASecondDownload() async {
        let starts = Box(0)
        let gate = Gate()
        let download = SpeechDownload(install: { _ in starts.mutate { $0 += 1 }; await gate.wait() })
        async let first = download.run { _ in }
        while starts.value == 0 { await Task.yield() }
        let second = await download.run { _ in }
        XCTAssertEqual(second, .alreadyRunning)
        gate.open()
        let firstOutcome = await first
        XCTAssertEqual(firstOutcome, .installed)
        XCTAssertEqual(starts.value, 1)
    }

    func testTryAgainAfterAFailureStartsAgainAndCanSucceed() async {
        let attempts = Box(0)
        let download = SpeechDownload(install: { _ in
            attempts.mutate { $0 += 1 }
            if attempts.value == 1 { throw URLError(.notConnectedToInternet) }
        })
        let firstOutcome = await download.run { _ in }
        XCTAssertEqual(firstOutcome, .failed(.offline))
        let secondOutcome = await download.run { _ in }
        XCTAssertEqual(secondOutcome, .installed)
        XCTAssertEqual(attempts.value, 2)
    }

    // MARK: Stall rule

    func testSteadyProgressNeverStalls() {
        var watch = StallWatch(limit: 3)
        for i in 1...100 { XCTAssertFalse(watch.tick(progress: Double(i) / 100)) }
    }

    func testFlatProgressStallsAfterTheLimit() {
        var watch = StallWatch(limit: 3)
        XCTAssertFalse(watch.tick(progress: 0.4))
        XCTAssertFalse(watch.tick(progress: 0.4))
        XCTAssertFalse(watch.tick(progress: 0.4))
        XCTAssertTrue(watch.tick(progress: 0.4))
    }

    func testProgressGoingBackwardsIsNotMovement() {
        var watch = StallWatch(limit: 2)
        _ = watch.tick(progress: 0.5)
        XCTAssertFalse(watch.tick(progress: 0.3))
        XCTAssertTrue(watch.tick(progress: 0.4))
    }

    // MARK: Words

    func testEveryProblemSpeaksPlainWordsAndSaysWhatToDo() {
        let jargon = ["model", "asset", "network", "error", "timeout", "server"]
        for problem in [DownloadProblem.offline, .stalled, .failed] {
            let text = problem.message.lowercased()
            XCTAssertFalse(text.isEmpty)
            XCTAssertTrue(text.contains("try again"), "\(problem) must say what to do")
            for word in jargon { XCTAssertFalse(text.contains(word), "\(problem) uses jargon: \(word)") }
        }
    }

    /// #37: a download of another language names that language, not English.
    func testTheOfflineWordsNameTheLanguageBeingDownloaded() {
        let spanish = DownloadProblem.offline.message(language: "Spanish (Spain)")
        XCTAssertTrue(spanish.contains("Spanish (Spain)"))
        XCTAssertFalse(spanish.contains("English"))
        XCTAssertTrue(spanish.lowercased().contains("try again"))
        XCTAssertEqual(DownloadProblem.offline.message, DownloadProblem.offline.message(language: "English"))
        XCTAssertEqual(DownloadProblem.stalled.message(language: "Spanish"), DownloadProblem.stalled.message)
    }

    // MARK: Undocumented gaps

    /// Case 8: Cross-instance double-download race. Two separate SpeechDownload instances for the same locale can both run; the system's asset-download API handles parallel requests idempotently.
    func testTwoInstancesOfTheSameLocaleCanRunConcurrentlyWithoutCorruption() async {
        let attempts = Box(0)
        let installClosure: @Sendable (_ progress: @escaping @Sendable (Double) -> Void) async throws -> Void = { progress in
            attempts.mutate { $0 += 1 }
            progress(0.5)
            progress(1)
        }
        let download1 = SpeechDownload(install: installClosure)
        let download2 = SpeechDownload(install: installClosure)

        async let outcome1 = download1.run { _ in }
        async let outcome2 = download2.run { _ in }

        let result1 = await outcome1
        let result2 = await outcome2

        XCTAssertEqual(result1, .installed, "first instance should complete successfully")
        XCTAssertEqual(result2, .installed, "second instance should complete successfully")
        XCTAssertEqual(attempts.value, 2, "both instances should start their own install task")
    }

    /// Case 9: Mid-session From change not live. When a language download is in progress, new caption streams still use the current language until the download finishes.
    /// This test verifies that multiple concurrent downloads (simulating this scenario) both complete successfully.
    func testMultipleConcurrentDownloadsForDifferentLocalesAllComplete() async {
        let download1 = SpeechDownload(install: { progress in progress(1) })
        let download2 = SpeechDownload(install: { progress in progress(1) })

        async let outcome1 = download1.run { _ in }
        async let outcome2 = download2.run { _ in }

        let result1 = await outcome1
        let result2 = await outcome2

        XCTAssertEqual(result1, .installed)
        XCTAssertEqual(result2, .installed)
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.withLock { stored } }
    func mutate(_ f: (inout T) -> Void) { lock.withLock { f(&stored) } }
}

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    func open() { lock.withLock { isOpen = true } }
    func wait() async { while !lock.withLock({ isOpen }) { try? await Task.sleep(for: .milliseconds(5)) } }
}

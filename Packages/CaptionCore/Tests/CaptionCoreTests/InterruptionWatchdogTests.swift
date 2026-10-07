import XCTest
@testable import CaptionCore

final class InterruptionWatchdogTests: XCTestCase {
    func testResumeBeforeTimeoutReturnsResumed() async {
        let watchdog = InterruptionWatchdog(timeoutSeconds: 1)

        let task = Task {
            await watchdog.wait()
        }

        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        let resumeResult = await watchdog.resume()
        XCTAssertEqual(resumeResult, .resumed)

        let waitResult = await task.value
        XCTAssertEqual(waitResult, .resumed)
    }

    func testTimeoutWithoutResumeReturnsTimedOut() async {
        let watchdog = InterruptionWatchdog(timeoutSeconds: 0.2) // 200ms

        let result = await watchdog.wait()
        XCTAssertEqual(result, .timedOut)
    }

    func testMultipleResumesConsistentlyReturnResumed() async {
        let watchdog = InterruptionWatchdog(timeoutSeconds: 1)

        let r1 = await watchdog.resume()
        XCTAssertEqual(r1, .resumed)

        let r2 = await watchdog.resume()
        XCTAssertEqual(r2, .resumed)

        let waitResult = await watchdog.wait()
        XCTAssertEqual(waitResult, .resumed)
    }

    func testResumeAfterTimeoutHasElapsedStillReturnResumed() async {
        let watchdog = InterruptionWatchdog(timeoutSeconds: 0.1) // 100ms

        let waitResult = await watchdog.wait()
        XCTAssertEqual(waitResult, .timedOut)

        let resumeResult = await watchdog.resume()
        XCTAssertEqual(resumeResult, .resumed)
    }
}

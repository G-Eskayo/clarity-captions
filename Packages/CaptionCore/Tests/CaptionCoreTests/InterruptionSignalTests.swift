import XCTest
@testable import CaptionCore

final class InterruptionSignalTests: XCTestCase {
    func testPausedEquality() {
        let reason = "Something else is using the microphone"
        let signal1 = InterruptionSignal.paused(reason)
        let signal2 = InterruptionSignal.paused(reason)
        XCTAssertEqual(signal1, signal2)
    }

    func testResumedEquality() {
        let signal1 = InterruptionSignal.resumed
        let signal2 = InterruptionSignal.resumed
        XCTAssertEqual(signal1, signal2)
    }

    func testPausedAndResumedAreNotEqual() {
        let paused = InterruptionSignal.paused("Something else is using the microphone")
        let resumed = InterruptionSignal.resumed
        XCTAssertNotEqual(paused, resumed)
    }

    func testDifferentReasonsPausedAreNotEqual() {
        let signal1 = InterruptionSignal.paused("Reason 1")
        let signal2 = InterruptionSignal.paused("Reason 2")
        XCTAssertNotEqual(signal1, signal2)
    }

    func testCodability() {
        let signal = InterruptionSignal.paused("Something else is using the microphone")
        let sendable: InterruptionSignal = signal
        _ = sendable
    }
}

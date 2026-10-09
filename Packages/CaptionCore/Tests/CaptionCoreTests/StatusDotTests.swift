import XCTest
@testable import CaptionCore

final class StatusDotTests: XCTestCase {
    func testPulsingWithLevelWhenActivelyListening() {
        let dot = StatusDot.select(state: .listening, activity: .activelyListening, roomLevelDBFS: -25)
        if case .pulsing(let level) = dot {
            XCTAssertEqual(level, -25, accuracy: 0.01)
        } else {
            XCTFail("Expected pulsing dot, got \(dot)")
        }
    }

    func testPulsingWithLevelWhenNoOneTalking() {
        let dot = StatusDot.select(state: .listening, activity: .noOneTalking, roomLevelDBFS: -35)
        if case .pulsing(let level) = dot {
            XCTAssertEqual(level, -35, accuracy: 0.01)
        } else {
            XCTFail("Expected pulsing dot, got \(dot)")
        }
    }

    func testFlatAmberWhenCantHear() {
        let dot = StatusDot.select(state: .listening, activity: .cantHearAnything, roomLevelDBFS: -60)
        XCTAssertEqual(dot, .flatAmber)
    }

    func testHiddenWhenIdle() {
        let dot = StatusDot.select(state: .idle, activity: nil, roomLevelDBFS: nil)
        XCTAssertEqual(dot, .hidden)
    }

    func testHiddenWhenPreparing() {
        let dot = StatusDot.select(state: .preparing, activity: nil, roomLevelDBFS: -30)
        XCTAssertEqual(dot, .hidden)
    }

    func testHiddenWhenFailed() {
        let dot = StatusDot.select(state: .failed("test"), activity: nil, roomLevelDBFS: nil)
        XCTAssertEqual(dot, .hidden)
    }

    func testHiddenWhenPaused() {
        let dot = StatusDot.select(state: .paused("Something"), activity: nil, roomLevelDBFS: -30)
        XCTAssertEqual(dot, .hidden)
    }

    func testPulsingWithNilLevelWhenNoOneTalking() {
        let dot = StatusDot.select(state: .listening, activity: .noOneTalking, roomLevelDBFS: nil)
        if case .pulsing(let level) = dot {
            XCTAssertEqual(level, -60, accuracy: 0.01)
        } else {
            XCTFail("Expected pulsing dot with -60 fallback, got \(dot)")
        }
    }
}

import XCTest
@testable import CaptionCore

/// How often Parakeet decodes (design §2 "Adaptive hop", D7: start at 0.5 s).
final class AdaptiveHopTests: XCTestCase {
    func testStartsAtHalfASecondWithNoHistory() {
        XCTAssertEqual(AdaptiveHop.next(decodeTimes: [], thermal: .nominal), 0.5)
    }

    func testFastDecodesStayAtTheFloor() {
        XCTAssertEqual(AdaptiveHop.next(decodeTimes: [0.1, 0.12, 0.15], thermal: .nominal), 0.5)
    }

    func testSlowDecodesStretchTheHopToOnePointThreeTimesTheMedian() {
        XCTAssertEqual(AdaptiveHop.next(decodeTimes: [0.8, 0.8, 0.8], thermal: .fair), 1.04, accuracy: 1e-9)
    }

    func testClampsAtOneAndAHalfSeconds() {
        XCTAssertEqual(AdaptiveHop.next(decodeTimes: [3, 4, 5], thermal: .nominal), 1.5)
    }

    func testOneOutlierDoesNotMoveIt() {
        XCTAssertEqual(AdaptiveHop.next(decodeTimes: [0.1, 0.1, 5.0, 0.1, 0.1], thermal: .nominal), 0.5)
    }

    func testOnlyTheLastFiveDecodesCount() {
        XCTAssertEqual(AdaptiveHop.next(decodeTimes: [2, 2, 2, 2, 2, 0.1, 0.1, 0.1, 0.1, 0.1], thermal: .nominal), 0.5)
    }

    func testSeriousHeatDoublesItAfterTheClamp() {
        XCTAssertEqual(AdaptiveHop.next(decodeTimes: [], thermal: .serious), 1.0)
        XCTAssertEqual(AdaptiveHop.next(decodeTimes: [5], thermal: .serious), 3.0)
    }

    func testNonsenseTimesNeverGiveANonsenseHop() {
        for times in [[-1.0], [.nan], [.infinity], [0]] {
            let hop = AdaptiveHop.next(decodeTimes: times, thermal: .nominal)
            XCTAssertTrue((0.5...1.5).contains(hop), "\(times) gave \(hop)")
        }
    }
}

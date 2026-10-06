import XCTest
@testable import CaptionCore

final class LoudnessBaselineTests: XCTestCase {
    func testMedianIsNilUntilWarmup() {
        var baseline = LoudnessBaseline()
        for i in 0..<7 {
            baseline.update(Double(i))
        }
        XCTAssertNil(baseline.median, "Baseline needs 8 samples to be warm")
    }

    func testMedianBecomesAvailableAtWarmup() {
        var baseline = LoudnessBaseline()
        for i in 0..<8 {
            baseline.update(Double(i))
        }
        XCTAssertNotNil(baseline.median)
    }

    func testMedianOfOddCount() {
        var baseline = LoudnessBaseline()
        baseline.update(-20)
        baseline.update(-10)
        baseline.update(0)
        baseline.update(10)
        baseline.update(20)
        baseline.update(30)
        baseline.update(40)
        baseline.update(50)
        baseline.update(60)
        let median = baseline.median!
        XCTAssertEqual(median, 20, accuracy: 0.01)
    }

    func testMedianOfEvenCount() {
        var baseline = LoudnessBaseline()
        baseline.update(10)
        baseline.update(20)
        baseline.update(30)
        baseline.update(40)
        baseline.update(50)
        baseline.update(60)
        baseline.update(70)
        baseline.update(80)
        let median = baseline.median!
        XCTAssertEqual(median, 45, accuracy: 0.01)
    }

    func testSizeCapAvoidsInfiniteGrowth() {
        var baseline = LoudnessBaseline()
        for i in 0..<40 {
            baseline.update(Double(i))
        }
        let median1 = baseline.median!
        baseline.update(100)
        let median2 = baseline.median!
        XCTAssertNotEqual(median1, median2, "Median should update when new samples come in")
    }

    func testReset() {
        var baseline = LoudnessBaseline()
        for i in 0..<10 {
            baseline.update(Double(i))
        }
        XCTAssertNotNil(baseline.median)
        baseline.reset()
        XCTAssertNil(baseline.median)
    }
}

final class EmphasisMapperTests: XCTestCase {
    func testNormalWhenBaselineIsNil() {
        let emphasis = EmphasisMapper.level(wordDBFS: 0, baseline: nil)
        XCTAssertEqual(emphasis, .normal)
    }

    func testNormalWhenWordIsQuietRelativeToBaseline() {
        let emphasis = EmphasisMapper.level(wordDBFS: -10, baseline: -10)
        XCTAssertEqual(emphasis, .normal)
    }

    func testLoudWhenWordExceedsBaselineByThreshold() {
        let emphasis = EmphasisMapper.level(wordDBFS: 0, baseline: -10)
        XCTAssertEqual(emphasis, .loud, "10 dB above baseline should be loud")
    }

    func testBoundaryJustBelow() {
        let emphasis = EmphasisMapper.level(wordDBFS: -2.01, baseline: -10)
        XCTAssertEqual(emphasis, .normal, "7.99 dB above baseline is still normal")
    }

    func testBoundaryJustAbove() {
        let emphasis = EmphasisMapper.level(wordDBFS: -1.99, baseline: -10)
        XCTAssertEqual(emphasis, .loud, "8 dB+ above baseline is loud")
    }
}

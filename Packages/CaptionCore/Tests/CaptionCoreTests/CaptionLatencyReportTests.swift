import XCTest
@testable import CaptionCore

final class CaptionLatencyReportTests: XCTestCase {
    // MARK: - Percentile calculation

    func testMedianOfOddCount() {
        let samples = [0.1, 0.2, 0.3, 0.4, 0.5]
        let report = CaptionLatencyReport(lagSamples: samples)
        XCTAssertEqual(report.medianLagSeconds, 0.3)
    }

    func testMedianOfEvenCount() {
        let samples = [0.1, 0.2, 0.3, 0.4]
        let report = CaptionLatencyReport(lagSamples: samples)
        // Nearest-rank median: ceil(4 * 0.5) - 1 = 1, so element at index 1 = 0.2
        XCTAssertEqual(report.medianLagSeconds, 0.2)
    }

    func testMedianOfSingleElement() {
        let samples = [0.5]
        let report = CaptionLatencyReport(lagSamples: samples)
        XCTAssertEqual(report.medianLagSeconds, 0.5)
    }

    func testMedianOfEmptyArray() {
        let samples: [Double] = []
        let report = CaptionLatencyReport(lagSamples: samples)
        XCTAssertEqual(report.medianLagSeconds, 0.0)
    }

    func testP95Percentile() {
        let samples = stride(from: 0.01, through: 0.20, by: 0.01).map { $0 }
        let report = CaptionLatencyReport(lagSamples: samples)
        XCTAssertGreaterThanOrEqual(report.p95LagSeconds, 0.19)
    }

    func testP95OfSmallArray() {
        let samples = [0.1, 0.2, 0.3, 0.4]
        let report = CaptionLatencyReport(lagSamples: samples)
        // ceil(4 * 0.95) = 4, so index 3 = 0.4
        XCTAssertEqual(report.p95LagSeconds, 0.4)
    }

    // MARK: - Time to first caption

    func testTimeToFirstCaptionIsStored() {
        let samples = [0.1, 0.2]
        let report = CaptionLatencyReport(lagSamples: samples, timeToFirstCaption: 0.05)
        XCTAssertEqual(report.timeToFirstCaptionSeconds, 0.05)
    }

    func testTimeToFirstCaptionNilByDefault() {
        let samples = [0.1, 0.2]
        let report = CaptionLatencyReport(lagSamples: samples)
        XCTAssertNil(report.timeToFirstCaptionSeconds)
    }

    // MARK: - Regression status

    func testRegressionStatusOkWhenWithinBudget() {
        let baseline = CaptionLatencyBaseline(
            device: "Mac mini",
            os: "macOS 14.6",
            date: "2026-10-05",
            medianLagSeconds: 0.200,
            p95LagSeconds: 0.300
        )
        let report = CaptionLatencyReport(lagSamples: [0.200, 0.210])
        let status = report.regressionStatus(against: baseline)

        if case .ok = status {
            XCTAssert(true)
        } else {
            XCTFail("Expected .ok, got \(status)")
        }
    }

    func testRegressionStatusMedianFailure() {
        let baseline = CaptionLatencyBaseline(
            device: "Mac mini",
            os: "macOS 14.6",
            date: "2026-10-05",
            medianLagSeconds: 0.200,
            p95LagSeconds: 0.300
        )
        // 0.225 is 12.5% above 0.200, exceeding 10% budget
        let report = CaptionLatencyReport(lagSamples: [0.225, 0.230])
        let status = report.regressionStatus(against: baseline)

        if case .medianFailure(let measured, let budget, let baselineVal) = status {
            XCTAssertEqual(measured, 0.225, accuracy: 0.001)
            XCTAssertEqual(budget, 0.220, accuracy: 0.001)
            XCTAssertEqual(baselineVal, 0.200, accuracy: 0.001)
        } else {
            XCTFail("Expected .medianFailure, got \(status)")
        }
    }

    func testRegressionStatusP95Warning() {
        let baseline = CaptionLatencyBaseline(
            device: "Mac mini",
            os: "macOS 14.6",
            date: "2026-10-05",
            medianLagSeconds: 0.200,
            p95LagSeconds: 0.300
        )
        // Median is ok, but p95 is 11% above budget
        let samples = [0.200, 0.200, 0.200, 0.200, 0.335]
        let report = CaptionLatencyReport(lagSamples: samples)
        let status = report.regressionStatus(against: baseline)

        if case .p95Warning(let measured, let budget, let baselineVal) = status {
            XCTAssertGreaterThan(measured, budget)
            XCTAssertEqual(baselineVal, 0.300, accuracy: 0.001)
        } else {
            XCTFail("Expected .p95Warning, got \(status)")
        }
    }

    func testRegressionStatusMedianFailureTakesPrecedence() {
        let baseline = CaptionLatencyBaseline(
            device: "Mac mini",
            os: "macOS 14.6",
            date: "2026-10-05",
            medianLagSeconds: 0.200,
            p95LagSeconds: 0.300
        )
        // Both median and p95 exceed budget; failure takes precedence
        let report = CaptionLatencyReport(lagSamples: [0.225, 0.340])
        let status = report.regressionStatus(against: baseline)

        if case .medianFailure = status {
            XCTAssert(true)
        } else {
            XCTFail("Expected .medianFailure to take precedence, got \(status)")
        }
    }
}

final class CaptionLatencyBaselineTests: XCTestCase {
    func testParseValidMarkdownTable() {
        let markdown = """
        # Caption Latency Baseline

        | Device | OS | Date | Median | P95 | Time-to-First |
        |--------|----|----|--------|-----|----------------|
        | Mac mini (M1) | macOS 14.6 | 2026-10-05 | 0.200 | 0.300 | 0.050 |
        """

        guard let baseline = CaptionLatencyBaseline.parse(markdown: markdown) else {
            XCTFail("Failed to parse baseline")
            return
        }
        XCTAssertEqual(baseline.device, "Mac mini (M1)")
        XCTAssertEqual(baseline.os, "macOS 14.6")
        XCTAssertEqual(baseline.medianLagSeconds, 0.200, accuracy: 0.001)
        XCTAssertEqual(baseline.p95LagSeconds, 0.300, accuracy: 0.001)
        guard let ttf = baseline.timeToFirstCaptionSeconds else {
            XCTFail("timeToFirstCaptionSeconds should not be nil")
            return
        }
        XCTAssertEqual(ttf, 0.050, accuracy: 0.001)
    }

    func testParseTableWithSecondsUnit() {
        let markdown = """
        | Device | OS | Date | Median | P95 | Time-to-First |
        |--------|----|----|--------|-----|----------------|
        | Mac mini | macOS 14.6 | 2026-10-05 | 0.200 s | 0.300 s | 0.050 s |
        """

        guard let baseline = CaptionLatencyBaseline.parse(markdown: markdown) else {
            XCTFail("Failed to parse baseline")
            return
        }
        XCTAssertEqual(baseline.medianLagSeconds, 0.200, accuracy: 0.001)
        XCTAssertEqual(baseline.p95LagSeconds, 0.300, accuracy: 0.001)
    }

    func testParseIgnoresTBDPlaceholders() {
        let markdown = """
        | Device | OS | Date | Median | P95 | Time-to-First |
        |--------|----|----|--------|-----|----------------|
        | Mac mini | macOS 14.6 | TBD | TBD | TBD | TBD |
        """

        let baseline = CaptionLatencyBaseline.parse(markdown: markdown)
        XCTAssertNil(baseline)
    }

    func testParseMultipleRowsPicksFirst() {
        let markdown = """
        | Device | OS | Date | Median | P95 | Time-to-First |
        |--------|----|----|--------|-----|----------------|
        | Mac mini | macOS 14.6 | 2026-10-05 | 0.200 | 0.300 | 0.050 |
        | iPhone 15 | iOS 18 | 2026-10-05 | 0.180 | 0.280 | 0.040 |
        """

        guard let baseline = CaptionLatencyBaseline.parse(markdown: markdown) else {
            XCTFail("Failed to parse baseline")
            return
        }
        XCTAssertEqual(baseline.device, "Mac mini")
    }

    func testParseEmptyMarkdown() {
        let baseline = CaptionLatencyBaseline.parse(markdown: "")
        XCTAssertNil(baseline)
    }

    func testParseHandlesMissingColumns() {
        let markdown = """
        | Device | OS | Date | Median |
        |--------|----|----|--------|
        | Mac mini | macOS 14.6 | 2026-10-05 | 0.200 |
        """

        let baseline = CaptionLatencyBaseline.parse(markdown: markdown)
        XCTAssertNil(baseline)
    }

    func testParseMixedTBDAndValid() {
        let markdown = """
        | Device | OS | Date | Median | P95 | Time-to-First |
        |--------|----|----|--------|-----|----------------|
        | Mac mini | macOS 14.6 | TBD | TBD | TBD | TBD |
        | iPhone 15 | iOS 18 | 2026-10-05 | 0.180 | 0.280 | 0.040 |
        """

        let baseline = CaptionLatencyBaseline.parse(markdown: markdown)
        XCTAssertNotNil(baseline)
        XCTAssertEqual(baseline?.device, "iPhone 15")
    }
}

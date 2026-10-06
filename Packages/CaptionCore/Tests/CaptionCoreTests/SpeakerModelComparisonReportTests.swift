import XCTest
@testable import CaptionCore

final class SpeakerModelComparisonReportTests: XCTestCase {
    func testBasicConstruction() {
        let report = SpeakerModelComparisonReport(
            modelName: "Sortformer",
            speakersFound: 2,
            der: 0.12,
            timeToFirstLabel: 0.05
        )
        XCTAssertEqual(report.modelName, "Sortformer")
        XCTAssertEqual(report.speakersFound, 2)
        XCTAssertEqual(report.der, 0.12, accuracy: 0.001)
        XCTAssertNotNil(report.timeToFirstLabelSeconds)
        if let ttf = report.timeToFirstLabelSeconds {
            XCTAssertEqual(ttf, 0.05, accuracy: 0.001)
        }
    }

    func testTimeToFirstLabelOptional() {
        let report = SpeakerModelComparisonReport(
            modelName: "LS-EEND/dihard3",
            speakersFound: 3,
            der: 0.15
        )
        XCTAssertNil(report.timeToFirstLabelSeconds)
    }

    func testSummaryLine() {
        let report = SpeakerModelComparisonReport(
            modelName: "Sortformer",
            speakersFound: 2,
            der: 0.12,
            timeToFirstLabel: 0.05
        )
        let summary = report.summaryLine()
        XCTAssertTrue(summary.contains("Sortformer"))
        XCTAssertTrue(summary.contains("speakers: 2"))
        XCTAssertTrue(summary.contains("DER:"))
        XCTAssertTrue(summary.contains("0.120"))
    }

    func testSummaryLineWithoutTimeToFirstLabel() {
        let report = SpeakerModelComparisonReport(
            modelName: "LS-EEND/ami",
            speakersFound: 4,
            der: 0.18
        )
        let summary = report.summaryLine()
        XCTAssertTrue(summary.contains("LS-EEND/ami"))
        XCTAssertTrue(summary.contains("N/A"))
    }

    func testDERBounds() {
        let perfectReport = SpeakerModelComparisonReport(
            modelName: "Perfect",
            speakersFound: 2,
            der: 0.0
        )
        let worstReport = SpeakerModelComparisonReport(
            modelName: "Worst",
            speakersFound: 2,
            der: 1.0
        )
        XCTAssertEqual(perfectReport.der, 0.0)
        XCTAssertEqual(worstReport.der, 1.0)
    }
}

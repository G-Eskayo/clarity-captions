import XCTest
@testable import CaptionCore

final class VoiceCalibrationTableTests: XCTestCase {
    func testSpanishReturnsEmpty() {
        let calibrations = VoiceCalibrationTable.calibrations(for: "es")
        XCTAssertEqual(calibrations.count, 0)
    }

    func testSpanishMexicoReturnsEmpty() {
        let calibrations = VoiceCalibrationTable.calibrations(for: "es-MX")
        XCTAssertEqual(calibrations.count, 0)
    }

    func testUnknownLanguageReturnsEmpty() {
        let calibrations = VoiceCalibrationTable.calibrations(for: "xx")
        XCTAssertEqual(calibrations.count, 0)
    }

    func testEnglishReturnsEmpty() {
        let calibrations = VoiceCalibrationTable.calibrations(for: "en")
        XCTAssertEqual(calibrations.count, 0)
    }

    func testFrenchReturnsEmpty() {
        let calibrations = VoiceCalibrationTable.calibrations(for: "fr")
        XCTAssertEqual(calibrations.count, 0)
    }

    func testCaseInsensitive() {
        let lower = VoiceCalibrationTable.calibrations(for: "es")
        let upper = VoiceCalibrationTable.calibrations(for: "ES")
        XCTAssertEqual(lower.count, upper.count)
    }
}

import XCTest
@testable import CaptionCore

final class FailureReasonTests: XCTestCase {
    func testTranscriptionErrorNoCompatibleAudioFormat() {
        let error = TranscriptionError.noCompatibleAudioFormat
        let plain = FailureReason.plainLanguage(for: error)
        XCTAssertNotEqual(plain, String(describing: error))
        XCTAssertTrue(plain.count > 0)
        XCTAssertFalse(plain.contains("noCompatibleAudioFormat"))
    }

    func testTranscriptionErrorConverterUnavailable() {
        let error = TranscriptionError.converterUnavailable
        let plain = FailureReason.plainLanguage(for: error)
        XCTAssertNotEqual(plain, String(describing: error))
        XCTAssertTrue(plain.count > 0)
        XCTAssertFalse(plain.contains("converterUnavailable"))
    }

    func testSpeakerModelErrorModelMissing() {
        let url = URL(fileURLWithPath: "test.mlmodelc")
        let error = SpeakerModelError.modelMissing(url)
        let plain = FailureReason.plainLanguage(for: error)
        XCTAssertNotEqual(plain, String(describing: error))
        XCTAssertTrue(plain.count > 0)
        XCTAssertFalse(plain.contains("modelMissing"))
    }

    func testUnknownErrorFallback() {
        struct UnknownError: Error {}
        let error = UnknownError()
        let plain = FailureReason.plainLanguage(for: error)
        XCTAssertTrue(plain.count > 0)
        XCTAssertTrue(plain.contains("try again") || plain.lowercased().contains("something went wrong"))
    }

    func testPlainLanguageIsAlwaysNonTechnical() {
        let errors: [Error] = [
            TranscriptionError.noCompatibleAudioFormat,
            TranscriptionError.converterUnavailable,
        ]
        for error in errors {
            let plain = FailureReason.plainLanguage(for: error)
            XCTAssertFalse(plain.contains("Error"), "Should not contain 'Error' keyword for: \(error)")
            XCTAssertFalse(plain.contains("exception"), "Should not contain 'exception'")
        }
    }

    func testPauseDetailForMicTakenElsewhere() {
        let detail = FailureReason.pauseDetail(for: .micTakenElsewhere)
        XCTAssertNotEqual(detail, "")
        XCTAssertFalse(detail.contains("micTakenElsewhere"), "must not contain technical enum name")
        XCTAssertFalse(detail.contains("Error"), "must not contain 'Error'")
    }
}

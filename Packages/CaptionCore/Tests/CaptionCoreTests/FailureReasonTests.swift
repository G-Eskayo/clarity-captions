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
}

#if os(macOS)
final class CallAudioFailureReasonTests: XCTestCase {
    func testNothingToListenToSaysSoPlainly() {
        let words = FailureReason.plainLanguage(for: CallAudioError.appNotPlayingSound)
        XCTAssertFalse(words.contains("Something went wrong"), words)
        XCTAssertTrue(words.lowercased().contains("call"), words)
    }

    func testACoreAudioRefusalNeverShowsItsStatusCode() {
        let words = FailureReason.plainLanguage(for: CallAudioError.coreAudio(step: "create tap", status: 560_947_818))
        XCTAssertFalse(words.contains("560947818"), words)
        XCTAssertFalse(words.contains("create tap"), words)
        XCTAssertTrue(words.contains("System Audio Recording"), "should name the permission to check: \(words)")
    }
}
#endif

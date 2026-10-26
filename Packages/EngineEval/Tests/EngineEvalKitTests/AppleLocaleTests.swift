import XCTest
@testable import EngineEvalKit

/// `--locale` for the Apple engine (#158). en-US stays the default so #145's model names are unchanged.
final class AppleLocaleTests: XCTestCase {
    func testDefaultIsEnglishUS() {
        XCTAssertEqual(AppleLocale.parse(nil), "en-US")
        XCTAssertEqual(AppleLocale.modelName("en-US"), "SpeechTranscriber en-US")
    }

    func testAcceptsLanguageRegion() {
        for id in ["es-MX", "es-US", "es-ES", "fr-FR", "de-DE", " de-CH "] {
            XCTAssertEqual(AppleLocale.parse(id), id.trimmingCharacters(in: .whitespaces))
        }
        XCTAssertEqual(AppleLocale.modelName("es-MX"), "SpeechTranscriber es-MX")
    }

    func testRejectsMalformed() {
        for bad in ["", "es", "es_MX", "ES-mx", "es-MXX", "../x", "es-MX,fr-FR", "e-MX"] {
            XCTAssertNil(AppleLocale.parse(bad), bad)
        }
    }
}

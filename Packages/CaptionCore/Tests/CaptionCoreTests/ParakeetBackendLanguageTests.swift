import XCTest
@testable import CaptionCore

final class ParakeetBackendLanguageTests: XCTestCase {
    func testLanguageMapsAllSixParakeetLanguages() {
        XCTAssertEqual(ParakeetBackend.language(for: Locale(identifier: "en-US")), .english)
        XCTAssertEqual(ParakeetBackend.language(for: Locale(identifier: "es-ES")), .spanish)
        XCTAssertEqual(ParakeetBackend.language(for: Locale(identifier: "fr-FR")), .french)
        XCTAssertEqual(ParakeetBackend.language(for: Locale(identifier: "de-DE")), .german)
        XCTAssertEqual(ParakeetBackend.language(for: Locale(identifier: "it-IT")), .italian)
        XCTAssertEqual(ParakeetBackend.language(for: Locale(identifier: "pt-BR")), .portuguese)
    }

    func testLanguageReturnsNilForNonParakeetLanguages() {
        XCTAssertNil(ParakeetBackend.language(for: Locale(identifier: "he-IL")))
        XCTAssertNil(ParakeetBackend.language(for: Locale(identifier: "ja-JP")))
        XCTAssertNil(ParakeetBackend.language(for: Locale(identifier: "zh-Hans-CN")))
        XCTAssertNil(ParakeetBackend.language(for: Locale(identifier: "ko-KR")))
    }

    func testLanguageHandlesMalformedLocales() {
        XCTAssertNil(ParakeetBackend.language(for: Locale(identifier: "")))
    }

    func testLanguageNeverTraps() {
        // Ensure no trap on any input, including edge cases
        let testCases = [
            Locale(identifier: "en"),
            Locale(identifier: "en-US"),
            Locale(identifier: "xx-YY"),
            Locale(identifier: ""),
        ]
        for locale in testCases {
            _ = ParakeetBackend.language(for: locale)  // Should not trap
        }
    }
}

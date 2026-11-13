import Foundation
import FluidAudio
import XCTest
@testable import CaptionCore

final class ParakeetBackendLanguageTests: XCTestCase {
    func testParakeetLanguageMapsEnglishLocales() {
        XCTAssertEqual(parakeetLanguage(for: Locale(identifier: "en-US")), .english)
        XCTAssertEqual(parakeetLanguage(for: Locale(identifier: "en-GB")), .english)
    }

    func testParakeetLanguageMapsSpanishLocales() {
        XCTAssertEqual(parakeetLanguage(for: Locale(identifier: "es-ES")), .spanish)
        XCTAssertEqual(parakeetLanguage(for: Locale(identifier: "es-MX")), .spanish)
    }

    func testParakeetLanguageMapsFrenchGermanItalianPortuguese() {
        XCTAssertEqual(parakeetLanguage(for: Locale(identifier: "fr-FR")), .french)
        XCTAssertEqual(parakeetLanguage(for: Locale(identifier: "de-DE")), .german)
        XCTAssertEqual(parakeetLanguage(for: Locale(identifier: "it-IT")), .italian)
        XCTAssertEqual(parakeetLanguage(for: Locale(identifier: "pt-PT")), .portuguese)
    }

    func testParakeetLanguageMappsCyrillicLocales() {
        XCTAssertEqual(parakeetLanguage(for: Locale(identifier: "ru-RU")), .russian)
        XCTAssertEqual(parakeetLanguage(for: Locale(identifier: "uk-UA")), .ukrainian)
    }

    func testParakeetLanguageReturnsNilForUnsupportedLocales() {
        XCTAssertNil(parakeetLanguage(for: Locale(identifier: "he-IL")))
        XCTAssertNil(parakeetLanguage(for: Locale(identifier: "ja-JP")))
        XCTAssertNil(parakeetLanguage(for: Locale(identifier: "zh-CN")))
        XCTAssertNil(parakeetLanguage(for: Locale(identifier: "xx-YY")))
    }

    func testParakeetBackendInitAcceptsLocaleWithDefault() {
        let url = URL(fileURLWithPath: "/tmp/model")
        let backend1 = ParakeetBackend(modelURL: url)
        XCTAssertEqual(backend1.name, "parakeet-ultra-pal6")

        let backend2 = ParakeetBackend(modelURL: url, locale: Locale(identifier: "es-ES"))
        XCTAssertEqual(backend2.name, "parakeet-ultra-pal6")
    }
}

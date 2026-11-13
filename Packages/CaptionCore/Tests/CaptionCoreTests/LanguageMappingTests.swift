import Foundation
import XCTest
@testable import CaptionCore
import FluidAudio

/// Language locale-to-Language mapping (tests-first item 1).
final class LanguageMappingTests: XCTestCase {
    func testEnglishLocaleMapsToParkeetEnglish() {
        let locale = Locale(identifier: "en-US")
        let language = Language.language(for: locale)
        XCTAssertEqual(language, .english)
    }

    func testEnglishUKMapsToParkeetEnglish() {
        let locale = Locale(identifier: "en-GB")
        let language = Language.language(for: locale)
        XCTAssertEqual(language, .english)
    }

    func testSpanishLocaleMapsToParkeetSpanish() {
        let locale = Locale(identifier: "es-ES")
        let language = Language.language(for: locale)
        XCTAssertEqual(language, .spanish)
    }

    func testMexicanSpanishMapsToParkeetSpanish() {
        let locale = Locale(identifier: "es-MX")
        let language = Language.language(for: locale)
        XCTAssertEqual(language, .spanish)
    }

    func testFrenchLocaleMapsToParkeetFrench() {
        let locale = Locale(identifier: "fr-FR")
        let language = Language.language(for: locale)
        XCTAssertEqual(language, .french)
    }

    func testGermanLocaleMapsToParkeetGerman() {
        let locale = Locale(identifier: "de-DE")
        let language = Language.language(for: locale)
        XCTAssertEqual(language, .german)
    }

    func testItalianLocaleMapsToParkeetItalian() {
        let locale = Locale(identifier: "it-IT")
        let language = Language.language(for: locale)
        XCTAssertEqual(language, .italian)
    }

    func testPortugueseLocaleMapsToParkeetPortuguese() {
        let locale = Locale(identifier: "pt-BR")
        let language = Language.language(for: locale)
        XCTAssertEqual(language, .portuguese)
    }

    func testPortugalPortugueseMapsToParkeetPortuguese() {
        let locale = Locale(identifier: "pt-PT")
        let language = Language.language(for: locale)
        XCTAssertEqual(language, .portuguese)
    }

    func testHebrewLocaleReturnsNil() {
        let locale = Locale(identifier: "he-IL")
        let language = Language.language(for: locale)
        XCTAssertNil(language, "Hebrew has no Parakeet model, uses a streaming engine")
    }

    func testJapaneseLocaleReturnsNil() {
        let locale = Locale(identifier: "ja-JP")
        let language = Language.language(for: locale)
        XCTAssertNil(language, "Japanese has no Parakeet model")
    }

    func testUnknownLocaleReturnsNil() {
        let locale = Locale(identifier: "unknown")
        let language = Language.language(for: locale)
        XCTAssertNil(language)
    }
}

import XCTest
@testable import CaptionCore

final class LanguageSelectionTests: XCTestCase {
    func testExactBCP47MatchWins() {
        let result = LanguageSelection.defaultLocale(deviceLocaleIdentifier: "en-US", supportedLocaleIdentifiers: ["en-US", "es-ES"])
        XCTAssertEqual(result, "en-US")
    }

    func testExactMatchIsCaseInsensitive() {
        let result = LanguageSelection.defaultLocale(deviceLocaleIdentifier: "en-US", supportedLocaleIdentifiers: ["en-US"])
        XCTAssertEqual(result, "en-US")
    }

    func testSingleDialectAutoMatchWins() {
        let result = LanguageSelection.defaultLocale(deviceLocaleIdentifier: "en-GB", supportedLocaleIdentifiers: ["en-US", "es-ES"])
        XCTAssertEqual(result, "en-US")
    }

    func testMultipleDialectsAmbiguous() {
        let result = LanguageSelection.defaultLocale(deviceLocaleIdentifier: "en-GB", supportedLocaleIdentifiers: ["en-US", "en-AU", "es-ES"])
        XCTAssertNil(result)
    }

    func testUnsupportedLanguageReturnsNil() {
        let result = LanguageSelection.defaultLocale(deviceLocaleIdentifier: "zh-CN", supportedLocaleIdentifiers: ["en-US", "es-ES"])
        XCTAssertNil(result)
    }

    func testEmptyListReturnsNil() {
        let result = LanguageSelection.defaultLocale(deviceLocaleIdentifier: "en-US", supportedLocaleIdentifiers: [])
        XCTAssertNil(result)
    }

    func testMustAskWhenAmbiguous() {
        XCTAssertTrue(LanguageSelection.mustAskOnFirstRun(deviceLocaleIdentifier: "en-GB", supportedLocaleIdentifiers: ["en-US", "en-AU"]))
    }

    func testMustAskWhenUnsupported() {
        XCTAssertTrue(LanguageSelection.mustAskOnFirstRun(deviceLocaleIdentifier: "zh-CN", supportedLocaleIdentifiers: ["en-US", "es-ES"]))
    }

    func testNoAskWhenMatched() {
        XCTAssertFalse(LanguageSelection.mustAskOnFirstRun(deviceLocaleIdentifier: "en-US", supportedLocaleIdentifiers: ["en-US", "es-ES"]))
    }
}

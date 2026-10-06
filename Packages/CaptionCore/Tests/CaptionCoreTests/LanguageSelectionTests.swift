import XCTest
@testable import CaptionCore

final class LanguageSelectionTests: XCTestCase {
    func testExactBCP47MatchIsSelected() {
        let supported = ["en-US", "en-GB", "es-ES"]
        XCTAssertEqual(LanguageSelection.defaultLocale(deviceLocaleIdentifier: "en-US", supportedLocaleIdentifiers: supported), "en-US")
    }

    func testExactMatchNeverAsksTheUser() {
        let supported = ["en-US", "es-ES"]
        XCTAssertFalse(LanguageSelection.mustAskOnFirstRun(deviceLocaleIdentifier: "en-US", supportedLocaleIdentifiers: supported))
    }

    func testSingleDialectOfDeviceLanguageIsSelectedWithoutAsking() {
        let supported = ["en-US", "es-ES"]
        XCTAssertEqual(LanguageSelection.defaultLocale(deviceLocaleIdentifier: "en-GB", supportedLocaleIdentifiers: supported), "en-US")
        XCTAssertFalse(LanguageSelection.mustAskOnFirstRun(deviceLocaleIdentifier: "en-GB", supportedLocaleIdentifiers: supported))
    }

    func testMultipleDialectsOfDeviceLanguageRequireUserChoice() {
        let supported = ["en-US", "en-GB", "es-ES"]
        XCTAssertNil(LanguageSelection.defaultLocale(deviceLocaleIdentifier: "en-AU", supportedLocaleIdentifiers: supported))
        XCTAssertTrue(LanguageSelection.mustAskOnFirstRun(deviceLocaleIdentifier: "en-AU", supportedLocaleIdentifiers: supported))
    }

    func testUnsupportedLanguageRequiresUserChoice() {
        let supported = ["en-US", "es-ES"]
        XCTAssertNil(LanguageSelection.defaultLocale(deviceLocaleIdentifier: "fr-FR", supportedLocaleIdentifiers: supported))
        XCTAssertTrue(LanguageSelection.mustAskOnFirstRun(deviceLocaleIdentifier: "fr-FR", supportedLocaleIdentifiers: supported))
    }

    func testEmptySupportedListRequiresUserChoice() {
        XCTAssertNil(LanguageSelection.defaultLocale(deviceLocaleIdentifier: "en-US", supportedLocaleIdentifiers: []))
        XCTAssertTrue(LanguageSelection.mustAskOnFirstRun(deviceLocaleIdentifier: "en-US", supportedLocaleIdentifiers: []))
    }

    func testPrefersCaseInsensitiveLanguageCode() {
        let supported = ["en-US", "es-ES"]
        XCTAssertEqual(LanguageSelection.defaultLocale(deviceLocaleIdentifier: "en-us", supportedLocaleIdentifiers: supported), "en-US")
    }
}

final class AppLocalizationCatalogTests: XCTestCase {
    func testEnglishIsTranslated() {
        XCTAssertTrue(AppLocalizationCatalog.isTranslated(localeIdentifier: "en-US"))
        XCTAssertTrue(AppLocalizationCatalog.isTranslated(localeIdentifier: "en-GB"))
        XCTAssertTrue(AppLocalizationCatalog.isTranslated(localeIdentifier: "en"))
    }

    func testSpanishIsNotYetTranslated() {
        XCTAssertFalse(AppLocalizationCatalog.isTranslated(localeIdentifier: "es-ES"))
        XCTAssertFalse(AppLocalizationCatalog.isTranslated(localeIdentifier: "es"))
    }

    func testFrenchIsNotYetTranslated() {
        XCTAssertFalse(AppLocalizationCatalog.isTranslated(localeIdentifier: "fr-FR"))
    }
}

final class LanguageStoreTests: XCTestCase {
    func testStoreRemembersSelectedLocale() {
        let d = UserDefaults(suiteName: "language-test-\(UUID())")!
        let store = LanguageStore(defaults: d)
        XCTAssertNil(store.selectedLocaleIdentifier)
        store.setSelectedLocaleIdentifier("en-US")
        XCTAssertEqual(store.selectedLocaleIdentifier, "en-US")
    }

    func testStoreCanUpdateSelectedLocale() {
        let d = UserDefaults(suiteName: "language-test-\(UUID())")!
        let store = LanguageStore(defaults: d)
        store.setSelectedLocaleIdentifier("en-US")
        store.setSelectedLocaleIdentifier("en-GB")
        XCTAssertEqual(store.selectedLocaleIdentifier, "en-GB")
    }
}

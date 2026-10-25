import XCTest
@testable import CaptionCore

final class LanguageStoreTests: XCTestCase {
    func testDefaultsToEnUS() {
        let d = UserDefaults(suiteName: "language-test-\(UUID())")!
        let store = LanguageStore(defaults: d)
        XCTAssertEqual(store.selectedLocaleIdentifier, "en-US")
    }

    func testRemembersSelectedLocale() {
        let d = UserDefaults(suiteName: "language-test-\(UUID())")!
        var store = LanguageStore(defaults: d)
        store.selectedLocaleIdentifier = "es-ES"
        XCTAssertEqual(store.selectedLocaleIdentifier, "es-ES")
    }

    func testPersistsAcrossInstances() {
        let d = UserDefaults(suiteName: "language-test-\(UUID())")!
        var store = LanguageStore(defaults: d)
        store.selectedLocaleIdentifier = "fr-FR"
        let store2 = LanguageStore(defaults: d)
        XCTAssertEqual(store2.selectedLocaleIdentifier, "fr-FR")
    }

    func testHasSelectionFalseWhenNotSet() {
        let d = UserDefaults(suiteName: "language-test-\(UUID())")!
        let store = LanguageStore(defaults: d)
        XCTAssertFalse(store.hasSelection)
    }

    func testHasSelectionTrueWhenSet() {
        let d = UserDefaults(suiteName: "language-test-\(UUID())")!
        var store = LanguageStore(defaults: d)
        store.selectedLocaleIdentifier = "es-ES"
        XCTAssertTrue(store.hasSelection)
    }
}

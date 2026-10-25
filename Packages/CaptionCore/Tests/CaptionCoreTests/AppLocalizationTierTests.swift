import XCTest
@testable import CaptionCore

final class AppLocalizationTierTests: XCTestCase {
    func testEnglishIsAlwaysFull() {
        XCTAssertEqual(AppLocalizationTier.tier(for: "en-US"), .full)
        XCTAssertEqual(AppLocalizationTier.tier(for: "en-GB"), .full)
    }

    func testTranslatedButNotNativeCheckedIsBeta() {
        XCTAssertEqual(AppLocalizationTier.tier(for: "es-ES", translatedLanguageCodes: ["es"], nativeCheckedLanguageCodes: []), .beta)
    }

    func testTranslatedAndNativeCheckedIsFull() {
        XCTAssertEqual(AppLocalizationTier.tier(for: "es-ES", translatedLanguageCodes: ["es"], nativeCheckedLanguageCodes: ["es"]), .full)
    }

    func testUntranslatedLanguageIsUntranslated() {
        XCTAssertEqual(AppLocalizationTier.tier(for: "fr-FR", translatedLanguageCodes: [], nativeCheckedLanguageCodes: []), .untranslated)
    }

    func testLanguageCodeCaseInsensitive() {
        XCTAssertEqual(AppLocalizationTier.tier(for: "ES-es", translatedLanguageCodes: ["es"], nativeCheckedLanguageCodes: []), .beta)
    }

    func testDefaultParametersAllUntranslatedExceptEnglish() {
        XCTAssertEqual(AppLocalizationTier.tier(for: "en-US"), .full)
        XCTAssertEqual(AppLocalizationTier.tier(for: "es-ES"), .untranslated)
        XCTAssertEqual(AppLocalizationTier.tier(for: "fr-FR"), .untranslated)
    }
}

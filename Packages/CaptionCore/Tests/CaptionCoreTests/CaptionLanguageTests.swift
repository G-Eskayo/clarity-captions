import XCTest
@testable import CaptionCore

/// #37: the caption language follows the device's language, and first run asks only when it must. #53: translation
/// goes into the device's language by default. These try to break the choice with regions, scripts, a device language
/// the engine doesn't have, and lists in odd orders.
final class CaptionLanguageTests: XCTestCase {
    private func locales(_ ids: String...) -> [Locale] { ids.map(Locale.init(identifier:)) }
    private let english = Locale(identifier: "en-US")

    func testExactDeviceLanguageIsUsedWithoutAsking() {
        let c = CaptionLanguage.defaultChoice(preferred: ["es-MX"], supported: locales("en-US", "es-ES", "es-MX", "es-US"))
        XCTAssertEqual(c, .use(Locale(identifier: "es-MX")))
    }

    func testTheOnlyRegionOfTheDeviceLanguageIsUsed() {
        // A Portuguese (Portugal) iPad when the engine only has Brazilian Portuguese: same language, one choice.
        let c = CaptionLanguage.defaultChoice(preferred: ["pt-PT"], supported: locales("en-US", "pt-BR"))
        XCTAssertEqual(c, .use(Locale(identifier: "pt-BR")))
    }

    func testSeveralRegionsAndNoExactMatchAsks() {
        let c = CaptionLanguage.defaultChoice(preferred: ["en-NZ"], supported: locales("en-US", "en-GB", "en-AU", "fr-FR"))
        XCTAssertEqual(c, .ask(suggested: locales("en-AU", "en-GB", "en-US")))
    }

    func testABareLanguageWithSeveralRegionsAsks() {
        let c = CaptionLanguage.defaultChoice(preferred: ["fr"], supported: locales("fr-FR", "fr-CA", "en-US"))
        XCTAssertEqual(c, .ask(suggested: locales("fr-CA", "fr-FR")))
    }

    func testTheNextPreferredLanguageIsUsedWhenTheFirstIsMissing() {
        // Someone who reads Welsh first and English second: the engine has no Welsh, so their second language.
        let c = CaptionLanguage.defaultChoice(preferred: ["cy-GB", "en-US"], supported: locales("en-US", "fr-FR"))
        XCTAssertEqual(c, .use(english))
    }

    func testNoPreferredLanguageSupportedAsksWithEverything() {
        let c = CaptionLanguage.defaultChoice(preferred: ["cy-GB"], supported: locales("fr-FR", "en-US"))
        XCTAssertEqual(c, .ask(suggested: []))
    }

    func testNoSupportedLanguagesAtAllAsksRatherThanCrashing() {
        XCTAssertEqual(CaptionLanguage.defaultChoice(preferred: ["en-US"], supported: []), .ask(suggested: []))
        XCTAssertEqual(CaptionLanguage.defaultChoice(preferred: [], supported: locales("en-US")), .ask(suggested: []))
    }

    func testScriptsAreDifferentLanguages() {
        // Traditional Chinese must not silently become Simplified.
        let c = CaptionLanguage.defaultChoice(preferred: ["zh-Hant-TW"], supported: locales("zh-Hans-CN", "zh-Hant-TW"))
        XCTAssertEqual(c, .use(Locale(identifier: "zh-Hant-TW")))
        let d = CaptionLanguage.defaultChoice(preferred: ["zh-Hant-HK"], supported: locales("zh-Hans-CN"))
        XCTAssertEqual(d, .ask(suggested: []))
    }

    func testUnderscoreAndHyphenFormsAreTheSame() {
        XCTAssertEqual(CaptionLanguage.defaultChoice(preferred: ["en_GB"], supported: locales("en-GB")), .use(Locale(identifier: "en-GB")))
    }

    func testTheOrderOfTheSupportedListDoesNotChangeTheAnswer() {
        let a = CaptionLanguage.defaultChoice(preferred: ["en-NZ"], supported: locales("en-US", "en-GB"))
        let b = CaptionLanguage.defaultChoice(preferred: ["en-NZ"], supported: locales("en-GB", "en-US"))
        XCTAssertEqual(a, b)
    }

    // MARK: translation (#53)

    func testTranslationGoesIntoTheDeviceLanguage() {
        // Captions in Spanish on an English iPad: translate into English.
        XCTAssertEqual(CaptionLanguage.translationTarget(captions: Locale(identifier: "es-ES"), preferred: ["en-US"]),
                       english)
    }

    func testTranslationHasNoDefaultWhenCaptionsAreAlreadyInTheDeviceLanguage() {
        // English captions on an English iPad: there's nothing to translate into until a language is picked.
        XCTAssertNil(CaptionLanguage.translationTarget(captions: Locale(identifier: "en-GB"), preferred: ["en-US"]))
        XCTAssertEqual(CaptionLanguage.translationTarget(captions: Locale(identifier: "en-GB"), preferred: ["en-US", "fr-FR"]),
                       Locale(identifier: "fr-FR"), "the next language the person reads")
    }

    func testStoredChoiceRoundTripsAndAbsentMeansFollowTheDevice() {
        let defaults = UserDefaults(suiteName: "CaptionLanguageTests-\(UUID())")!
        let store = CaptionLanguageStore(defaults: defaults)
        XCTAssertNil(store.captionLanguage, "no stored choice: follow the device")
        store.captionLanguage = Locale(identifier: "es-MX")
        XCTAssertEqual(store.captionLanguage, Locale(identifier: "es-MX"))
        XCTAssertFalse(store.translationOn)
        store.translationOn = true
        store.translationTarget = Locale(identifier: "en-US")
        XCTAssertTrue(CaptionLanguageStore(defaults: defaults).translationOn)
        XCTAssertEqual(CaptionLanguageStore(defaults: defaults).translationTarget, english)
        store.captionLanguage = nil
        XCTAssertNil(store.captionLanguage)
    }

    // MARK: the saved choice (#37: Settings can switch language)

    func testAChosenLanguageTheDeviceHasWinsOverTheDeviceLanguage() {
        let c = CaptionLanguage.resolve(saved: Locale(identifier: "es-ES"), preferred: ["en-US"], supported: locales("en-US", "es-ES"))
        XCTAssertEqual(c, .use(Locale(identifier: "es-ES")))
    }

    func testNothingSavedFollowsTheDevice() {
        let c = CaptionLanguage.resolve(saved: nil, preferred: ["en-US"], supported: locales("en-US", "es-ES"))
        XCTAssertEqual(c, .use(english))
    }

    func testASavedLanguageTheDeviceNoLongerHasFallsBackToTheDevice() {
        let c = CaptionLanguage.resolve(saved: Locale(identifier: "ko-KR"), preferred: ["en-US"], supported: locales("en-US", "es-ES"))
        XCTAssertEqual(c, .use(english))
    }

    func testASavedLanguageIsMatchedByItsFullCodeNotItsSpelling() {
        // Saved as "es_ES" by an older build, listed as "es-ES" by the engine.
        let c = CaptionLanguage.resolve(saved: Locale(identifier: "es_ES"), preferred: ["en-US"], supported: locales("en-US", "es-ES"))
        XCTAssertEqual(c.locale.map(CaptionLanguage.bcp47), "es-ES")
    }

    func testAnEmptyEngineListStillUsesTheSavedLanguageRatherThanAsking() {
        // The list can come back empty for a moment at launch; a saved choice mustn't be thrown away for it.
        let c = CaptionLanguage.resolve(saved: Locale(identifier: "es-ES"), preferred: ["en-US"], supported: [])
        XCTAssertEqual(c, .use(Locale(identifier: "es-ES")))
    }
}

/// #252: the same language on both sides is allowed (owner). Apple's Translation has no pair for it, so the words pass
/// through as they are.
final class SameLanguageTranslationTests: XCTestCase {
    private func lang(_ id: String) -> Locale.Language { Locale.Language(identifier: id) }

    func testTheSameLanguageNeedsNoTranslation() {
        XCTAssertTrue(CaptionLanguage.needsNoTranslation(from: lang("fr-FR"), into: lang("fr-FR")))
        XCTAssertTrue(CaptionLanguage.needsNoTranslation(from: lang("en-US"), into: lang("en-GB")), "regions read the same")
        XCTAssertTrue(CaptionLanguage.needsNoTranslation(from: lang("en-US"), into: lang("en-Latn-US")))
    }

    func testDifferentLanguagesAndScriptsAreTranslated() {
        XCTAssertFalse(CaptionLanguage.needsNoTranslation(from: lang("en-US"), into: lang("fr-FR")))
        XCTAssertFalse(CaptionLanguage.needsNoTranslation(from: lang("zh-CN"), into: lang("zh-Hant-TW")), "Simplified into Traditional is real work")
    }
}

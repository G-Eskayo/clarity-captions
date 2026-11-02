import CaptionCore
import XCTest

/// #252: the swap between translation's From and Into. From must be a language the speech engine has (it captions it),
/// Into any language Translation has, so a swap maps each side onto the other's list. These try regions, scripts, a
/// language the speech engine doesn't have, and a download that fails.
final class LanguageSwapTests: XCTestCase {
    private func l(_ id: String) -> Locale { Locale(identifier: id) }
    private let speech = ["de-DE", "en-AU", "en-GB", "en-US", "es-ES", "es-MX", "fr-CA", "fr-FR", "zh-CN", "zh-TW"].map(Locale.init(identifier:))
    private func plan(_ from: String, _ into: String?, preferred: [String] = ["en-US"]) -> LanguageSwap? {
        LanguageSwap.plan(from: l(from), into: into.map(l), speech: speech, preferred: preferred)
    }
    private func ids(_ s: LanguageSwap?) -> [String]? { s.map { [$0.from, $0.into].map(CaptionLanguage.bcp47) } }

    func testEnglishIntoFrenchSwapsToFrenchIntoEnglish() {
        XCTAssertEqual(ids(plan("en-US", "fr-FR")), ["fr-FR", "en-US"])
    }

    func testTheSameLanguageOnBothSidesSwapsToItself() {
        XCTAssertEqual(ids(plan("fr-FR", "fr-FR")), ["fr-FR", "fr-FR"])
    }

    func testIntoWithAScriptBecomesTheSpeechEnginesName() {
        // Translation names Chinese with its script; the speech engine by region. Scripts never cross.
        XCTAssertEqual(ids(plan("en-US", "zh-Hans-CN")), ["zh-CN", "en-US"])
        XCTAssertEqual(ids(plan("en-US", "zh-Hant-TW")), ["zh-TW", "en-US"])
    }

    func testIntoWithNoRegionTakesTheRegionSheUses() {
        XCTAssertEqual(ids(plan("es-ES", "en", preferred: ["en-GB", "es-ES"])), ["en-GB", "es-ES"])
    }

    func testIntoWithNoRegionAndNoHintStillPicksOneTheSameWayEveryTime() {
        XCTAssertEqual(ids(plan("es-ES", "fr", preferred: ["es-ES"])), ["fr-CA", "es-ES"])
    }

    func testARegionTheEngineLacksFallsBackToOneItHas() {
        XCTAssertEqual(ids(plan("en-US", "fr-BE", preferred: ["en-US"])), ["fr-CA", "en-US"])
        XCTAssertEqual(ids(plan("en-US", "fr-BE", preferred: ["fr-FR"])), ["fr-FR", "en-US"])
    }

    func testNoSwapWhenTheSpeechEngineCantCaptionTheIntoLanguageAndScriptsNeverCross() {
        XCTAssertNil(plan("en-US", "ar-AE"), "Seal can't caption Arabic, so it can't be From")
        XCTAssertEqual(ids(plan("en-US", "zh-Hant-HK"))?.first, "zh-TW", "Traditional Chinese never becomes Simplified")
    }

    func testNoSwapBeforeIntoIsChosen() {
        XCTAssertNil(plan("en-US", nil))
    }

    func testNoSwapBeforeTheSpeechEngineHasAnswered() {
        XCTAssertNil(LanguageSwap.plan(from: l("en-US"), into: l("fr-FR"), speech: [], preferred: ["en-US"]))
    }

    // MARK: while From downloads

    private let swap = LanguageSwap.plan(from: Locale(identifier: "en-US"), into: Locale(identifier: "fr-FR"),
                                         speech: ["en-US", "fr-FR"].map(Locale.init(identifier:)), preferred: ["en-US"])!

    func testIntoChangesAtOnceWhileFromDownloads() {
        var s = CaptionLanguageSwitch(current: l("en-US"))
        _ = s.choose(swap.from, installed: false)
        XCTAssertEqual(swap.into(after: s), l("en-US"))
        s.progress(0.4, for: swap.from)
        XCTAssertEqual(s.shown, .init(locale: l("fr-FR"), downloading: 0.4))
        s.finished(.installed, for: swap.from)
        XCTAssertEqual(swap.into(after: s), l("en-US"))
        XCTAssertEqual(s.current, l("fr-FR"))
    }

    func testAFailedDownloadPutsIntoBackSoThePairIsWhatItWas() {
        var s = CaptionLanguageSwitch(current: l("en-US"))
        _ = s.choose(swap.from, installed: false)
        s.finished(.failed(.offline), for: swap.from)
        XCTAssertEqual(s.current, l("en-US"))
        XCTAssertEqual(swap.into(after: s), l("fr-FR"), "English into French again, not English into English")
    }

    func testAnInstalledFromSwapsBothAtOnce() {
        var s = CaptionLanguageSwitch(current: l("en-US"))
        XCTAssertNil(s.choose(swap.from, installed: true))
        XCTAssertEqual(swap.into(after: s), l("en-US"))
    }

    func testAPickAfterTheSwapKeepsTheSwappedInto() {
        // She swapped, then picked German as From while French downloaded: her newest pick decides From, the swap Into.
        var s = CaptionLanguageSwitch(current: l("en-US"))
        _ = s.choose(swap.from, installed: false)
        _ = s.choose(l("de-DE"), installed: false)
        s.finished(.failed(.offline), for: l("de-DE"))
        XCTAssertEqual(swap.into(after: s), l("en-US"), "the failed download was German's, not the swap's")
    }
}

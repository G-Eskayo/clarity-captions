import CaptionCore
import XCTest

/// #37 / #53: the list behind "Caption language" and translation's "From". The inputs are what Apple reported on the
/// M4 Mac mini, macOS 26.5 (2026-10-28): `SpeechTranscriber.supportedLocales` and `LanguageAvailability`.
final class CaptionLanguageListTests: XCTestCase {
    private func l(_ id: String) -> Locale { Locale(identifier: id) }
    private let speech = ["de-DE", "en-GB", "en-US", "es-ES", "es-MX", "fr-FR", "ja-JP", "yue-CN", "zh-CN", "zh-TW"]
    /// Translation's languages, as `LanguageAvailability.supportedLanguages` names them (no Cantonese).
    private let translation = ["de-Latn-DE", "en-Latn-US", "es-Latn-ES", "fr-Latn-FR", "ja-Jpan-JP", "zh-Hans-CN", "zh-Hant-TW"]

    private func rows(current: String = "es-ES", into: String? = "en-US", installed: [String] = ["es-ES", "en-US"]) -> [CaptionLanguageList.Row] {
        CaptionLanguageList.rows(speech: speech.map(l), installed: installed.map(l), current: l(current),
                                 translation: into.map { (into: l($0), supported: translation.map(Locale.Language.init(identifier:))) })
    }

    private func row(_ id: String, in rows: [CaptionLanguageList.Row]) -> CaptionLanguageList.Row? {
        rows.first { $0.locale.identifier(.bcp47) == id }
    }

    func testEveryLanguageTheSpeechEngineHasIsListedOnce() {
        let r = rows()
        XCTAssertEqual(r.count, speech.count)
        XCTAssertEqual(Set(r.map { $0.locale.identifier(.bcp47) }), Set(speech))
    }

    func testOnlyTheChosenLanguageIsTicked() {
        let r = rows(current: "es-MX")
        XCTAssertEqual(r.filter(\.isCurrent).map { $0.locale.identifier(.bcp47) }, ["es-MX"])
    }

    func testInstalledLanguagesNeedNoDownload() {
        let r = rows()
        XCTAssertTrue(row("es-ES", in: r)!.onDevice)
        XCTAssertFalse(row("es-MX", in: r)!.onDevice, "another region of an installed language is its own download")
        XCTAssertFalse(row("fr-FR", in: r)!.onDevice)
    }

    func testWithTranslationOffNothingSaysAnythingAboutTranslation() {
        XCTAssertTrue(rows(into: nil).allSatisfy { $0.translation == .off })
    }

    func testLanguagesTranslationHasTranslateIntoYours() {
        let r = rows()
        XCTAssertEqual(row("es-ES", in: r)?.translation, .translates)
        XCTAssertEqual(row("es-MX", in: r)?.translation, .translates, "a region translation doesn't list still translates")
        XCTAssertEqual(row("ja-JP", in: r)?.translation, .translates)
    }

    func testCantoneseCanBeCaptionedButNotTranslated() {
        XCTAssertEqual(row("yue-CN", in: rows())?.translation, .captionsOnly)
    }

    func testChineseScriptsAreMatchedNotMerged() {
        let r = rows()
        XCTAssertEqual(row("zh-CN", in: r)?.translation, .translates)
        XCTAssertEqual(row("zh-TW", in: r)?.translation, .translates)
        let onlySimplified = CaptionLanguageList.rows(speech: [l("zh-TW")], installed: [], current: l("es-ES"),
                                                      translation: (into: l("en-US"), supported: [Locale.Language(identifier: "zh-Hans-CN")]))
        XCTAssertEqual(onlySimplified.first?.translation, .captionsOnly, "Traditional must not borrow Simplified's translation")
    }

    func testYourOwnLanguageIsMarkedAsNothingToTranslate() {
        let r = rows()
        XCTAssertEqual(row("en-US", in: r)?.translation, .yourLanguage)
        XCTAssertEqual(row("en-GB", in: r)?.translation, .yourLanguage, "any English, when translating into English")
    }

    func testTheListPutsTheChosenLanguageFirstThenTheRestInOrder() {
        let r = CaptionLanguageList.rows(speech: speech.map(l), installed: [], current: l("fr-FR"), translation: nil)
        XCTAssertEqual(r.first?.locale.identifier(.bcp47), "fr-FR")
        let rest = r.dropFirst().map { $0.locale.identifier(.bcp47) }
        XCTAssertEqual(rest, rest.sorted())
    }

    func testAChosenLanguageTheEngineNoLongerHasIsStillShownSoSheCanSeeWhatsSet() {
        let r = CaptionLanguageList.rows(speech: [l("en-US")], installed: [], current: l("ko-KR"), translation: nil)
        XCTAssertEqual(r.first?.locale.identifier(.bcp47), "ko-KR")
        XCTAssertEqual(r.first?.isCurrent, true)
        XCTAssertEqual(r.first?.supported, false)
        XCTAssertEqual(r.last?.supported, true)
    }

    /// With translation on, what translates comes first; captions-only, then her own language, go to the end, so a
    /// dozen kinds of English don't push Spanish off the screen.
    func testWithTranslationOnTheLanguagesThatTranslateComeFirst() {
        let kinds = rows().dropFirst().map(\.translation)
        let order: [CaptionLanguageList.Translation] = [.translates, .captionsOnly, .yourLanguage]
        XCTAssertEqual(kinds, kinds.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! })
        XCTAssertEqual(rows().last?.translation, .yourLanguage)
    }
}

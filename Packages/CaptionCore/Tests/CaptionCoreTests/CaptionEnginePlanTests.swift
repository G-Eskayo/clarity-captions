import CaptionCore
import XCTest

/// #37 with Parakeet on main (#155): the engine is made for the caption language she chose. Parakeet is English only,
/// so any other language runs Apple's engine in that language, and Apple's fallback keeps her language too. Before
/// this, the app made every engine for en-US, so Spanish captions came out as English words.
final class CaptionEnginePlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let plenty: UInt64 = 2_000_000_000

    private func plan(_ id: String, choice: CaptionEngineChoice = .parakeet, modelPresent: Bool = true) -> CaptionEnginePlan {
        CaptionEnginePlan.make(captionLanguage: Locale(identifier: id), choice: choice, now: now, recentFallbacks: [],
                               availableMemory: plenty, modelPresent: modelPresent)
    }

    func testEnglishRunsParakeetAndAppleFallbackStaysInThatEnglish() {
        let p = plan("en-GB")
        XCTAssertEqual(p.selection.engine, .parakeet)
        XCTAssertEqual(p.locale.identifier(.bcp47), "en-GB")
    }

    func testSpanishRunsAppleInSpanishNotEnglish() {
        let p = plan("es-ES")
        XCTAssertEqual(p.selection, EngineSelection(engine: .apple, reason: .locale))
        XCTAssertEqual(p.locale.identifier(.bcp47), "es-ES")
    }

    func testEveryNonEnglishCaptionLanguageKeepsItsOwnLanguage() {
        for id in ["fr-FR", "de-DE", "ja-JP", "zh-TW", "yue-CN", "pt-BR"] {
            let p = plan(id)
            XCTAssertEqual(p.selection.engine, .apple, id)
            XCTAssertEqual(p.locale.identifier(.bcp47), id)
        }
    }

    func testAnApplePickOrAMissingModelStillUsesHerLanguage() {
        XCTAssertEqual(plan("es-MX", choice: .apple).locale.identifier(.bcp47), "es-MX")
        XCTAssertEqual(plan("en-US", modelPresent: false).selection.reason, .modelMissing)
        XCTAssertEqual(plan("fr-CA", modelPresent: false).locale.identifier(.bcp47), "fr-CA")
    }

    // MARK: Hebrew on Seal's own engine (#220, owner 2026-10-30)

    func testHebrewRunsSealsZipformerWhenItIsBundled() {
        let p = plan("he-IL")
        XCTAssertEqual(p.selection, EngineSelection(engine: .parakeet, reason: nil))
        XCTAssertEqual(p.sealModel, .hebrewZipformer)
        XCTAssertEqual(p.locale.identifier(.bcp47), "he-IL")
    }

    func testEnglishNamesParakeetAsItsModelAndOtherLanguagesNone() {
        XCTAssertEqual(plan("en-US").sealModel, .parakeetUltra)
        XCTAssertNil(plan("es-ES").sealModel)
        XCTAssertNil(plan("he-IL", choice: .apple).sealModel, "the developer panel's Apple pick wins")
    }

    func testHebrewWithoutItsModelSaysTheModelIsMissing() {
        let p = plan("he-IL", modelPresent: false)
        XCTAssertEqual(p.selection, EngineSelection(engine: .apple, reason: .modelMissing))
        XCTAssertNil(p.sealModel)
    }

    func testEachLanguageMapsToItsOwnModel() {
        XCTAssertEqual(SealModel.forLanguage(Locale(identifier: "he")), .hebrewZipformer)
        XCTAssertEqual(SealModel.forLanguage(Locale(identifier: "iw-IL")), .hebrewZipformer, "the old code for Hebrew")
        XCTAssertEqual(SealModel.forLanguage(Locale(identifier: "en-IN")), .parakeetUltra)
        XCTAssertNil(SealModel.forLanguage(Locale(identifier: "ar-SA")))
    }
}

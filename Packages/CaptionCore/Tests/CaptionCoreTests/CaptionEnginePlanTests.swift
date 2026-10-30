import CaptionCore
import XCTest

/// #37 with Parakeet on main (#155), then #234: the engine is made for the caption language she chose, and that
/// language picks it. Parakeet for every language where it matched or beat Apple's engine on FLEURS
/// (docs/perf/language-accuracy-comparison.md), Apple's engine in that language for the rest, and Apple's fallback
/// keeps her language too. Before #37, the app made every engine for en-US, so Spanish captions came out as English.
final class CaptionEnginePlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let plenty: UInt64 = 2_000_000_000

    private func plan(_ id: String, choice: CaptionEngineChoice = .parakeet, modelPresent: Bool = true,
                      memory: UInt64? = nil, fallbacks: [Date] = []) -> CaptionEnginePlan {
        CaptionEnginePlan.make(captionLanguage: Locale(identifier: id), choice: choice, now: now,
                               recentFallbacks: fallbacks, availableMemory: memory ?? plenty, modelPresent: modelPresent)
    }

    func testEnglishRunsParakeetAndAppleFallbackStaysInThatEnglish() {
        let p = plan("en-GB")
        XCTAssertEqual(p.selection.engine, .parakeet)
        XCTAssertEqual(p.locale.identifier(.bcp47), "en-GB")
    }

    func testEveryRegionOfAWonLanguageRunsParakeetInItsOwnLocale() {
        // Parakeet takes no language (it hears it), so every region of a won language goes to it; the locale is kept
        // for Apple's fallback and the language checks.
        for id in ["es-ES", "es-MX", "es-US", "es-CL", "fr-FR", "fr-CA", "fr-BE", "fr-CH", "de-DE", "de-AT", "de-CH"]
            + CaptionEngineRoutingExpectations.extraWon {
            let p = plan(id)
            XCTAssertEqual(p.selection, EngineSelection(engine: .parakeet, reason: nil), id)
            XCTAssertEqual(p.locale.identifier(.bcp47), id)
        }
    }

    func testALostOrUncoveredLanguageRunsAppleInThatLanguage() {
        for id in ["ja-JP", "ko-KR", "zh-CN", "zh-TW", "zh-HK", "yue-CN"] + CaptionEngineRoutingExpectations.lost {
            let p = plan(id)
            XCTAssertEqual(p.selection, EngineSelection(engine: .apple, reason: .locale), id)
            XCTAssertEqual(p.locale.identifier(.bcp47), id)
        }
    }

    func testTheTableIsExactlyTheMeasuredWins() {
        // One line per win (ADR 0029): adding a language without its measurement should fail here.
        XCTAssertEqual(CaptionEngineRouting.parakeetLanguages,
                       Set(["en", "es", "fr", "de"] + CaptionEngineRoutingExpectations.extraWon.map { String($0.prefix(2)) }))
    }

    func testAWonLanguageFallsBackToAppleInItsOwnLanguage() {
        for id in ["es-MX", "fr-CA", "de-DE"] {
            XCTAssertEqual(plan(id, modelPresent: false).selection.reason, .modelMissing, id)
            XCTAssertEqual(plan(id, modelPresent: false).locale.identifier(.bcp47), id)
            XCTAssertEqual(plan(id, memory: 1).selection, EngineSelection(engine: .apple, reason: .lowMemory), id)
            XCTAssertEqual(plan(id, fallbacks: [now.addingTimeInterval(-60), now.addingTimeInterval(-30)]).selection.reason,
                           .repeatedFallbacks, id)
        }
        // Mid-session, a memory warning or critical heat moves any Parakeet session to Apple, whatever the language.
        XCTAssertEqual(EngineFallbackPolicy.action(for: .memoryWarning, running: .parakeet), .switchToApple)
        XCTAssertEqual(EngineFallbackPolicy.action(for: .thermal(.critical), running: .parakeet), .switchToApple)
    }

    func testAnApplePickStillUsesHerLanguage() {
        XCTAssertEqual(plan("es-MX", choice: .apple).selection, EngineSelection(engine: .apple, reason: nil))
        XCTAssertEqual(plan("es-MX", choice: .apple).locale.identifier(.bcp47), "es-MX")
    }
}

/// Italian and Portuguese, filled in from the #234 measurement.
enum CaptionEngineRoutingExpectations {
    static let extraWon = ["it-IT", "it-CH"]  // #234: 2.2% (1.8–2.5) vs Apple 3.6% (3.1–4.1)
    static let lost: [String] = []
}

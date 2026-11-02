@testable import CaptionCore
import XCTest

/// #245, root cause from the owner's iPad: picking French in the partner's half started a silent download of Apple's
/// French speech files inside the engine's start, and Stop waited for it. The owner's rule (2026-10-30): everything is
/// set up up front, in Settings. The split never downloads, and its lists show only fully ready languages: the speech
/// model on the device and the translation pair downloaded. Fewer than two ready, and Face to face opens that setup.
final class FaceToFaceSetupTests: XCTestCase {
    private func l(_ id: String) -> Locale { Locale(identifier: id) }
    private func ids(_ ls: [Locale]) -> [String] { ls.map(\.identifier) }
    private func pairs(_ list: [(String, String)]) -> (Locale, Locale) -> Bool {
        let keys = Set(list.map { FaceToFaceReadyLanguages.pairKey(l($0.0), l($0.1)) })
        return { keys.contains(FaceToFaceReadyLanguages.pairKey($0, $1)) }
    }
    private func ready(_ candidates: [String], speech: [String], pairs list: [(String, String)]) -> FaceToFaceReadyLanguages {
        FaceToFaceReadyLanguages(candidates: candidates.map(l), speechInstalled: speech.map(l), pairInstalled: pairs(list))
    }

    // MARK: offered = ready only

    func testALanguageWithItsSpeechModelAndPairDownloadedIsOffered() {
        let r = ready(["en-US", "es-ES"], speech: ["en-US", "es-ES"], pairs: [("en-US", "es-ES")])
        XCTAssertEqual(ids(r.languages), ["en-US", "es-ES"])
    }

    func testALanguageWhoseSpeechModelIsntOnTheDeviceIsNotOffered() {
        // The owner's iPad: French was offered, and picking it downloaded Apple's French speech files inside the start.
        let r = ready(["en-US", "es-ES", "fr-FR"], speech: ["en-US", "es-ES"],
                      pairs: [("en-US", "es-ES"), ("en-US", "fr-FR"), ("es-ES", "fr-FR")])
        XCTAssertEqual(ids(r.languages), ["en-US", "es-ES"])
    }

    func testALanguageWithNoDownloadedTranslationPairIsNotOffered() {
        let r = ready(["en-US", "es-ES", "fr-FR"], speech: ["en-US", "es-ES", "fr-FR"], pairs: [("en-US", "es-ES")])
        XCTAssertEqual(ids(r.languages), ["en-US", "es-ES"], "French can't be translated to or from anything here yet")
    }

    func testTheInstalledRegionIsTheOneOffered() {
        // Into is es-ES; the speech model on the device is es-MX. The engine must start in es-MX, never fetch es-ES.
        let r = ready(["en-US", "es-ES"], speech: ["en-US", "es-MX"], pairs: [("en-US", "es-MX")])
        XCTAssertEqual(ids(r.languages), ["en-US", "es-MX"])
    }

    func testRegionsOfOneLanguageAreOneLanguage() {
        let r = ready(["en-US", "en-GB", "es-ES"], speech: ["en-US", "en-GB", "es-ES"], pairs: [("en-US", "es-ES")])
        XCTAssertEqual(ids(r.languages), ["en-US", "es-ES"])
    }

    func testAPairIsReadyEitherWayRound() {
        let r = ready(["en-US", "es-ES"], speech: ["en-US", "es-ES"], pairs: [("es-ES", "en-US")])
        XCTAssertTrue(r.pairReady(l("en-US"), l("es-ES")))
        XCTAssertTrue(r.pairReady(l("es-ES"), l("en-US")))
    }

    func testAPairIsKeyedByLanguageNotRegion() {
        XCTAssertEqual(FaceToFaceReadyLanguages.pairKey(l("en-US"), l("es-MX")), FaceToFaceReadyLanguages.pairKey(l("es-ES"), l("en-GB")))
    }

    // MARK: each half's list

    func testOnceTheOtherHalfPicksAHalfOffersOnlyLanguagesWithAReadyPairToIt() {
        // en↔es and en↔fr are downloaded, es↔fr isn't: with Español picked across, French would translate nothing.
        let r = ready(["en-US", "es-ES", "fr-FR"], speech: ["en-US", "es-ES", "fr-FR"],
                      pairs: [("en-US", "es-ES"), ("en-US", "fr-FR")])
        var split = FaceToFaceSplit()
        XCTAssertEqual(ids(r.choices(for: .owner, in: split, name: \.identifier)), ["en-US", "es-ES", "fr-FR"])
        split.pick(l("es-ES"), for: .partner)
        XCTAssertEqual(ids(r.choices(for: .owner, in: split, name: \.identifier)), ["en-US"])
    }

    // MARK: Face to face opens setup instead

    func testWithTwoReadyLanguagesFaceToFaceOpensTheSplit() {
        let r = ready(["en-US", "es-ES"], speech: ["en-US", "es-ES"], pairs: [("en-US", "es-ES")])
        XCTAssertEqual(r.opening, .split)
    }

    func testWithFewerThanTwoReadyFaceToFaceOpensSetupAndSaysWhyInOneLine() {
        // The owner's iPad: the caption language was ready, Into was set but its speech model and pack weren't on it.
        let r = ready(["en-US", "fr-FR"], speech: ["en-US"], pairs: [])
        XCTAssertEqual(r.opening, .setup)
        XCTAssertTrue(r.languages.isEmpty, "English alone has nothing to translate with")
        XCTAssertEqual(FaceToFaceReadyLanguages.setupReason,
                       "Face to face needs two languages ready on this device. Set them up here first.")
    }

    func testNoCandidatesAtAllOpensSetup() {
        XCTAssertEqual(ready([], speech: [], pairs: []).opening, .setup)
    }

    // MARK: nothing in the split calls an installer

    func testTheSplitsSpeechEngineNeverDownloadsAMissingModel() async {
        let installs = Counter()
        let backend = AppleSpeechBackend(locale: l("fr-FR"), model: .mustBeOnDevice,
                                         isInstalled: { _ in false },
                                         install: { _, _ in installs.add() })
        do {
            try await backend.prepare()
            XCTFail("a missing model must fail the start at once, not download")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .speechModelNotOnDevice)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(installs.value, 0)
    }

    func testOneWayCaptionsStillFetchTheirModelAsBefore() async {
        let installs = Counter()
        let backend = AppleSpeechBackend(locale: l("fr-FR"), model: .downloadIfNeeded,
                                         isInstalled: { _ in false },
                                         install: { _, _ in installs.add(); throw CancellationError() })
        _ = try? await backend.prepare()
        XCTAssertEqual(installs.value, 1)
    }

    func testAMissingModelIsSaidInPlainWordsWithWhereToFixIt() {
        XCTAssertEqual(FailureReason.plainLanguage(for: TranscriptionError.speechModelNotOnDevice),
                       "This language isn't set up on this device. Set it up in Settings")
    }

    // MARK: never trapped

    /// #245 item 1: Stop is her half's control in every state but paused, where a way out sits beside Start.
    func testThereIsAlwaysAWayOut() {
        var s = FaceToFaceSplit()
        XCTAssertEqual(s.control, .stop, "nothing picked")
        s.pick(l("en-US"), for: .owner)
        XCTAssertEqual(s.control, .stop, "one half picked")
        s.pick(l("fr-FR"), for: .partner)
        XCTAssertEqual(s.control, .stop, "both picked")
        s.openList(.owner)
        XCTAssertEqual(s.control, .stop, "picking again")
        s.stoppedOnTheirOwn()
        XCTAssertTrue(s.control == .stop || s.offersLeaveBesideStart, "paused")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func add() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}

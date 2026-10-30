import CaptionCore
import XCTest

/// #245, root cause from the owner's iPad: picking French in the partner's half started a silent download of Apple's
/// French speech files inside the engine's start, and Stop waited for it. A language is now only started once its
/// speech engine is on the device; one that isn't is downloaded first, in its half, with progress, and Stop drops it.
final class FaceToFaceSetupTests: XCTestCase {
    private func l(_ id: String) -> Locale { Locale(identifier: id) }

    // MARK: what a tap does

    func testTappingAnInstalledLanguageStartsItInTheInstalledRegion() {
        XCTAssertEqual(FaceToFace.pickPlan(l("fr-FR"), speechInstalled: [l("en-US"), l("fr-CA")]), .start(l("fr-CA")))
    }

    func testTappingALanguageThatIsntOnTheDeviceDownloadsItFirstAndStartsNothing() {
        XCTAssertEqual(FaceToFace.pickPlan(l("fr-FR"), speechInstalled: [l("en-US")]), .download(l("fr-FR")))
    }

    // MARK: the list

    func testAReadyLanguageIsJustItsName() {
        XCTAssertEqual(FaceToFace.listLabel("Français", ready: true), "Français")
    }

    func testALanguageThatIsntReadyIsMarkedAsADownload() {
        XCTAssertEqual(FaceToFace.listLabel("Français", ready: false), "Français · Download")
    }

    // MARK: each half's download

    func testADownloadShowsInItsHalfOnlyWithProgress() {
        var d = FaceToFaceDownloads()
        let ticket = d.begin(l("fr-FR"), for: .partner)
        XCTAssertNotNil(ticket)
        d.progress(0.4, for: ticket!)
        XCTAssertEqual(d.byHalf[.partner], FaceToFaceDownload(locale: l("fr-FR"), progress: .downloading(0.4)))
        XCTAssertNil(d.byHalf[.owner])
    }

    func testAFinishedDownloadHandsBackTheLanguageToPickAndClearsTheHalf() {
        var d = FaceToFaceDownloads()
        let ticket = d.begin(l("fr-FR"), for: .partner)!
        XCTAssertEqual(d.finished(ticket, outcome: .installed), l("fr-FR"))
        XCTAssertNil(d.byHalf[.partner])
    }

    func testAFailedDownloadStaysInItsHalfWithWhatToDoAndTappingAgainRetries() {
        var d = FaceToFaceDownloads()
        let first = d.begin(l("fr-FR"), for: .partner)!
        XCTAssertNil(d.finished(first, outcome: .failed(.offline)))
        XCTAssertEqual(d.byHalf[.partner]?.progress, .failed(.offline))
        XCTAssertNotNil(d.begin(l("fr-FR"), for: .partner), "the same language tapped again tries again")
        XCTAssertEqual(d.byHalf[.partner]?.progress, .downloading(0))
    }

    func testTappingTheSameLanguageWhileItDownloadsStartsNoSecondDownload() {
        var d = FaceToFaceDownloads()
        _ = d.begin(l("fr-FR"), for: .partner)
        XCTAssertNil(d.begin(l("fr-FR"), for: .partner))
    }

    func testPickingAnotherLanguageInThatHalfLeavesTheDownloadBehind() {
        var d = FaceToFaceDownloads()
        let french = d.begin(l("fr-FR"), for: .partner)!
        XCTAssertTrue(d.drop(.partner), "there was one to cancel")
        XCTAssertNil(d.byHalf[.partner])
        d.progress(0.9, for: french)
        XCTAssertNil(d.finished(french, outcome: .installed), "a download left behind never starts its language")
        XCTAssertNil(d.byHalf[.partner])
        XCTAssertFalse(d.drop(.partner))
    }

    func testANewDownloadInAHalfReplacesTheOldOneAndTheOldOneIsIgnored() {
        var d = FaceToFaceDownloads()
        let french = d.begin(l("fr-FR"), for: .partner)!
        let german = d.begin(l("de-DE"), for: .partner)!
        XCTAssertNil(d.finished(french, outcome: .installed))
        XCTAssertEqual(d.byHalf[.partner]?.locale, l("de-DE"))
        XCTAssertEqual(d.finished(german, outcome: .installed), l("de-DE"))
    }

    func testLeavingTheSplitDropsEveryDownload() {
        var d = FaceToFaceDownloads()
        let a = d.begin(l("fr-FR"), for: .partner)!
        let b = d.begin(l("de-DE"), for: .owner)!
        d.dropAll()
        XCTAssertTrue(d.byHalf.isEmpty)
        XCTAssertNil(d.finished(a, outcome: .installed))
        d.progress(0.5, for: b)
        XCTAssertTrue(d.byHalf.isEmpty, "late progress from a dropped download shows nowhere")
    }

    func testACancelledDownloadClearsItsHalfAndStartsNothing() {
        var d = FaceToFaceDownloads()
        let t = d.begin(l("fr-FR"), for: .partner)!
        XCTAssertNil(d.finished(t, outcome: .cancelled))
        XCTAssertNil(d.byHalf[.partner])
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

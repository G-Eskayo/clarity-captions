import CaptionCore
import XCTest

/// #245 item 2 (owner, TestFlight 1.1 (9), iPad Pro 12.9"): the split sat silent. Both halves had picked, nothing
/// captioned, and nothing said why. Each half now always says what's happening, in plain words.
final class FaceToFaceStatusTests: XCTestCase {
    private let en = Locale(identifier: "en-US")
    private let es = Locale(identifier: "es-ES")
    private func status(_ half: FaceToFaceHalf, _ split: FaceToFaceSplit, _ state: CaptionState) -> FaceToFaceStatus {
        FaceToFaceStatus.of(half, split: split, state: state)
    }
    private func picked(owner: Locale? = nil, partner: Locale? = nil) -> FaceToFaceSplit {
        var s = FaceToFaceSplit()
        if let owner { s.pick(owner, for: .owner) }
        if let partner { s.pick(partner, for: .partner) }
        return s
    }

    // MARK: nothing picked, one picked

    func testAHalfThatHasntPickedSaysTapYourLanguage() {
        XCTAssertEqual(status(.owner, FaceToFaceSplit(), .idle), .tapYourLanguage)
        XCTAssertEqual(status(.partner, picked(owner: en), .listening), .tapYourLanguage)
        XCTAssertEqual(FaceToFaceStatus.tapYourLanguage.words(for: .owner), "Tap your language to start")
    }

    func testAHalfPickingAgainSaysTapToSwitch() {
        var s = picked(owner: en, partner: es)
        s.openList(.owner)
        XCTAssertEqual(status(.owner, s, .listening), .tapToSwitch)
    }

    func testThePickedHalfSaysItIsListeningAndWaitingForTheOther() {
        let s = picked(owner: en)
        XCTAssertEqual(status(.owner, s, .listening), .listeningWaitingForOther)
        XCTAssertEqual(FaceToFaceStatus.listeningWaitingForOther.words(for: .owner),
                       "Listening. Waiting for the other person to pick")
    }

    func testStartingIsSaidWhileTheEnginesLoad() {
        XCTAssertEqual(status(.owner, picked(owner: en, partner: es), .preparing), .starting)
        XCTAssertEqual(status(.partner, picked(owner: en, partner: es), .preparing), .starting)
    }

    func testBetweenAPickAndTheEngineStartingItSaysStartingNotNothing() {
        XCTAssertEqual(status(.owner, picked(owner: en), .idle), .starting)
    }

    func testBothPickedAndListening() {
        XCTAssertEqual(status(.owner, picked(owner: en, partner: es), .listening), .listening)
        XCTAssertEqual(status(.partner, picked(owner: en, partner: es), .listening), .listening)
    }

    // MARK: stopped

    func testAFailureIsSaidInBothHalvesWithWhatToDo() {
        var s = picked(owner: en, partner: es)
        s.stoppedOnTheirOwn()
        let st = status(.owner, s, .failed("The speaker model didn't install — tap to try again"))
        XCTAssertEqual(st, .failed("The speaker model didn't install — tap to try again"))
        XCTAssertEqual(status(.partner, s, .failed("x")), .failed("x"))
        XCTAssertEqual(FaceToFaceStatus.failed("x").words(for: .owner), "x. Tap Start to try again")
        XCTAssertEqual(FaceToFaceStatus.failed("x").words(for: .partner), "x")
    }

    func testPausedSaysStartInHerHalfOnly() {
        var s = picked(owner: en, partner: es)
        s.stoppedOnTheirOwn()
        XCTAssertEqual(status(.owner, s, .pausedQuiet(minutes: 5)), .paused)
        XCTAssertEqual(FaceToFaceStatus.paused.words(for: .owner), "Paused. Tap Start to carry on")
        XCTAssertEqual(FaceToFaceStatus.paused.words(for: .partner), "Paused")
    }

    func testPausedAfterAFailureStillHasAWayOut() {
        var s = picked(owner: en, partner: es)
        XCTAssertFalse(s.offersLeaveBesideStart, "Stop itself leaves while captioning")
        s.stoppedOnTheirOwn()
        XCTAssertEqual(s.control, .start)
        XCTAssertTrue(s.offersLeaveBesideStart, "Start alone could fail again and again: the split must still leave")
    }

    func testEveryStatusHasWords() {
        let all: [FaceToFaceStatus] = [.tapYourLanguage, .tapToSwitch, .starting, .listening, .listeningWaitingForOther,
                                       .paused, .failed("x")]
        for st in all { for half in [FaceToFaceHalf.owner, .partner] { XCTAssertFalse(st.words(for: half).isEmpty, "\(st)") } }
    }
}

/// #245 item 3: a language whose speech engine isn't on the device was offered like any other; picking it started a
/// silent download inside the engine's start. A language is offered as the installed region the engine will use.
final class FaceToFaceReadinessTests: XCTestCase {
    private func l(_ id: String) -> Locale { Locale(identifier: id) }

    func testALanguageIsReadyWhenItsSpeechEngineIsInstalled() {
        let installed = [l("en-US"), l("fr-FR")]
        XCTAssertEqual(FaceToFace.readyLocale(for: l("en-US"), speechInstalled: installed)?.identifier, "en-US")
        XCTAssertNil(FaceToFace.readyLocale(for: l("es-ES"), speechInstalled: installed), "Spanish isn't on this iPad")
    }

    func testAnotherInstalledRegionOfTheSameLanguageIsReadyAndIsTheOneUsed() {
        let installed = [l("es-MX")]
        XCTAssertEqual(FaceToFace.readyLocale(for: l("es-ES"), speechInstalled: installed)?.identifier, "es-MX")
    }

    func testTheExactRegionIsPreferredWhenSeveralAreInstalled() {
        let installed = [l("en-GB"), l("en-US")]
        XCTAssertEqual(FaceToFace.readyLocale(for: l("en-US"), speechInstalled: installed)?.identifier, "en-US")
    }

    func testEveryRowOfTheListCaptionsInAnInstalledRegion() {
        // The Into language (es-ES) isn't installed, but es-MX is: picking Español must run the engine in es-MX.
        let installed = [l("en-US"), l("es-MX")]
        let offered = FaceToFace.offered(captionLanguage: l("en-US"), into: l("es-ES"), speechInstalled: installed,
                                         translatable: ["en", "es"])
        let rows = FaceToFace.choices(downloaded: offered, takenByOtherHalf: nil, name: { $0.identifier })
        XCTAssertEqual(rows.map { FaceToFace.readyLocale(for: $0, speechInstalled: installed)?.identifier }, ["en-US", "es-MX"])
    }
}

/// #245 item 1: the split's starts, restarts and Stop ran one after another, so a start that never finished held
/// Stop forever. Leaving drops everything still queued, and work queued after it never waits for the abandoned work.
@MainActor
final class SplitWorkQueueTests: XCTestCase {
    private func eventually(_ what: String, timeout: Double = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition(), "timed out waiting for: \(what)")
    }

    func testWorkRunsOneAfterAnother() async {
        let q = SplitWorkQueue()
        var order: [Int] = []
        q.enqueue { _ in try? await Task.sleep(nanoseconds: 30_000_000); order.append(1) }
        q.enqueue { _ in order.append(2) }
        await q.drained()
        XCTAssertEqual(order, [1, 2])
    }

    func testLeavingDropsQueuedWorkAndNewWorkDoesntWaitForTheHungOne() async {
        let q = SplitWorkQueue()
        var release: CheckedContinuation<Void, Never>?
        var hungStarted = false, hungSawCurrent: Bool?, queuedRan = false, afterRan = false
        q.enqueue { isCurrent in
            hungStarted = true
            await withCheckedContinuation { release = $0 }
            hungSawCurrent = isCurrent()
        }
        q.enqueue { _ in queuedRan = true }
        await eventually("the first work is running") { hungStarted }

        q.cancelAll()
        q.enqueue { _ in afterRan = true }
        await eventually("work queued after leaving runs at once") { afterRan }
        XCTAssertFalse(queuedRan, "work queued before leaving never runs")

        release?.resume()
        await eventually("the abandoned work ends") { hungSawCurrent != nil }
        XCTAssertEqual(hungSawCurrent, false, "the abandoned work knows it was left behind")
        XCTAssertFalse(queuedRan)
    }
}

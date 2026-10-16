import XCTest
@testable import CaptionCore

/// The how-to-use tour v3 (#137; approved 2026-10-15 from TestFlight build 3 feedback, mock-ups round4/01): four steps
/// the person controls. Every step but the last has [ Next ›], and the real action moves it on too. Nothing is on a
/// timer. Back and Skip tour stay; only the last step has [ Done ].
final class HowToUseTourTests: XCTestCase {

    private func tour(at step: TourStep) -> HowToUseTour {
        var tour = HowToUseTour()
        tour.begin()
        while tour.step != step, tour.step != nil { tour.did(.tappedNext) }
        XCTAssertEqual(tour.step, step)
        return tour
    }

    // MARK: four steps, in the mock-up's order

    func testFourStepsInTheMockUpsOrder() {
        XCTAssertEqual(TourStep.allCases, [.start, .captions, .pause, .done])
        XCTAssertEqual(tour(at: .pause).progress, "3 of 4")
    }

    func testNextWalksTheWholeTourOnItsOwn() {
        // "Show it all and let the user dictate when to go forward."
        var t = HowToUseTour()
        t.begin()
        for expected in [TourStep.captions, .pause, .done] {
            t.did(.tappedNext)
            XCTAssertEqual(t.step, expected)
        }
        XCTAssertEqual(t.step, .done)
        t.did(.tappedNext)                       // the last step has no Next: Next does nothing there
        XCTAssertEqual(t.step, .done)
        t.did(.tappedDone)
        XCTAssertNil(t.step)
        XCTAssertEqual(t.ending, .finished)
    }

    func testTheRealActionAlsoMovesItsStepOn() {
        var t = HowToUseTour()
        t.begin()
        t.did(.tappedStart)
        XCTAssertEqual(t.step, .captions)
        t.did(.tappedNext)
        t.did(.tappedStop)
        XCTAssertEqual(t.step, .done)
    }

    func testWordsAppearingDoNotMoveOnByThemselves() {
        // Step 2 stays until she taps Next: nothing reads on, nothing is timed.
        var t = tour(at: .captions)
        for action in [TourAction.captionShown, .followUpRead, .tappedSave, .saveMomentFinished, .clearedDim, .restoredDim,
                       .openedSettings, .closedSettings] {
            t.did(action)
            XCTAssertEqual(t.step, .captions, "\(action) must not move step 2 on")
        }
    }

    func testActionsForOtherStepsAreIgnored() {
        var t = tour(at: .start)
        t.did(.tappedStop)
        t.did(.tappedDone)
        XCTAssertEqual(t.step, .start)
        t = tour(at: .pause)
        t.did(.tappedStart)
        XCTAssertEqual(t.step, .pause)
    }

    func testEveryStepButTheLastHasNextAndOnlyTheLastHasDone() {
        for step in TourStep.allCases {
            let t = tour(at: step)
            XCTAssertEqual(t.hasNextButton, step != .done, "\(step)")
            XCTAssertEqual(t.hasDoneButton, step == .done, "\(step)")
            XCTAssertTrue(t.showsWords, "words are never hidden on a timer (\(step))")
        }
    }

    func testNothingInTheTourIsTimed() {
        // The follow-up beats that hid words after a few seconds are gone with tour v2.
        for step in TourStep.allCases { XCTAssertEqual(tour(at: step).phase, .waiting) }
    }

    // MARK: Back, Skip, replay

    func testEveryStepButTheFirstHasBackAndBackGoesOneStep() {
        XCTAssertFalse(tour(at: .start).canGoBack)
        var t = tour(at: .done)
        XCTAssertTrue(t.canGoBack)
        t.back()
        XCTAssertEqual(t.step, .pause)
    }

    func testSkipEndsTheTourFromAnyStep() {
        for step in TourStep.allCases {
            var t = tour(at: step)
            t.skip()
            XCTAssertNil(t.step)
            XCTAssertEqual(t.ending, .skipped)
        }
    }

    func testNothingMovesWhenTheTourIsntRunning() {
        var t = HowToUseTour()
        t.did(.tappedNext)
        t.did(.tappedStart)
        XCTAssertNil(t.step)
        XCTAssertNil(t.ending)
    }

    func testReplayStartsAgainFromTheFirstStep() {
        var t = tour(at: .done)
        t.did(.tappedDone)
        t.begin()
        XCTAssertEqual(t.step, .start)
        XCTAssertNil(t.ending)
    }

    // MARK: what's lit, and the words

    func testWhatIsLitOnEachStep() {
        XCTAssertEqual(tour(at: .start).focus, TourFocus(lit: .start, answers: .start, dims: true))
        XCTAssertEqual(tour(at: .captions).focus, TourFocus(lit: .captionArea, answers: nil, dims: true))
        XCTAssertEqual(tour(at: .pause).focus, TourFocus(lit: .stop, answers: .stop, dims: true))
        XCTAssertEqual(tour(at: .done).focus, TourFocus(lit: .gear, answers: nil, dims: true))
    }

    func testTheWordsAreTheApprovedOnes() {
        XCTAssertEqual(tour(at: .start).words, TourWords(title: "Set the phone flat on the table.",
                                                       message: "Between you and whoever's talking. Then tap Start captions."))
        XCTAssertEqual(tour(at: .captions).words.title, "Words show up here as people talk.")
        XCTAssertTrue(tour(at: .captions).words.message.contains("so it can mix people up"))
        XCTAssertEqual(tour(at: .pause).words.title, "Tap ✕ to pause.")
        XCTAssertTrue(tour(at: .pause).words.message.contains("30 days"))
        XCTAssertEqual(tour(at: .done).words.title, "That's it.")
        XCTAssertTrue(tour(at: .done).words.message.contains("You can replay this in Settings."))
    }

    func testTheLastStepDoesNotExplainTheObvious() {
        // "you don't really need to explain the obvious UI elements"
        let text = tour(at: .done).words.message.lowercased()
        for obvious in ["copy", "hold on", "goes quiet"] { XCTAssertFalse(text.contains(obvious), obvious) }
    }

    func testNoWordPromisesToKnowWhoIsSpeaking() {
        let text = TourStep.allCases.map { let w = tour(at: $0).words; return "\(w.title) \(w.message)" }.joined(separator: " ").lowercased()
        for overclaim in ["who is speaking", "who's speaking", "name ", "names", "identif", "recogni"] {
            XCTAssertFalse(text.contains(overclaim), "tour words must not say \"\(overclaim)\"")
        }
    }

    // MARK: when it may start: never mid-conversation

    func testItStartsByItselfOnceAfterFirstRunOnAnEmptyIdleScreen() {
        XCTAssertTrue(TourGate.startsByItself(hasSeen: false, state: .idle, hasConversation: false, launchCovering: false))
    }

    func testItNeverStartsByItselfTwice() {
        XCTAssertFalse(TourGate.startsByItself(hasSeen: true, state: .idle, hasConversation: false, launchCovering: false))
    }

    func testItWaitsForTheLaunchAnimation() {
        XCTAssertFalse(TourGate.startsByItself(hasSeen: false, state: .idle, hasConversation: false, launchCovering: true))
    }

    func testItNeverStartsByItselfMidConversation() {
        XCTAssertFalse(TourGate.startsByItself(hasSeen: false, state: .listening, hasConversation: true, launchCovering: false))
        XCTAssertFalse(TourGate.startsByItself(hasSeen: false, state: .preparing, hasConversation: false, launchCovering: false))
        XCTAssertFalse(TourGate.startsByItself(hasSeen: false, state: .idle, hasConversation: true, launchCovering: false))
    }

    func testReplayFromSettingsWaitsUntilCaptioningIsPaused() {
        XCTAssertFalse(TourGate.canReplay(state: .listening))
        XCTAssertFalse(TourGate.canReplay(state: .preparing))
        XCTAssertTrue(TourGate.canReplay(state: .idle))
        XCTAssertTrue(TourGate.canReplay(state: .pausedQuiet(minutes: 5)))
        XCTAssertTrue(TourGate.canReplay(state: .failed("x")))
    }

    // MARK: the example, for a quiet room: two voices, text only

    func testTheExampleIsTwoVoicesWithTheMockUpsWords() {
        XCTAssertEqual(TourExample.lines.map(\.text), ["Hi, is this working? I can see what I'm saying.",
                                                       "Yep, it put me on my own line."])
        XCTAssertEqual(TourExample.lines.map(\.speaker), [0, 1])
    }

    func testTheExampleOnlyCountsWhenNothingElseWasSaid() {
        var stream = CaptionStream()
        for line in TourExample.lines { stream.apply(text: line.text, isFinal: true, speaker: line.speaker) }
        let exampleIDs = Set(stream.lines.map(\.id))
        XCTAssertTrue(TourExample.isOnlyExample(lines: stream.lines, exampleIDs: exampleIDs))
        stream.apply(text: "And a real sentence from the room.", isFinal: true, speaker: 2)
        XCTAssertFalse(TourExample.isOnlyExample(lines: stream.lines, exampleIDs: exampleIDs))
    }

    func testAnEmptyConversationIsNotAnExample() {
        XCTAssertFalse(TourExample.isOnlyExample(lines: [], exampleIDs: []))
    }

    func testTheExampleOfferWaitsForAQuietStretch() {
        XCTAssertFalse(TourExample.offersExample(secondsWithoutCaption: 2, isCaptioning: true))
        XCTAssertTrue(TourExample.offersExample(secondsWithoutCaption: TourExample.quietSeconds, isCaptioning: true))
        XCTAssertFalse(TourExample.offersExample(secondsWithoutCaption: 60, isCaptioning: false))
    }

    // MARK: seen, on the device only

    func testSeenIsRememberedAndStartsFalse() {
        let defaults = UserDefaults(suiteName: "tour-test-\(UUID().uuidString)")!
        let store = TourStore(defaults: defaults)
        XCTAssertFalse(store.hasSeen)
        store.markSeen()
        XCTAssertTrue(TourStore(defaults: defaults).hasSeen)
    }
}

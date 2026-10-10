import XCTest
@testable import CaptionCore

/// The how-to-use tour v2 (#121; approved in #120, mock-ups round3/01-02, flow from #117): eight steps on the real
/// screen. Each step moves on only when she really does it; there is no Next on an action step. Back and Skip tour are
/// on every step, and only the last one has a button to finish.
final class HowToUseTourTests: XCTestCase {

    /// Walks a fresh tour to `step`, doing each real action on the way.
    private func tour(at step: TourStep) -> HowToUseTour {
        var tour = HowToUseTour()
        tour.begin()
        let path: [TourAction] = [.tappedStart, .captionShown, .followUpRead, .tappedStop, .tappedSave, .saveMomentFinished,
                                  .followUpRead, .clearedDim, .restoredDim, .openedSettings, .closedSettings]
        for action in path where tour.step != step { tour.did(action) }
        XCTAssertEqual(tour.step, step)
        return tour
    }

    // MARK: order and advancing on the real action

    func testEightStepsInTheMockUpsOrder() {
        XCTAssertEqual(TourStep.allCases, [.start, .captions, .pause, .save, .clearDim, .holdBack, .gear, .done])
    }

    func testDoingEachRealActionWalksTheWholeTour() {
        var tour = HowToUseTour()
        tour.begin()
        XCTAssertEqual(tour.step, .start); XCTAssertEqual(tour.phase, .waiting)
        tour.did(.tappedStart);        XCTAssertEqual(tour.step, .captions)
        tour.did(.captionShown);       XCTAssertEqual(tour.step, .captions); XCTAssertEqual(tour.phase, .followUp)
        tour.did(.followUpRead);       XCTAssertEqual(tour.step, .pause)
        tour.did(.tappedStop);         XCTAssertEqual(tour.step, .save)
        tour.did(.tappedSave);         XCTAssertEqual(tour.step, .save); XCTAssertEqual(tour.phase, .savingMoment)
        tour.did(.saveMomentFinished); XCTAssertEqual(tour.step, .save); XCTAssertEqual(tour.phase, .followUp)
        tour.did(.followUpRead);       XCTAssertEqual(tour.step, .clearDim)
        tour.did(.clearedDim);         XCTAssertEqual(tour.step, .holdBack)
        tour.did(.restoredDim);        XCTAssertEqual(tour.step, .gear)
        tour.did(.openedSettings);     XCTAssertEqual(tour.step, .gear); XCTAssertEqual(tour.phase, .inSettings)
        tour.did(.closedSettings);     XCTAssertEqual(tour.step, .done)
        tour.did(.tappedDone)
        XCTAssertNil(tour.step)
        XCTAssertEqual(tour.ending, .finished)
    }

    func testEarlyActionsForLaterStepsAreIgnoredOnEveryStep() {
        let all: [TourAction] = [.tappedStart, .captionShown, .followUpRead, .tappedStop, .tappedSave, .saveMomentFinished,
                                 .clearedDim, .restoredDim, .openedSettings, .closedSettings, .tappedDone]
        for step in TourStep.allCases {
            let start = tour(at: step)
            for action in all where !TourStep.completes(step, phase: .waiting, action) {
                var t = start
                t.did(action)
                XCTAssertEqual(t.step, step, "\(action) must not move the tour off \(step)")
                XCTAssertEqual(t.phase, .waiting, "\(action) must not change \(step)'s phase")
            }
        }
    }

    func testNothingButReadingMovesAFollowUpOn() {
        var t = tour(at: .captions)
        t.did(.captionShown)
        for action in [TourAction.tappedStart, .tappedStop, .tappedSave, .clearedDim, .openedSettings, .tappedDone] {
            t.did(action)
            XCTAssertEqual(t.step, .captions); XCTAssertEqual(t.phase, .followUp)
        }
        t.did(.followUpRead)
        XCTAssertEqual(t.step, .pause)
    }

    func testSavesGreenMomentFinishesBeforeItsWordsAndBeforeStepFive() {
        var t = tour(at: .save)
        t.did(.tappedSave)
        XCTAssertEqual(t.phase, .savingMoment)
        XCTAssertFalse(t.showsWords, "[ ✔ ] → [ Saved ] plays out first, with no words over it")
        t.did(.followUpRead)                      // a reading beat can't skip the green moment
        XCTAssertEqual(t.step, .save); XCTAssertEqual(t.phase, .savingMoment)
        t.did(.saveMomentFinished)
        XCTAssertEqual(t.phase, .followUp)
        XCTAssertTrue(t.showsWords)
        XCTAssertEqual(t.words, TourWords(title: "Saved.", message: "It stays green until somebody says something new."))
        t.did(.followUpRead)
        XCTAssertEqual(t.step, .clearDim)
    }

    func testAlreadySavedGoesStraightToTheSavedWords() {
        var t = tour(at: .save)
        t.alreadySaved()
        XCTAssertEqual(t.phase, .followUp)
        var other = tour(at: .pause)
        other.alreadySaved()                      // only means something on the Save step
        XCTAssertEqual(other.step, .pause); XCTAssertEqual(other.phase, .waiting)
    }

    func testTheGearStepEndsWhenSheComesBackNotWhenSettingsOpens() {
        var t = tour(at: .gear)
        t.did(.closedSettings)                    // can't come back before going
        XCTAssertEqual(t.phase, .waiting)
        t.did(.openedSettings)
        XCTAssertEqual(t.step, .gear); XCTAssertEqual(t.phase, .inSettings)
        t.did(.closedSettings)
        XCTAssertEqual(t.step, .done)
    }

    func testActionsDoNothingWhenTheTourIsntRunning() {
        var t = HowToUseTour()
        t.did(.tappedStart)
        XCTAssertNil(t.step)
        XCTAssertNil(t.ending)
    }

    func testDoingTheSameThingTwiceOnlyAdvancesOnce() {
        var t = HowToUseTour()
        t.begin()
        t.did(.tappedStart)
        t.did(.tappedStart)
        XCTAssertEqual(t.step, .captions)
    }

    // MARK: Back and Skip on every step; [ Done ] only on the last

    func testBackGoesToTheStepBeforeAndWaitsForItsActionAgain() {
        var t = tour(at: .clearDim)
        t.back()
        XCTAssertEqual(t.step, .save); XCTAssertEqual(t.phase, .waiting)
        t.back(); XCTAssertEqual(t.step, .pause)
        t.back(); XCTAssertEqual(t.step, .captions)
        t.back(); XCTAssertEqual(t.step, .start)
        t.back(); XCTAssertEqual(t.step, .start, "Back on the first step stays put")
        XCTAssertFalse(t.canGoBack)
    }

    func testBackFromAFollowUpOrSettingsGoesToThePreviousStep() {
        var t = tour(at: .captions)
        t.did(.captionShown)
        t.back()
        XCTAssertEqual(t.step, .start); XCTAssertEqual(t.phase, .waiting)
        var g = tour(at: .gear)
        g.did(.openedSettings)
        g.back()
        XCTAssertEqual(g.step, .holdBack); XCTAssertEqual(g.phase, .waiting)
    }

    func testEveryStepButTheFirstHasBack() {
        for step in TourStep.allCases {
            XCTAssertEqual(tour(at: step).canGoBack, step != .start, "\(step)")
        }
    }

    func testSkipEndsTheTourFromAnyStepAndPhase() {
        for step in TourStep.allCases {
            var t = tour(at: step)
            t.skip()
            XCTAssertNil(t.step)
            XCTAssertEqual(t.ending, .skipped)
        }
        var mid = tour(at: .save)
        mid.did(.tappedSave)
        mid.skip()
        XCTAssertEqual(mid.ending, .skipped)
    }

    func testOnlyTheLastStepHasAFinishButton() {
        for step in TourStep.allCases {
            XCTAssertEqual(tour(at: step).hasDoneButton, step == .done, "\(step)")
        }
        var t = tour(at: .gear)
        t.did(.tappedDone)                        // there is no Next to press on an action step
        XCTAssertEqual(t.step, .gear)
    }

    func testNothingMovesAfterTheTourEnds() {
        var t = tour(at: .done)
        t.did(.tappedDone)
        t.did(.tappedStart)
        t.back()
        XCTAssertNil(t.step)
        XCTAssertEqual(t.ending, .finished)
    }

    func testCountsEightSteps() {
        XCTAssertEqual(tour(at: .start).progress, "1 of 8")
        XCTAssertEqual(tour(at: .done).progress, "8 of 8")
    }

    func testReplayStartsAgainFromTheFirstStep() {
        var t = tour(at: .done)
        t.did(.tappedDone)
        t.begin()
        XCTAssertEqual(t.step, .start); XCTAssertEqual(t.phase, .waiting)
        XCTAssertNil(t.ending)
    }

    // MARK: only the lit control answers

    func testOnlyTheLitControlAnswersOnEachStep() {
        XCTAssertEqual(tour(at: .start).focus, TourFocus(lit: .start, answers: .start, dims: true))
        var two = tour(at: .captions)
        XCTAssertEqual(two.focus, TourFocus(lit: .stop, answers: nil, dims: true),
                       "waiting for a voice: ✕ shows (round3/01 step 2) but nothing answers")
        two.did(.captionShown)
        XCTAssertEqual(two.focus, TourFocus(lit: .captionArea, answers: nil, dims: true), "her words lit, nothing answers")
        XCTAssertEqual(tour(at: .pause).focus, TourFocus(lit: .stop, answers: .stop, dims: true))
        var four = tour(at: .save)
        XCTAssertEqual(four.focus, TourFocus(lit: .save, answers: .save, dims: true))
        four.did(.tappedSave)
        XCTAssertEqual(four.focus, TourFocus(lit: .save, answers: nil, dims: true), "no second tap during the green moment")
        XCTAssertEqual(tour(at: .clearDim).focus, TourFocus(lit: nil, answers: .veil, dims: false), "the whole dim is lit")
        XCTAssertEqual(tour(at: .holdBack).focus, TourFocus(lit: nil, answers: .captionArea, dims: false))
        var seven = tour(at: .gear)
        XCTAssertEqual(seven.focus, TourFocus(lit: .gear, answers: .gear, dims: true))
        seven.did(.openedSettings)
        XCTAssertEqual(seven.focus, TourFocus(lit: nil, answers: .everything, dims: false), "Settings works while she looks")
        XCTAssertEqual(tour(at: .done).focus, TourFocus(lit: nil, answers: nil, dims: true))
    }

    // MARK: the approved words (#120, every step "keep as drafted")

    func testTheWordsAreExactlyTheApprovedOnes() {
        XCTAssertEqual(tour(at: .start).words, TourWords(title: "Set the phone flat on the table.",
                                                         message: "Between you and whoever's talking. Then tap Start captions."))
        var two = tour(at: .captions)
        XCTAssertEqual(two.words, TourWords(title: "Say something.", message: "Your words show up here as you talk."))
        two.did(.captionShown)
        XCTAssertEqual(two.words, TourWords(title: "That's you.",
                                            message: "Each voice gets its own line and label. Seal goes by the sound of the voice, so it can mix people up. It doesn't know who anyone is."))
        XCTAssertEqual(tour(at: .pause).words, TourWords(title: "Tap ✕ to pause.",
                                                         message: "Nothing gets lost. Start captions picks up where you left off."))
        XCTAssertEqual(tour(at: .save).words, TourWords(title: "Tap [ Save ].", message: "Keeps it on this phone for 30 days."))
        XCTAssertEqual(tour(at: .clearDim).words, TourWords(title: "Tap anywhere on the dim.",
                                                            message: "It clears so you can read and scroll back."))
        XCTAssertEqual(tour(at: .holdBack).words, TourWords(title: "Hold an empty spot.", message: "The buttons come back."))
        XCTAssertEqual(tour(at: .gear).words, TourWords(title: "Tap the gear.",
                                                        message: "Colors, text size and lettering. Tap it again to come back."))
        XCTAssertEqual(tour(at: .done).words, TourWords(title: "That's it.",
                                                        message: "[ New ] clears the screen for the next conversation. It asks once first.\n\nHold on any words to copy them.\n\nIf it goes quiet for a while, captions pause on their own.\n\nYou can replay this in Settings."))
    }

    func testNoWordPromisesToKnowWhoIsSpeaking() {
        // Honest claims (#120): Seal tells voices apart; it doesn't know who anyone is, and naming is gone in v1.
        var t = tour(at: .captions)
        t.did(.captionShown)
        var all = [t.words]
        for step in TourStep.allCases { all.append(tour(at: step).words) }
        let text = all.map { "\($0.title) \($0.message)" }.joined(separator: " ").lowercased()
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

    func testFollowUpsGiveTimeToRead() {
        // "That's you." is the longest message; it gets the longer reading beat.
        XCTAssertGreaterThan(TourTiming.followUpSeconds(for: .captions), TourTiming.followUpSeconds(for: .save))
        XCTAssertGreaterThanOrEqual(TourTiming.followUpSeconds(for: .save), 3)
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

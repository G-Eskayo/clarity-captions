import XCTest
@testable import CaptionCore

/// ADR 0013: first-time users get a guided tour showing how to use the app. The tour is a pure
/// state machine (step order, action-based advancement, resettable) so it's testable in isolation
/// before the SwiftUI layer (which can't be tested here).
final class TourTests: XCTestCase {

    // MARK: - Step order and initialization

    func testStepsAreInTheRightOrder() {
        XCTAssertEqual(TourStep.allCases, [.start, .listening, .pause, .save, .copy, .gear])
    }

    func testFreshStateStartsAtTheFirstStep() {
        let state = TourState()
        XCTAssertEqual(state.step, .start)
        XCTAssertTrue(state.isActive)
    }

    func testReplayStartingStepDefaultsToStart() {
        let state1 = TourState()
        let state2 = TourState(startingStep: .start)
        XCTAssertEqual(state1.step, .start)
        XCTAssertEqual(state2.step, .start)
        XCTAssertTrue(state1.isActive)
        XCTAssertTrue(state2.isActive)
    }

    func testReplayStartingStepSkipsStartWhenAlreadyCaptioning() {
        let state = TourState(startingStep: .listening)
        XCTAssertEqual(state.step, .listening)
        XCTAssertTrue(state.isActive)
    }

    // MARK: - Advancement by matching action

    func testAdvancesFromStartWhenStartButtonTapped() {
        var state = TourState()
        state.handle(.startedCaptioning)
        XCTAssertEqual(state.step, .listening)
    }

    func testAdvancesFromListeningWhenCaptionArrivesQuickly() {
        var state = TourState()
        state.step = .listening
        state.handle(.captionArrived)
        XCTAssertEqual(state.step, .pause)
    }

    func testAdvancesFromPauseWhenControlPausedOrStopped() {
        var state = TourState()
        state.step = .pause
        state.handle(.paused)
        XCTAssertEqual(state.step, .save)
    }

    func testAdvancesFromSaveWhenTapped() {
        var state = TourState()
        state.step = .save
        state.handle(.saved)
        XCTAssertEqual(state.step, .copy)
    }

    func testAdvancesFromCopyWhenTapped() {
        var state = TourState()
        state.step = .copy
        state.handle(.copied)
        XCTAssertEqual(state.step, .gear)
    }

    func testAdvancesFromGearWhenTapped() {
        var state = TourState()
        state.step = .gear
        state.handle(.openedSettings)
        XCTAssertEqual(state.step, .gear)  // last step stays at gear
        XCTAssertFalse(state.isActive)     // but isActive becomes false (Done)
    }

    // MARK: - Ignoring wrong triggers

    func testWrongTriggerIsANoOp() {
        var state = TourState()
        state.step = .start
        let before = state
        state.handle(.captionArrived)  // this doesn't match .start's required trigger
        XCTAssertEqual(state.step, before.step)
        XCTAssertTrue(state.isActive)  // unchanged
    }

    func testOutOfOrderTriggerWhilePausedDoesntSkipSteps() {
        // Simulates real speech arriving while the tour is on the Save step
        var state = TourState()
        state.step = .save
        state.handle(.captionArrived)  // real caption came in, doesn't match .save
        XCTAssertEqual(state.step, .save)  // no advance
        XCTAssertTrue(state.isActive)      // tour continues
    }

    // MARK: - Navigation controls

    func testSkipFromEveryStep() {
        for step in TourStep.allCases {
            var state = TourState()
            state.step = step
            state.skip()
            XCTAssertFalse(state.isActive, "skip() from \(step) should deactivate")
            XCTAssertEqual(state.step, step, "skip() shouldn't change step")
        }
    }

    func testNextAdvancesWithoutRequiringTheAction() {
        var state = TourState()
        state.step = .start
        state.next()
        XCTAssertEqual(state.step, .listening)
    }

    func testNextFromLastStepDeactivates() {
        var state = TourState()
        state.step = .gear
        state.next()
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.step, .gear)
    }

    func testBackReturnsToThePreviousStep() {
        var state = TourState()
        state.step = .copy
        state.back()
        XCTAssertEqual(state.step, .save)
    }

    func testBackOnTheFirstStepIsANoOp() {
        var state = TourState()
        state.step = .start
        state.back()
        XCTAssertEqual(state.step, .start)
        XCTAssertTrue(state.isActive)
    }

    // MARK: - Backgrounding and stale state

    func testFurtherCommandsAfterSkipAreNoOps() {
        var state = TourState()
        state.skip()
        XCTAssertFalse(state.isActive)

        let before = state
        state.next()
        XCTAssertEqual(state, before, "next() after skip should be a no-op")

        state.handle(.startedCaptioning)
        XCTAssertEqual(state, before, "handle() after skip should be a no-op")

        state.back()
        XCTAssertEqual(state, before, "back() after skip should be a no-op")
    }

    func testFurtherCommandsAfterFinishingAreNoOps() {
        var state = TourState()
        state.step = .gear
        state.next()  // Done
        XCTAssertFalse(state.isActive)

        let before = state
        state.next()
        XCTAssertEqual(state, before, "next() after finish should be a no-op")

        state.handle(.openedSettings)
        XCTAssertEqual(state, before, "handle() after finish should be a no-op")
    }

    // MARK: - Replay and persistence

    func testReplayCreatesAFreshState() {
        var state = TourState()
        state.step = .gear
        state.skip()
        XCTAssertFalse(state.isActive)

        // Replay
        state = TourState()
        XCTAssertEqual(state.step, .start)
        XCTAssertTrue(state.isActive)
    }

    // MARK: - TourStore

    func testStoreFreshlyHasNotSeenTour() {
        let defaults = UserDefaults(suiteName: "tour-test-\(UUID())")!
        let store = TourStore(defaults: defaults)
        XCTAssertFalse(store.hasSeenTour)
    }

    func testStoreRemembersThatTourWasSeen() {
        let defaults = UserDefaults(suiteName: "tour-test-\(UUID())")!
        let store = TourStore(defaults: defaults)
        store.markSeen()
        XCTAssertTrue(store.hasSeenTour)
    }

    func testStorePersistesAcrossInstances() {
        let defaults = UserDefaults(suiteName: "tour-test-\(UUID())")!
        let store1 = TourStore(defaults: defaults)
        store1.markSeen()

        let store2 = TourStore(defaults: defaults)
        XCTAssertTrue(store2.hasSeenTour)
    }

    func testMarkSeenIsIdempotent() {
        let defaults = UserDefaults(suiteName: "tour-test-\(UUID())")!
        let store = TourStore(defaults: defaults)
        store.markSeen()
        store.markSeen()
        XCTAssertTrue(store.hasSeenTour)
    }

    // MARK: - TourDemoLine

    func testDemoLineNotInjectedOutsideTour() {
        // Demo line should never inject during a normal Save outside the tour
        XCTAssertFalse(TourDemoLine.isNeeded(hasRealConversation: false, tourStepIsSave: false))
    }

    func testDemoLineInjectedOnlyDuringTourSaveStep() {
        // Demo line injects when: tour is at .save, room is quiet
        XCTAssertTrue(TourDemoLine.isNeeded(hasRealConversation: false, tourStepIsSave: true))
    }

    func testDemoLineNeverOverwritesRealConversationDuringTour() {
        // Demo line never fires if there's already real speech, even mid-tour
        XCTAssertFalse(TourDemoLine.isNeeded(hasRealConversation: true, tourStepIsSave: true))
    }

    // MARK: - Completeness

    func testEveryStepHasExactlyOneRequiredTrigger() {
        let allTriggers = TourStep.allCases.map { $0.requiredTrigger }
        let uniqueTriggers = Set(allTriggers)
        XCTAssertEqual(uniqueTriggers.count, allTriggers.count, "Two steps share the same trigger")
    }

    func testStepRawValueEnumIsComplete() {
        XCTAssertNotNil(TourStep(rawValue: 0), ".start must exist")
        XCTAssertNotNil(TourStep(rawValue: 5), ".gear must exist")
        XCTAssertNil(TourStep(rawValue: 99), "invalid raw values must return nil")
    }

    // MARK: - Copy text

    func testCopyExistsForEveryStep() {
        for step in TourStep.allCases {
            let copy = TourCopy.for(step)
            XCTAssertFalse(copy.title.isEmpty, "\(step) needs a title")
            XCTAssertFalse(copy.body.isEmpty, "\(step) needs body text")
        }
    }

    func testCopyUsesPlainWordsWithoutJargon() {
        let jargon = ["diarizer", "transcription", "model", "neural", "core ml", "api", "database"]
        for step in TourStep.allCases {
            let copy = TourCopy.for(step)
            let text = (copy.title + " " + copy.body).lowercased()
            for word in jargon {
                XCTAssertFalse(text.contains(word), "\(step) uses jargon: \(word)")
            }
        }
    }
}

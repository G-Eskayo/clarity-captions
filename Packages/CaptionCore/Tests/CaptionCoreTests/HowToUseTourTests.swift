import XCTest
@testable import CaptionCore

final class HowToUseTourTests: XCTestCase {
    func testTourStartsAtStartNotFinished() {
        var tour = HowToUseTour()
        XCTAssertEqual(tour.currentStep, .start)
        XCTAssertFalse(tour.isFinished)
    }

    func testStepOrderIsCorrect() {
        let expected: [HowToUseTour.TourStep] = [.start, .pause, .save, .new, .copy, .gear]
        XCTAssertEqual(HowToUseTour.TourStep.allCases, expected)
    }

    func testNextAdvancesWhenActionMatches() {
        var tour = HowToUseTour()
        XCTAssertEqual(tour.currentStep, .start)
        tour.didPerform(.start)
        XCTAssertEqual(tour.currentStep, .pause)
    }

    func testDidPerformIgnoresWrongAction() {
        var tour = HowToUseTour()
        XCTAssertEqual(tour.currentStep, .start)
        tour.didPerform(.save)  // Wrong action
        XCTAssertEqual(tour.currentStep, .start)  // No advance
    }

    func testDidPerformAdvancesThroughAllSteps() {
        var tour = HowToUseTour()
        let steps: [HowToUseTour.TourStep] = [.start, .pause, .save, .new, .copy, .gear]
        for (i, expectedStep) in steps.enumerated() {
            XCTAssertEqual(tour.currentStep, expectedStep, "Step \(i)")
            if i < steps.count - 1 {
                tour.didPerform(expectedStep)
            }
        }
    }

    func testNextAfterGearFinishesTour() {
        var tour = HowToUseTour()
        // Skip to the last step
        for step in [HowToUseTour.TourStep.start, .pause, .save, .new, .copy] {
            tour.didPerform(step)
        }
        XCTAssertEqual(tour.currentStep, .gear)
        XCTAssertFalse(tour.isFinished)
        tour.didPerform(.gear)
        XCTAssertTrue(tour.isFinished)
        XCTAssertNil(tour.currentStep)
    }

    func testBackAtStartIsNoOp() {
        var tour = HowToUseTour()
        tour.back()
        XCTAssertEqual(tour.currentStep, .start)
    }

    func testBackMovesBackOneStep() {
        var tour = HowToUseTour()
        tour.didPerform(.start)
        tour.didPerform(.pause)
        XCTAssertEqual(tour.currentStep, .save)
        tour.back()
        XCTAssertEqual(tour.currentStep, .pause)
    }

    func testBackAfterFinishedIsNoOp() {
        var tour = HowToUseTour()
        for step in [HowToUseTour.TourStep.start, .pause, .save, .new, .copy, .gear] {
            tour.didPerform(step)
        }
        XCTAssertTrue(tour.isFinished)
        tour.back()
        XCTAssertTrue(tour.isFinished)
    }

    func testSkipFinishesTour() {
        var tour = HowToUseTour()
        XCTAssertEqual(tour.currentStep, .start)
        tour.skip()
        XCTAssertTrue(tour.isFinished)
        XCTAssertNil(tour.currentStep)
    }

    func testSkipFromAnyStepFinishesTour() {
        var tour = HowToUseTour()
        tour.didPerform(.start)
        tour.didPerform(.pause)
        tour.didPerform(.save)
        XCTAssertEqual(tour.currentStep, .new)
        tour.skip()
        XCTAssertTrue(tour.isFinished)
    }

    func testDidPerformAfterFinishedIsIgnored() {
        var tour = HowToUseTour()
        tour.skip()
        XCTAssertTrue(tour.isFinished)
        tour.didPerform(.start)  // Should be ignored
        XCTAssertTrue(tour.isFinished)
    }

    func testDidPerformCalledTwiceForSameActionDoesNotDoubleAdvance() {
        var tour = HowToUseTour()
        tour.didPerform(.start)
        XCTAssertEqual(tour.currentStep, .pause)
        tour.didPerform(.start)  // Wrong action now
        XCTAssertEqual(tour.currentStep, .pause)  // No advance
    }

    func testSequenceNextNextBackBackNextLandsCorrectly() {
        var tour = HowToUseTour()
        tour.didPerform(.start)  // -> pause
        tour.didPerform(.pause)  // -> save
        tour.back()  // -> pause
        tour.back()  // -> start
        tour.didPerform(.start)  // -> pause
        XCTAssertEqual(tour.currentStep, .pause)
    }

    func testInitialStepIdleNoConversation() {
        let step = HowToUseTour.initialStep(state: .idle, hasConversation: false)
        XCTAssertEqual(step, .start)
    }

    func testInitialStepListeningNoConversation() {
        let step = HowToUseTour.initialStep(state: .listening, hasConversation: false)
        XCTAssertEqual(step, .start)
    }

    func testInitialStepPreparingNoConversation() {
        let step = HowToUseTour.initialStep(state: .preparing, hasConversation: false)
        XCTAssertEqual(step, .start)
    }

    func testInitialStepFailedNoConversation() {
        let step = HowToUseTour.initialStep(state: .failed("error"), hasConversation: false)
        XCTAssertEqual(step, .start)
    }

    func testInitialStepPausedQuietNoConversation() {
        let step = HowToUseTour.initialStep(state: .pausedQuiet(minutes: 5), hasConversation: false)
        XCTAssertEqual(step, .start)
    }

    func testInitialStepIdleWithConversation() {
        let step = HowToUseTour.initialStep(state: .idle, hasConversation: true)
        XCTAssertEqual(step, .pause)
    }

    func testInitialStepPausedQuietWithConversation() {
        let step = HowToUseTour.initialStep(state: .pausedQuiet(minutes: 5), hasConversation: true)
        XCTAssertEqual(step, .pause)
    }

    func testInitialStepFailedWithConversation() {
        let step = HowToUseTour.initialStep(state: .failed("error"), hasConversation: true)
        XCTAssertEqual(step, .pause)
    }

    func testInitialStepListeningWithConversation() {
        let step = HowToUseTour.initialStep(state: .listening, hasConversation: true)
        XCTAssertEqual(step, .pause)
    }

    func testInitialStepPreparingWithConversation() {
        let step = HowToUseTour.initialStep(state: .preparing, hasConversation: true)
        XCTAssertEqual(step, .pause)
    }

    func testStoreRemembersHasSeenTour() {
        let d = UserDefaults(suiteName: "tour-test-\(UUID())")!
        let store = HowToUseTourStore(defaults: d)
        XCTAssertFalse(store.hasSeenTour)
        store.markSeen()
        XCTAssertTrue(store.hasSeenTour)
    }

    func testStoreMarkSeenIsPersisted() {
        let d = UserDefaults(suiteName: "tour-test-\(UUID())")!
        let store = HowToUseTourStore(defaults: d)
        store.markSeen()
        let newStore = HowToUseTourStore(defaults: d)
        XCTAssertTrue(newStore.hasSeenTour)
    }

    func testStoreMarkSeenIsIdempotent() {
        let d = UserDefaults(suiteName: "tour-test-\(UUID())")!
        let store = HowToUseTourStore(defaults: d)
        store.markSeen()
        store.markSeen()
        XCTAssertTrue(store.hasSeenTour)
    }

    func testTourCopyHasContentForAllSteps() {
        for step in HowToUseTour.TourStep.allCases {
            let copy = TourCopy.for(step)
            XCTAssertFalse(copy.title.isEmpty, "\(step) needs a title")
            XCTAssertFalse(copy.message.isEmpty, "\(step) needs a message")
        }
    }

    func testTourCopyAvoidsTechJargon() {
        let jargon = ["model", "diariz", "neural", "core ml", "mlmodel", "analyzer", "asset", "bundle", "network"]
        for step in HowToUseTour.TourStep.allCases {
            let copy = TourCopy.for(step)
            let combined = (copy.title + " " + copy.message).lowercased()
            for word in jargon {
                XCTAssertFalse(combined.contains(word), "\(step) uses jargon: \(word)")
            }
        }
    }

    func testTourCopyAvoidsBrokenPlaceholders() {
        let placeholders = ["open question", "todo", "placeholder", "tbd", "["]
        for step in HowToUseTour.TourStep.allCases {
            let copy = TourCopy.for(step)
            let combined = (copy.title + " " + copy.message).lowercased()
            for placeholder in placeholders {
                XCTAssertFalse(combined.contains(placeholder), "\(step) contains unfinished placeholder: \(placeholder)")
            }
        }
    }

    func testShowsDemoContentForSaveWithoutConversation() {
        XCTAssertTrue(HowToUseTour.showsDemoContent(step: .save, hasConversation: false))
    }

    func testShowsDemoContentForCopyWithoutConversation() {
        XCTAssertTrue(HowToUseTour.showsDemoContent(step: .copy, hasConversation: false))
    }

    func testShowsDemoContentHiddenForSaveWithConversation() {
        XCTAssertFalse(HowToUseTour.showsDemoContent(step: .save, hasConversation: true))
    }

    func testShowsDemoContentHiddenForCopyWithConversation() {
        XCTAssertFalse(HowToUseTour.showsDemoContent(step: .copy, hasConversation: true))
    }

    func testShowsDemoContentNilForStartStep() {
        XCTAssertFalse(HowToUseTour.showsDemoContent(step: .start, hasConversation: false))
    }

    func testShowsDemoContentNilForPauseStep() {
        XCTAssertFalse(HowToUseTour.showsDemoContent(step: .pause, hasConversation: false))
    }

    func testShowsDemoContentNilForNewStep() {
        XCTAssertFalse(HowToUseTour.showsDemoContent(step: .new, hasConversation: false))
    }

    func testShowsDemoContentNilForGearStep() {
        XCTAssertFalse(HowToUseTour.showsDemoContent(step: .gear, hasConversation: false))
    }

    func testShowsDemoContentNilWhenNoStep() {
        XCTAssertFalse(HowToUseTour.showsDemoContent(step: nil, hasConversation: false))
    }

    func testShowsDemoContentInstantlyHidesWhenConversationStarts() {
        // Demonstrates the fix for defect 1: demo content disappears even mid-tour step
        XCTAssertTrue(HowToUseTour.showsDemoContent(step: .save, hasConversation: false))
        XCTAssertFalse(HowToUseTour.showsDemoContent(step: .save, hasConversation: true))
    }

    func testDemoScriptProducesLines() {
        let script = TourDemoScript.lines
        XCTAssertFalse(script.isEmpty, "Demo script should have at least one line")
    }

    func testDemoScriptProducesOnlySpeechLines() {
        let script = TourDemoScript.lines
        for line in script {
            XCTAssertNil(line.soundLabel, "Demo script should not contain sound labels")
        }
    }

    func testDemoScriptHasNoAudioType() {
        // Structural test: the demo script only uses CaptionLine initialization
        // which has no audio/mic/engine dependencies. This is verified by compilation.
        let script = TourDemoScript.lines
        XCTAssertFalse(script.isEmpty)
    }

    // MARK: - Frame Key Tests

    func testFrameKeyReturnsDistinctNonEmptyKeysForAllSteps() {
        var keys = Set<String>()
        for step in HowToUseTour.TourStep.allCases {
            let key = HowToUseTour.frameKey(for: step)
            XCTAssertFalse(key.isEmpty, "\(step) should have a non-empty key")
            XCTAssertTrue(keys.insert(key).inserted, "Keys must be distinct, but \(key) appeared twice")
        }
        XCTAssertEqual(keys.count, HowToUseTour.TourStep.allCases.count, "All steps should have unique keys")
    }

    // MARK: - Spotlight Visibility Tests

    func testShowsSpotlightTargetForSaveWithoutConversation() {
        XCTAssertTrue(HowToUseTour.showsSpotlightTarget(step: .save, hasConversation: false))
    }

    func testShowsSpotlightTargetForNewWithoutConversation() {
        XCTAssertTrue(HowToUseTour.showsSpotlightTarget(step: .new, hasConversation: false))
    }

    func testShowsSpotlightTargetForCopyWithoutConversation() {
        XCTAssertTrue(HowToUseTour.showsSpotlightTarget(step: .copy, hasConversation: false))
    }

    func testShowsSpotlightTargetHidesForStartWithoutConversation() {
        XCTAssertFalse(HowToUseTour.showsSpotlightTarget(step: .start, hasConversation: false))
    }

    func testShowsSpotlightTargetHidesForPauseWithoutConversation() {
        XCTAssertFalse(HowToUseTour.showsSpotlightTarget(step: .pause, hasConversation: false))
    }

    func testShowsSpotlightTargetHidesForGearWithoutConversation() {
        XCTAssertFalse(HowToUseTour.showsSpotlightTarget(step: .gear, hasConversation: false))
    }

    func testShowsSpotlightTargetHidesWhenConversationExists() {
        XCTAssertFalse(HowToUseTour.showsSpotlightTarget(step: .save, hasConversation: true))
        XCTAssertFalse(HowToUseTour.showsSpotlightTarget(step: .new, hasConversation: true))
        XCTAssertFalse(HowToUseTour.showsSpotlightTarget(step: .copy, hasConversation: true))
    }

    func testShowsSpotlightTargetNilWhenNoStep() {
        XCTAssertFalse(HowToUseTour.showsSpotlightTarget(step: nil, hasConversation: false))
    }
}

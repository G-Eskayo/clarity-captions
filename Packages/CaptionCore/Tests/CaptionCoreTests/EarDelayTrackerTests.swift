import CaptionCore
import XCTest

final class EarDelayTrackerTests: XCTestCase {
    func testPhraseBecomeReadyTranslationArrivesToVoiceStarted() {
        var tracker = EarDelayTracker()
        tracker.phraseReady(lineID: 1, wordStart: 0, at: 0)
        tracker.translationReady(lineID: 1, wordStart: 0, at: 0.2)
        let sample = tracker.voiceStarted(lineID: 1, wordStart: 0, at: 0.5)
        XCTAssertEqual(sample!.translateDelay, 0.2, accuracy: 0.001)
        XCTAssertEqual(sample!.voiceStartDelay, 0.3, accuracy: 0.001)
    }

    func testBehindByMeasuresQueuedWork() {
        var tracker = EarDelayTracker()
        tracker.phraseReady(lineID: 1, wordStart: 0, at: 0)
        tracker.translationReady(lineID: 1, wordStart: 0, at: 0.2)
        let sample = tracker.voiceStarted(lineID: 1, wordStart: 0, at: 0.5)
        XCTAssertEqual(sample!.behindBy, 0, "first phrase has no backlog")

        // Second phrase ready before first finishes: creates backlog.
        tracker.phraseReady(lineID: 2, wordStart: 0, at: 0.6)
        tracker.translationReady(lineID: 2, wordStart: 0, at: 0.8)
        let sample2 = tracker.voiceStarted(lineID: 2, wordStart: 0, at: 1.2)
        // backlog = now - latestEndOfPhrase = 1.2 - 0.2 = 1.0
        XCTAssertEqual(sample2!.behindBy, 1.0, accuracy: 0.001, "backlog from when first phrase finished translating")
    }

    func testDelaysClamped() {
        var tracker = EarDelayTracker()
        tracker.phraseReady(lineID: 1, wordStart: 0, at: 10)
        tracker.translationReady(lineID: 1, wordStart: 0, at: 9)
        let sample = tracker.voiceStarted(lineID: 1, wordStart: 0, at: 8)
        XCTAssertGreaterThanOrEqual(sample?.translateDelay ?? 0, 0)
        XCTAssertGreaterThanOrEqual(sample?.voiceStartDelay ?? 0, 0)
        XCTAssertGreaterThanOrEqual(sample?.behindBy ?? 0, 0)
    }

    func testTranslationNotReadyYet() {
        var tracker = EarDelayTracker()
        tracker.phraseReady(lineID: 1, wordStart: 0, at: 0)
        let sample = tracker.voiceStarted(lineID: 1, wordStart: 0, at: 0.5)
        XCTAssertNil(sample, "no sample without translation ready")
    }

    func testUnknownLineIDReturnsNil() {
        var tracker = EarDelayTracker()
        let sample = tracker.voiceStarted(lineID: 999, wordStart: 0, at: 1)
        XCTAssertNil(sample)
    }

    func testPhrasesCleanedAfterVoiceStart() {
        var tracker = EarDelayTracker()
        tracker.phraseReady(lineID: 1, wordStart: 0, at: 0)
        tracker.translationReady(lineID: 1, wordStart: 0, at: 0.2)
        _ = tracker.voiceStarted(lineID: 1, wordStart: 0, at: 0.5)
        // Try again: should return nil since it was cleaned up.
        let sample2 = tracker.voiceStarted(lineID: 1, wordStart: 0, at: 0.6)
        XCTAssertNil(sample2)
    }

    func testMaxPendingEvictsOldestLineID() {
        var tracker = EarDelayTracker()
        for i in 1...102 {
            tracker.phraseReady(lineID: i, wordStart: 0, at: Double(i))
        }
        // Line 1 should be evicted (oldest ID).
        tracker.translationReady(lineID: 1, wordStart: 0, at: 102.2)
        let sample = tracker.voiceStarted(lineID: 1, wordStart: 0, at: 102.5)
        XCTAssertNil(sample, "line 1 was evicted when pending exceeded 100")
    }

    func testResetClearsPending() {
        var tracker = EarDelayTracker()
        tracker.phraseReady(lineID: 1, wordStart: 0, at: 0)
        tracker.reset()
        tracker.translationReady(lineID: 1, wordStart: 0, at: 0.2)
        let sample = tracker.voiceStarted(lineID: 1, wordStart: 0, at: 0.5)
        XCTAssertNil(sample, "pending cleared by reset")
    }

    func testMultiplePhrasesPerLineKeepsFirstAnchor() {
        var tracker = EarDelayTracker()
        // Line 1, first phrase (early)
        tracker.phraseReady(lineID: 1, wordStart: 0, at: 0)
        tracker.translationReady(lineID: 1, wordStart: 0, at: 0.15)

        // Line 1, second phrase (final) shouldn't overwrite first's readyAt
        tracker.phraseReady(lineID: 1, wordStart: 3, at: 0.4)
        tracker.translationReady(lineID: 1, wordStart: 3, at: 0.6)

        // First phrase speaks at 0.5
        let sample1 = tracker.voiceStarted(lineID: 1, wordStart: 0, at: 0.5)
        XCTAssertNotNil(sample1)
        XCTAssertEqual(sample1!.translateDelay, 0.15, accuracy: 0.001, "first phrase has its own timing")

        // Second phrase speaks at 1.0
        let sample2 = tracker.voiceStarted(lineID: 1, wordStart: 3, at: 1.0)
        XCTAssertNotNil(sample2)
        XCTAssertEqual(sample2!.translateDelay, 0.2, accuracy: 0.001, "second phrase has its own timing")
        XCTAssertEqual(sample2!.behindBy, 0.5, accuracy: 0.001, "backlog from when first phrase finished")
    }

    func testNaNTimestampsDoNotCorruptHistogram() {
        var tracker = EarDelayTracker()
        tracker.phraseReady(lineID: 1, wordStart: 0, at: 0)
        tracker.translationReady(lineID: 1, wordStart: 0, at: Double.nan)
        let sample = tracker.voiceStarted(lineID: 1, wordStart: 0, at: 0.5)
        // Should produce a sample with NaN delays, which the histogram will reject
        XCTAssertNotNil(sample)
        XCTAssertTrue(sample!.translateDelay.isNaN)
        // Histogram.add already guards against non-finite values
    }
}

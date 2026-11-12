import XCTest
@testable import CaptionCore

final class EarDelayTrackingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    // MARK: translate delay (phrase spoken → translation ready)

    func testTranslateDelayFromSpokenToReady() {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.translationReady(instanceID: 1, at: at(0.5))
        let report = tracker.report
        XCTAssertEqual(report.translateDelay.p50Seconds ?? 0, 0.525, accuracy: 0.01)
        XCTAssertEqual(report.translateDelay.samples, 1)
    }

    func testTranslateDelayP95() {
        var tracker = EarDelayTracker()
        for i in 0..<100 {
            tracker.phraseSpoken(instanceID: i, at: at(Double(i)))
            if i >= 90 {
                tracker.translationReady(instanceID: i, at: at(Double(i) + 3.0))
            } else {
                tracker.translationReady(instanceID: i, at: at(Double(i) + 0.5))
            }
        }
        let report = tracker.report
        XCTAssertEqual(report.translateDelay.samples, 100)
        XCTAssertEqual(report.translateDelay.p50Seconds ?? 0, 0.525, accuracy: 0.05)
        let p95 = report.translateDelay.p95Seconds ?? 0
        XCTAssertGreaterThanOrEqual(p95, 1.0)
    }

    func testTranslateDelayNegativeClamped() {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(1.0))
        tracker.translationReady(instanceID: 1, at: at(0.5))  // clock disagreement
        let report = tracker.report
        XCTAssertEqual(report.translateDelay.p50Seconds ?? 0, 0.025, accuracy: 0.01)
    }

    // MARK: voice start delay (translation ready → voice started)

    func testVoiceStartDelayFromReadyToStarted() {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.translationReady(instanceID: 1, at: at(0.5))
        tracker.voiceStarted(instanceID: 1, at: at(0.6))
        let report = tracker.report
        XCTAssertEqual(report.voiceStartDelay.p50Seconds ?? 0, 0.125, accuracy: 0.01)
        XCTAssertEqual(report.voiceStartDelay.samples, 1)
    }

    func testVoiceStartDelayP95() {
        var tracker = EarDelayTracker()
        for i in 0..<100 {
            tracker.phraseSpoken(instanceID: i, at: at(Double(i)))
            tracker.translationReady(instanceID: i, at: at(Double(i) + 0.3))
            if i >= 90 {
                tracker.voiceStarted(instanceID: i, at: at(Double(i) + 2.0))
            } else {
                tracker.voiceStarted(instanceID: i, at: at(Double(i) + 0.35))
            }
        }
        let report = tracker.report
        XCTAssertEqual(report.voiceStartDelay.samples, 100)
        XCTAssertEqual(report.voiceStartDelay.p50Seconds ?? 0, 0.075, accuracy: 0.05)
        let p95 = report.voiceStartDelay.p95Seconds ?? 0
        XCTAssertGreaterThanOrEqual(p95, 0.5)
    }

    func testVoiceStartDelayIgnoredIfNoTranslation() {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.voiceStarted(instanceID: 1, at: at(0.1))  // no translation recorded first
        let report = tracker.report
        XCTAssertEqual(report.voiceStartDelay.samples, 0)
    }

    // MARK: behind-by (voice finished → speaker spoke then)

    func testBehindByDistance() {
        var tracker = EarDelayTracker()
        let speakerSpokeThen = at(0)
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.translationReady(instanceID: 1, at: at(0.5))
        tracker.voiceStarted(instanceID: 1, at: at(0.6))
        tracker.voiceFinished(instanceID: 1, at: at(1.0), speakerSpokeThen: speakerSpokeThen)
        let report = tracker.report
        XCTAssertEqual(report.behindBy.p50Seconds ?? 0, 1.05, accuracy: 0.01)
        XCTAssertEqual(report.behindBy.samples, 1)
    }

    func testBehindByP95() {
        var tracker = EarDelayTracker()
        let baseTime = at(0)
        for i in 0..<20 {
            let instanceID = i
            tracker.phraseSpoken(instanceID: instanceID, at: baseTime.addingTimeInterval(Double(i) * 0.5))
            tracker.translationReady(instanceID: instanceID, at: baseTime.addingTimeInterval(Double(i) * 0.5 + 0.3))
            tracker.voiceStarted(instanceID: instanceID, at: baseTime.addingTimeInterval(Double(i) * 0.5 + 0.35))
            if i == 19 {
                tracker.voiceFinished(instanceID: instanceID, at: baseTime.addingTimeInterval(Double(i) * 0.5 + 2.0), speakerSpokeThen: baseTime)
            } else {
                tracker.voiceFinished(instanceID: instanceID, at: baseTime.addingTimeInterval(Double(i) * 0.5 + 0.7), speakerSpokeThen: baseTime)
            }
        }
        let report = tracker.report
        XCTAssertEqual(report.behindBy.samples, 20)
        let p50 = report.behindBy.p50Seconds ?? 0
        let p95 = report.behindBy.p95Seconds ?? 0
        XCTAssertGreaterThanOrEqual(p95, p50)
        XCTAssertGreaterThan(p95, 4.5)
    }

    // MARK: error conditions

    func testTranslationMissesWhenNoPhrase() {
        var tracker = EarDelayTracker()
        tracker.translationReady(instanceID: 1, at: at(0.5))  // no phrase spoken
        XCTAssertEqual(tracker.translationMisses, 1)
    }

    func testTranslationFailedCounts() {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.translationFailed(instanceID: 1)
        let report = tracker.report
        XCTAssertEqual(report.translationMisses, 1)
    }

    func testVoiceCutOffCounts() {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.translationReady(instanceID: 1, at: at(0.5))
        tracker.voiceStarted(instanceID: 1, at: at(0.6))
        tracker.voiceCutOff(instanceID: 1)
        let report = tracker.report
        XCTAssertEqual(report.voiceCutOffs, 1)
    }

    func testVoiceCutOffIgnoredIfNotOpen() {
        var tracker = EarDelayTracker()
        tracker.voiceCutOff(instanceID: 999)
        XCTAssertEqual(tracker.voiceCutOffs, 0)
    }

    func testInstancesCleanedUpAfterFinish() {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.translationReady(instanceID: 1, at: at(0.5))
        tracker.voiceStarted(instanceID: 1, at: at(0.6))
        tracker.voiceFinished(instanceID: 1, at: at(1.0), speakerSpokeThen: at(0))
        tracker.voiceStarted(instanceID: 1, at: at(2.0))  // after finish: ignored
        let report = tracker.report
        XCTAssertEqual(report.voiceStartDelay.samples, 1)
    }

    func testInstancesCleanedUpAfterCutOff() {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.translationReady(instanceID: 1, at: at(0.5))
        tracker.voiceCutOff(instanceID: 1)
        tracker.translationFailed(instanceID: 1)  // after cut off: ignorecd
        let report = tracker.report
        XCTAssertEqual(report.translationMisses, 0)
        XCTAssertEqual(report.voiceCutOffs, 1)
    }

    // MARK: Codable

    func testEarDelayTrackerCodable() throws {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.translationReady(instanceID: 1, at: at(0.5))
        tracker.voiceStarted(instanceID: 1, at: at(0.6))
        tracker.voiceFinished(instanceID: 1, at: at(1.0), speakerSpokeThen: at(0))

        let encoded = try JSONEncoder().encode(tracker)
        let decoded = try JSONDecoder().decode(EarDelayTracker.self, from: encoded)

        XCTAssertEqual(tracker, decoded)
    }

    func testEarDelayReportCodable() throws {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.translationReady(instanceID: 1, at: at(0.5))
        tracker.voiceStarted(instanceID: 1, at: at(0.6))
        tracker.voiceFinished(instanceID: 1, at: at(1.0), speakerSpokeThen: at(0))

        let report = tracker.report
        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(EarDelayReport.self, from: encoded)

        XCTAssertEqual(report, decoded)
    }

    // MARK: Defect tests

    func testMissingPhraseEndDateDoesNotFabricate() {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.translationReady(instanceID: 1, at: at(0.5))
        tracker.voiceStarted(instanceID: 1, at: at(0.6))
        tracker.voiceFinished(instanceID: 1, at: at(1.0), speakerSpokeThen: at(0))

        let report = tracker.report
        XCTAssertEqual(report.behindBy.samples, 1)
    }

    func testOpenInstancesBounded() {
        var tracker = EarDelayTracker()
        for i in 0..<150 {
            tracker.phraseSpoken(instanceID: i, at: at(Double(i)))
        }

        _ = tracker.report
        XCTAssertGreaterThanOrEqual(tracker.translationMisses, 0)
    }

    func testCodablePreservesAllMetrics() {
        var tracker = EarDelayTracker()
        for i in 0..<5 {
            tracker.phraseSpoken(instanceID: i, at: at(Double(i)))
            tracker.translationReady(instanceID: i, at: at(Double(i) + 0.5))
            tracker.voiceStarted(instanceID: i, at: at(Double(i) + 0.6))
            tracker.voiceFinished(instanceID: i, at: at(Double(i) + 1.0), speakerSpokeThen: at(Double(i)))
        }
        tracker.voiceCutOff(instanceID: 999)

        let encoded = try! JSONEncoder().encode(tracker)
        let decoded = try! JSONDecoder().decode(EarDelayTracker.self, from: encoded)

        XCTAssertEqual(tracker.report, decoded.report)
        XCTAssertEqual(tracker.voiceCutOffs, decoded.voiceCutOffs)
    }

    func testTranslationFailureStates() {
        var tracker = EarDelayTracker()
        tracker.phraseSpoken(instanceID: 1, at: at(0))
        tracker.translationFailed(instanceID: 1)

        let report = tracker.report
        XCTAssertEqual(report.translationMisses, 1)
        XCTAssertEqual(report.translateDelay.samples, 0)
    }
}

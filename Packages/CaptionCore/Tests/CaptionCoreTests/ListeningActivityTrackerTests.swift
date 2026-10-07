import XCTest
@testable import CaptionCore

final class ListeningActivityTrackerTests: XCTestCase {
    func testNoSpeechYetTreatsAsSilent() {
        let tracker = ListeningActivityTracker()
        let now = Date()

        let activity = tracker.activity(now: now, roomLevelDBFS: -30)

        XCTAssertEqual(activity, .noOneTalking)
    }

    func testRecordingSpeechResetsTheClock() {
        var tracker = ListeningActivityTracker()
        let t0 = Date()
        let t9dot9 = t0.addingTimeInterval(9.9)

        tracker.recordSpeech(at: t0)
        let activity = tracker.activity(now: t9dot9, roomLevelDBFS: -30)

        XCTAssertEqual(activity, .activelyListening)
    }

    func testActivityBelowThresholdAfterSpeechIsRecent() {
        var tracker = ListeningActivityTracker()
        let t0 = Date()
        let t5 = t0.addingTimeInterval(5)

        tracker.recordSpeech(at: t0)
        let activity = tracker.activity(now: t5, roomLevelDBFS: -30)

        XCTAssertEqual(activity, .activelyListening)
    }

    func testActivityAtThresholdBecomesNoOneTalking() {
        var tracker = ListeningActivityTracker()
        let t0 = Date()
        let t10dot5 = t0.addingTimeInterval(10.5)

        tracker.recordSpeech(at: t0)
        let activity = tracker.activity(now: t10dot5, roomLevelDBFS: -30)

        XCTAssertEqual(activity, .noOneTalking)
    }

    func testMultipleSpeechEventsUpdateTheRecordedTime() {
        var tracker = ListeningActivityTracker()
        let t0 = Date()
        let t5 = t0.addingTimeInterval(5)
        let t14 = t0.addingTimeInterval(14)

        tracker.recordSpeech(at: t0)
        tracker.recordSpeech(at: t5)
        let activity = tracker.activity(now: t14, roomLevelDBFS: -30)

        XCTAssertEqual(activity, .activelyListening)
    }

    func testLowRoomLevelBelowThresholdGiveCantHear() {
        var tracker = ListeningActivityTracker()
        let t0 = Date()
        let t15 = t0.addingTimeInterval(15)

        tracker.recordSpeech(at: t0)
        let activity = tracker.activity(now: t15, roomLevelDBFS: -60.5)

        XCTAssertEqual(activity, .cantHearAnything)
    }
}

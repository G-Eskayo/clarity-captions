import XCTest
@testable import CaptionCore

final class ListeningActivityClassifierTests: XCTestCase {
    func testActivelyListeningWhenSpeechIsRecent() {
        let activity = ListeningActivityClassifier.classify(secondsSinceSpeech: 0, roomLevelDBFS: -30)
        XCTAssertEqual(activity, .activelyListening)
    }

    func testActivelyListeningJustBeforeTheThreshold() {
        let activity = ListeningActivityClassifier.classify(secondsSinceSpeech: 9.9, roomLevelDBFS: -30)
        XCTAssertEqual(activity, .activelyListening)
    }

    func testNoOneTalkingWhenSpeechHasBeenSilentForAbout10Seconds() {
        let activity = ListeningActivityClassifier.classify(secondsSinceSpeech: 10.5, roomLevelDBFS: -30)
        XCTAssertEqual(activity, .noOneTalking)
    }

    func testNoOneTalkingWithNilLevel() {
        let activity = ListeningActivityClassifier.classify(secondsSinceSpeech: 15, roomLevelDBFS: nil)
        XCTAssertEqual(activity, .noOneTalking)
    }

    func testCantHearWhenRoomLevelIsBelowSilenceFloor() {
        let activity = ListeningActivityClassifier.classify(secondsSinceSpeech: 15, roomLevelDBFS: -60.5)
        XCTAssertEqual(activity, .cantHearAnything)
    }

    func testCantHearBoundaryAtSilenceFloor() {
        let activity = ListeningActivityClassifier.classify(secondsSinceSpeech: 15, roomLevelDBFS: -60.0)
        XCTAssertEqual(activity, .cantHearAnything)
    }

    func testJustAboveSilenceFloorIsStillNoOneTalking() {
        let activity = ListeningActivityClassifier.classify(secondsSinceSpeech: 15, roomLevelDBFS: -59.9)
        XCTAssertEqual(activity, .noOneTalking)
    }

    func testActivelyListeningDoesNotCheckRoomLevel() {
        let activity = ListeningActivityClassifier.classify(secondsSinceSpeech: 5, roomLevelDBFS: -100)
        XCTAssertEqual(activity, .activelyListening)
    }
}

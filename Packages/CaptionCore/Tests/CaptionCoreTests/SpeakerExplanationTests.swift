import XCTest
@testable import CaptionCore

final class SpeakerExplanationTests: XCTestCase {
    func testSentenceIsNonEmpty() {
        XCTAssertFalse(SpeakerExplanation.sentence.isEmpty)
    }

    func testSentenceSpeaksPlainWordsWithoutJargon() {
        let jargon = ["model", "diariz", "neural", "core ml", "mlmodel", "analyzer", "asset", "bundle", "network"]
        let sentence = SpeakerExplanation.sentence.lowercased()
        for word in jargon {
            XCTAssertFalse(sentence.contains(word), "uses jargon: \(word)")
        }
    }

    func testStoreRoundTripsHasSeenFlag() {
        let d = UserDefaults(suiteName: "speaker-explanation-test-\(UUID())")!
        let store = SpeakerExplanationStore(defaults: d)
        XCTAssertFalse(store.hasSeen, "should start unseen")
        store.markSeen()
        XCTAssertTrue(store.hasSeen, "should remember being seen")
    }
}

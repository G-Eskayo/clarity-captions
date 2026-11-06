import XCTest
@testable import CaptionCore

final class EarVoiceMatchWiringTests: XCTestCase {
    func testFinishedCaptionLineHasSpeakerTraits() {
        let traits = SpeakerTraits(pitchHz: 150, syllablesPerSecond: 5)
        var stream = CaptionStream()
        stream.apply(text: "hello world", isFinal: true, speaker: 0, rawSlot: 1, speakerTraits: traits)
        XCTAssertEqual(stream.lines.count, 1)
        let line = stream.lines[0]
        XCTAssertTrue(line.isFinal)
        XCTAssertNotNil(line.speakerTraits)
        XCTAssertEqual(line.speakerTraits?.pitchHz, 150)
        XCTAssertEqual(line.rawSlot, 1)
    }

    func testLiveCaptionLineHasNilSpeakerTraits() {
        let traits = SpeakerTraits(pitchHz: 150, syllablesPerSecond: 5)
        var stream = CaptionStream()
        stream.apply(text: "hello", isFinal: false, speaker: 0, rawSlot: 1, speakerTraits: traits)
        XCTAssertEqual(stream.lines.count, 1)
        let line = stream.lines[0]
        XCTAssertFalse(line.isFinal)
        XCTAssertNil(line.speakerTraits, "Live captions should not have speaker traits")
        XCTAssertNil(line.rawSlot, "Live captions should not have rawSlot")
    }

    func testFaceToFaceLinesHaveNilSpeakerTraits() {
        let traits = SpeakerTraits(pitchHz: 150, syllablesPerSecond: 5)
        var stream = CaptionStream()
        stream.apply(text: "hello", isFinal: true, speaker: 0, lane: .owner, rawSlot: 1, speakerTraits: traits)
        XCTAssertEqual(stream.lines.count, 1)
        let line = stream.lines[0]
        XCTAssertNotNil(line.lane)
        XCTAssertNil(line.speakerTraits, "Face-to-face captions should not have speaker traits")
    }

    func testMultipleSpeakersMapToCorrectSlots() {
        var stream = CaptionStream()
        let traits1 = SpeakerTraits(pitchHz: 100, syllablesPerSecond: 4)
        let traits2 = SpeakerTraits(pitchHz: 200, syllablesPerSecond: 6)
        stream.apply(text: "speaker one", isFinal: true, speaker: 0, rawSlot: 0, speakerTraits: traits1)
        stream.apply(text: "speaker two", isFinal: true, speaker: 1, rawSlot: 1, speakerTraits: traits2)
        XCTAssertEqual(stream.lines.count, 2)
        XCTAssertEqual(stream.lines[0].rawSlot, 0)
        XCTAssertEqual(stream.lines[0].speakerTraits?.pitchHz, 100)
        XCTAssertEqual(stream.lines[1].rawSlot, 1)
        XCTAssertEqual(stream.lines[1].speakerTraits?.pitchHz, 200)
    }

    func testPhrasesCarrySpeakerSlotForMatching() {
        var lines: [CaptionLine] = []
        var stream = CaptionStream()
        stream.apply(text: "hello world", isFinal: true, speaker: 0, rawSlot: 5)
        lines = stream.lines

        var phrases = EarPhrases()
        let phrasesOut = phrases.take(from: lines, now: 0)
        XCTAssertGreaterThan(phrasesOut.count, 0)
        let phrase = phrasesOut[0]
        XCTAssertEqual(phrase.speakerSlot, 5, "Phrase should carry the raw slot for voice matching")
    }
}

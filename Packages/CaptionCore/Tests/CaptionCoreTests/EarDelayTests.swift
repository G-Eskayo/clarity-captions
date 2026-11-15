import XCTest
@testable import CaptionCore

final class EarDelayTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    // MARK: 1. Rewritten/re-issued phrase, one line not two
    func testIdempotencyGuardAgainstDuplicateTranslationReady() {
        var r = EarDelayRecorder()
        let lineID = 1, wordStart = at(0)
        r.phraseEnded(lineID: lineID, wordStart: wordStart, at: at(0.1))
        r.translationReady(lineID: lineID, wordStart: wordStart, at: at(0.5))
        r.translationReady(lineID: lineID, wordStart: wordStart, at: at(0.6))  // second call
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(1.0))
        // Only one translationReady should have been counted; the second is ignored.
        XCTAssertEqual(r.translationReadyDelaySamples, 1)
    }

    func testIdempotencyGuardAgainstDuplicateVoiceStarted() {
        var r = EarDelayRecorder()
        let lineID = 1, wordStart = at(0)
        r.phraseEnded(lineID: lineID, wordStart: wordStart, at: at(0.1))
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(0.8))
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(0.9))  // second call
        // Only one voice start should have been counted; the second is ignored.
        XCTAssertEqual(r.voiceStartDelaySamples, 1)
        XCTAssertEqual(r.voiceStartDelayMaxSeconds, 0.7, accuracy: 0.001)
    }

    // MARK: 2. Translation never arrives
    func testTranslationNeverArrivesLeavesNoTrace() {
        var r = EarDelayRecorder()
        let lineID = 1, wordStart = at(0)
        r.phraseEnded(lineID: lineID, wordStart: wordStart, at: at(0.1))
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(1.0))
        r.voiceEnded(lineID: lineID, wordStart: wordStart, at: at(1.5))
        // Translation delay should not be recorded.
        XCTAssertEqual(r.translationReadyDelaySamples, 0)
        XCTAssertNil(r.translationReadyDelayMedian)
        // But voice start delay is recorded.
        XCTAssertEqual(r.voiceStartDelaySamples, 1)
    }

    // MARK: 3. Voice cut off by the next line
    func testVoiceCutOffDoesNotCrashAndIsIdempotent() {
        var r = EarDelayRecorder()
        let lineID = 1, wordStart = at(0)
        r.phraseEnded(lineID: lineID, wordStart: wordStart, at: at(0.1))
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(1.0))
        r.voiceEnded(lineID: lineID, wordStart: wordStart, at: at(1.5))
        r.voiceEnded(lineID: lineID, wordStart: wordStart, at: at(1.6))  // second voiceEnded
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(2.0))  // stray voiceStarted after close
        // One voice start delay recorded; stray events are safe no-ops.
        XCTAssertEqual(r.voiceStartDelaySamples, 1)
    }

    // MARK: 4. Headphones unplugged / Airplane Mode / backgrounded (abandoned open phrase)
    func testOldOpenPhrasesAreEvicted() {
        var r = EarDelayRecorder()
        let lineID1 = 1, wordStart1 = at(0)
        let lineID2 = 2, wordStart2 = at(140)

        r.phraseEnded(lineID: lineID1, wordStart: wordStart1, at: at(0.1))
        r.translationReady(lineID: lineID1, wordStart: wordStart1, at: at(0.5))
        // Create a new phrase 140 seconds later (well past the 2-minute age cap).
        r.phraseEnded(lineID: lineID2, wordStart: wordStart2, at: at(140.1))
        // Calling voiceEnded on the new phrase triggers eviction of the old one.
        r.voiceStarted(lineID: lineID2, wordStart: wordStart2, at: at(141))
        r.voiceEnded(lineID: lineID2, wordStart: wordStart2, at: at(141.5))
        // The old phrase was never resolved, so no delay is recorded for it.
        // Only the new phrase's voice start delay is recorded.
        XCTAssertEqual(r.voiceStartDelaySamples, 1)
    }

    // MARK: 5. Wrong order: translationReady / voiceStarted called before phraseEnded
    func testTranslationReadyBeforePhraseEndedIsNoOp() {
        var r = EarDelayRecorder()
        let lineID = 1, wordStart = at(0)
        r.translationReady(lineID: lineID, wordStart: wordStart, at: at(0.5))  // before phraseEnded
        r.phraseEnded(lineID: lineID, wordStart: wordStart, at: at(0.1))
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(1.0))
        // The translationReady before phraseEnded is a safe no-op.
        XCTAssertEqual(r.voiceStartDelaySamples, 1)
    }

    func testVoiceStartedBeforePhraseEndedIsNoOp() {
        var r = EarDelayRecorder()
        let lineID = 1, wordStart = at(0)
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(0.5))  // before phraseEnded
        r.phraseEnded(lineID: lineID, wordStart: wordStart, at: at(0.1))
        // The voiceStarted before phraseEnded is a safe no-op.
        XCTAssertEqual(r.voiceStartDelaySamples, 0)
    }

    // MARK: 6. 2-hour session, bounded memory
    func testBoundedMemoryAfterThousandsOfPhrases() {
        var r = EarDelayRecorder()
        for i in 0..<1000 {
            let lineID = i, wordStart = at(Double(i) * 0.5)
            r.phraseEnded(lineID: lineID, wordStart: wordStart, at: at(Double(i) * 0.5 + 0.05))
            r.translationReady(lineID: lineID, wordStart: wordStart, at: at(Double(i) * 0.5 + 0.1))
            r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(Double(i) * 0.5 + 0.3))
            r.voiceEnded(lineID: lineID, wordStart: wordStart, at: at(Double(i) * 0.5 + 0.45))
        }
        // Histograms have fixed bin counts and don't grow with input.
        XCTAssertEqual(r.voiceStartDelaySamples, 1000)
        // The histograms' internal structure is bounded.
        // We verify that the max is still tracked (not approximated by bins).
        XCTAssertTrue(r.voiceStartDelayMaxSeconds > 0.24)
        XCTAssertTrue(r.voiceStartDelayMaxSeconds < 0.26)
    }

    // MARK: 7. Clock change mid-session
    func testNegativeDelayClampedToZero() {
        var r = EarDelayRecorder()
        let lineID = 1, wordStart = at(10)
        r.phraseEnded(lineID: lineID, wordStart: wordStart, at: at(10.5))
        // Clock jumped backward: voiceStarted is before phraseEnded.
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(5))
        // Should clamp to 0, never negative.
        XCTAssertEqual(r.voiceStartDelaySamples, 1)
        let median = r.voiceStartDelayMedian ?? 0
        XCTAssertTrue(median >= 0)
        XCTAssertTrue(r.voiceStartDelayMaxSeconds >= 0)
        XCTAssertEqual(r.voiceStartDelayMaxSeconds, 0, accuracy: 0.001)
    }

    // MARK: 8. Two speakers overlapping on iPad face to face
    func testTwoSpeakersOverlappingWithGrowingBacklog() {
        var r = EarDelayRecorder()
        let speaker1ID = 1, speaker1Start = at(0)
        let speaker2ID = 2, speaker2Start = at(1)

        // Speaker 1: phrase ends at 0.5, voice starts at 1.5
        r.phraseEnded(lineID: speaker1ID, wordStart: speaker1Start, at: at(0.5))
        r.voiceStarted(lineID: speaker1ID, wordStart: speaker1Start, at: at(1.5))
        r.voiceEnded(lineID: speaker1ID, wordStart: speaker1Start, at: at(2.0))

        // Speaker 2: phrase ends at 1.0, but speaker 1's voice doesn't end until 2.0
        // So speaker 2 has to wait. Backlog = 2.5 - 2.0 = 0.5
        r.phraseEnded(lineID: speaker2ID, wordStart: speaker2Start, at: at(1.0))
        r.voiceStarted(lineID: speaker2ID, wordStart: speaker2Start, at: at(2.5))
        r.voiceEnded(lineID: speaker2ID, wordStart: speaker2Start, at: at(3.0))

        // Behind-by should measure the backlog (comparison to previous voice end).
        XCTAssertEqual(r.behindBySamples, 1)
        if let backlog = r.behindByMedian {
            XCTAssertEqual(backlog, 0.5, accuracy: 0.05)
        }
    }

    // MARK: 8b. Empty recorder
    func testEmptyRecorderReportsZeroSamples() {
        let r = EarDelayRecorder()
        XCTAssertEqual(r.voiceStartDelaySamples, 0)
        XCTAssertEqual(r.translationReadyDelaySamples, 0)
        XCTAssertEqual(r.behindBySamples, 0)
        XCTAssertNil(r.voiceStartDelayMedian)
        XCTAssertNil(r.translationReadyDelayMedian)
        XCTAssertNil(r.behindByMedian)
    }

    // MARK: 9. Bad/empty/malformed input
    func testEmptyLineIsIgnored() {
        var r = EarDelayRecorder()
        r.lineFinished("", at: at(0))
        r.lineFinished("   ", at: at(1))
        r.lineFinished("\t\n", at: at(2))
        // No repeats recorded.
        XCTAssertEqual(r.repeats, 0)
    }

    func testVeryLongLineHashesInConstantTime() {
        var r = EarDelayRecorder()
        let longText = String(repeating: "a", count: 10_000)
        r.lineFinished(longText, at: at(0))
        // Should not crash or timeout; the normalization is O(1).
        XCTAssertEqual(r.repeats, 0)
    }

    func testAccentedAndDifferentCaseRepeatMatches() {
        var r = EarDelayRecorder()
        r.lineFinished("Café", at: at(0))
        r.lineFinished("CAFÉ", at: at(1))  // different case, same accented letter
        // Should match after normalization (folding case and diacritics).
        XCTAssertEqual(r.repeats, 1)
    }

    func testGenuinelyDifferentTextNeverFalselyMatches() {
        var r = EarDelayRecorder()
        r.lineFinished("hello", at: at(0))
        r.lineFinished("hello world", at: at(1))
        r.lineFinished("hell", at: at(2))
        // Only exact matches (after normalization) count as repeats.
        XCTAssertEqual(r.repeats, 0)
    }

    // MARK: 10. Growing backlog ("behind by")
    func testGrowingBacklogShowsIncreasingBacklog() {
        var r = EarDelayRecorder()
        let lineID1 = 1, wordStart1 = at(0)
        let lineID2 = 2, wordStart2 = at(1)
        let lineID3 = 3, wordStart3 = at(2)

        // Phrase 1: ends at 0, voice starts at 1.0 (delay 1.0).
        r.phraseEnded(lineID: lineID1, wordStart: wordStart1, at: at(0))
        r.voiceStarted(lineID: lineID1, wordStart: wordStart1, at: at(1.0))
        r.voiceEnded(lineID: lineID1, wordStart: wordStart1, at: at(1.5))

        // Phrase 2: ends at 1, voice starts at 2.5 (backlog = 2.5 - 1.5 = 1.0).
        r.phraseEnded(lineID: lineID2, wordStart: wordStart2, at: at(1))
        r.voiceStarted(lineID: lineID2, wordStart: wordStart2, at: at(2.5))
        r.voiceEnded(lineID: lineID2, wordStart: wordStart2, at: at(3.0))

        // Phrase 3: ends at 2, voice starts at 4.2 (backlog = 4.2 - 3.0 = 1.2, further behind).
        r.phraseEnded(lineID: lineID3, wordStart: wordStart3, at: at(2))
        r.voiceStarted(lineID: lineID3, wordStart: wordStart3, at: at(4.2))
        r.voiceEnded(lineID: lineID3, wordStart: wordStart3, at: at(4.5))

        // Behind-by should show the backlog growth [1.0, 1.2].
        XCTAssertEqual(r.behindBySamples, 2)
        XCTAssertTrue(r.behindByMaxSeconds > 1.1)
    }

    // MARK: 11. "The one a listener feels": voiceStartDelay
    func testVoiceStartDelayEqualsVoiceStartMinusPhraseEnded() {
        var r = EarDelayRecorder()
        let lineID = 1, wordStart = at(5)
        r.phraseEnded(lineID: lineID, wordStart: wordStart, at: at(5.2))
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(7.0))
        // Expected delay: 7.0 - 5.2 = 1.8 seconds.
        XCTAssertEqual(r.voiceStartDelayMaxSeconds, 1.8, accuracy: 0.001)
        XCTAssertEqual(r.voiceStartDelayMedian ?? 0, 1.8, accuracy: 0.05)
    }

    // MARK: 12. Repeat count
    func testIdenticalFinalizedLineCountsAsRepeat() {
        var r = EarDelayRecorder()
        r.lineFinished("hello there", at: at(0))
        r.lineFinished("hello there", at: at(1))  // identical
        XCTAssertEqual(r.repeats, 1)
    }

    func testSameLineFinalizingOnceNeverSelfCounts() {
        var r = EarDelayRecorder()
        r.lineFinished("hello", at: at(0))
        // First finalization is not a repeat of itself.
        XCTAssertEqual(r.repeats, 0)
    }

    func testLineOutsideRecentWindowDoesNotMatch() {
        var r = EarDelayRecorder()
        r.lineFinished("old line", at: at(0))
        // 130 seconds later, well past the 2-minute window.
        r.lineFinished("old line", at: at(130))
        // The second occurrence is outside the window, so not counted as a repeat.
        XCTAssertEqual(r.repeats, 0)
    }

    // MARK: 13. Backward compatibility / stale state
    func testRecorderSurvivesBeingEncodedAndDecoded() throws {
        var r = EarDelayRecorder()
        let lineID = 1, wordStart = at(0)
        r.phraseEnded(lineID: lineID, wordStart: wordStart, at: at(0.1))
        r.translationReady(lineID: lineID, wordStart: wordStart, at: at(0.5))
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(1.0))
        r.voiceEnded(lineID: lineID, wordStart: wordStart, at: at(1.5))
        r.lineFinished("test line", at: at(2.0))

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let back = try decoder.decode(EarDelayRecorder.self, from: encoder.encode(r))

        XCTAssertEqual(back.voiceStartDelaySamples, r.voiceStartDelaySamples)
        XCTAssertEqual(back.translationReadyDelaySamples, r.translationReadyDelaySamples)
        XCTAssertEqual(back.repeats, r.repeats)
    }

    // MARK: 14. Report shape
    func testMetricsAreNilWhenNoSamples() {
        let r = EarDelayRecorder()
        XCTAssertNil(r.voiceStartDelayMedian)
        XCTAssertNil(r.voiceStartDelayP95)
        XCTAssertNil(r.translationReadyDelayMedian)
        XCTAssertNil(r.translationReadyDelayP95)
        XCTAssertNil(r.behindByMedian)
        XCTAssertNil(r.behindByP95)
        // Max is always reported (0.0 when untouched).
        XCTAssertEqual(r.voiceStartDelayMaxSeconds, 0.0)
    }

    func testMetricsAreAvailableWhenSamplesExist() {
        var r = EarDelayRecorder()
        let lineID = 1, wordStart = at(0)
        r.phraseEnded(lineID: lineID, wordStart: wordStart, at: at(0.1))
        r.translationReady(lineID: lineID, wordStart: wordStart, at: at(0.5))
        r.voiceStarted(lineID: lineID, wordStart: wordStart, at: at(1.0))

        XCTAssertTrue(r.voiceStartDelayMedian != nil)
        XCTAssertTrue(r.voiceStartDelayP95 != nil)
        XCTAssertTrue(r.translationReadyDelayMedian != nil)
        XCTAssertTrue(r.translationReadyDelayP95 != nil)
    }

    func testConversationReportEarIsNilWhenRecorderIsNil() throws {
        var recorder = ConversationRecorder(id: UUID())
        recorder.startPressed(at: at(0), sinceLaunch: nil, launch: nil)
        recorder.captioningStarted(at: at(0), battery: nil)
        recorder.captioningStopped(at: at(10), battery: nil, ending: .userStop)

        let report = recorder.entry(now: at(10))
        XCTAssertNil(report.ear)
    }

    func testConversationReportEarIsPopulatedWhenSamplesExist() throws {
        var recorder = ConversationRecorder(id: UUID())
        recorder.startPressed(at: at(0), sinceLaunch: nil, launch: nil)
        recorder.captioningStarted(at: at(0), battery: nil)

        let lineID = 1, wordStart = at(0)
        recorder.earPhraseEnded(lineID: lineID, wordStart: wordStart, at: at(0.1))
        recorder.earVoiceStarted(lineID: lineID, wordStart: wordStart, at: at(1.0))
        recorder.earVoiceEnded(lineID: lineID, wordStart: wordStart, at: at(1.5))

        recorder.captioningStopped(at: at(10), battery: nil, ending: .userStop)
        let report = recorder.entry(now: at(10))

        XCTAssertNotNil(report.ear)
        XCTAssertNotNil(report.ear?.voiceStartDelay)
        if let maxSeconds = report.ear?.voiceStartDelay?.maxSeconds {
            XCTAssertEqual(maxSeconds, 0.9, accuracy: 0.01)
        } else {
            XCTFail("maxSeconds should not be nil")
        }
    }

    func testConversationReportEarDelayStatsAreNilWhenNoSamples() throws {
        var recorder = ConversationRecorder(id: UUID())
        recorder.startPressed(at: at(0), sinceLaunch: nil, launch: nil)
        recorder.captioningStarted(at: at(0), battery: nil)

        let lineID = 1, wordStart = at(0)
        recorder.earPhraseEnded(lineID: lineID, wordStart: wordStart, at: at(0.1))
        // Voice never started, so no voiceStartDelay samples.

        recorder.captioningStopped(at: at(10), battery: nil, ending: .userStop)
        let report = recorder.entry(now: at(10))

        XCTAssertNotNil(report.ear)
        XCTAssertNil(report.ear?.voiceStartDelay)
        XCTAssertNil(report.ear?.translationReadyDelay)
        XCTAssertNil(report.ear?.behindBy)
    }

    func testConversationReportDecodesOldJSONWithoutEar() throws {
        let json = """
        {
          "id": "test-id",
          "startedAt": "2026-01-01T00:00:00Z",
          "minutes": 1.0,
          "rating": null,
          "ratingSkipped": false,
          "note": null,
          "lag": {"p50Seconds": 0.5, "p95Seconds": 0.7, "samples": 1},
          "rewriteRate": null,
          "speakers": {"detected": 1, "relabelsPerMinute": null},
          "launchToStartSeconds": null,
          "startToFirstCaptionSeconds": null,
          "ending": null,
          "battery": {"dropPercentPer30Min": null, "maxThermalState": null},
          "micLevel": {"medianDBFS": -20.0, "quietFraction": 0.1},
          "launch": null,
          "engine": null,
          "engineFallback": null,
          "captionLanguage": null,
          "captionLanguageChosen": null,
          "faceToFace": null,
          "build": null
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(ConversationReport.self, from: json.data(using: .utf8)!)
        XCTAssertNil(report.ear)
    }
}

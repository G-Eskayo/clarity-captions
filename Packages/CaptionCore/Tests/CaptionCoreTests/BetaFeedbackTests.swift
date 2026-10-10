import XCTest
@testable import CaptionCore

/// ADR 0023 (#112): beta-only feedback and metrics. These try to break the promises that matter: App Store installs
/// record nothing, the card shows only when the owner said, the numbers are right, and no caption text ever reaches
/// a report, a preview, the message or the file on the phone.
final class BetaFeedbackTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    // MARK: environment

    func testOnlyTestFlightAndDevelopmentBuildsRecord() {
        XCTAssertTrue(BetaEnvironment.sandbox.featuresOn)
        XCTAssertTrue(BetaEnvironment.xcode.featuresOn)
        XCTAssertFalse(BetaEnvironment.production.featuresOn)
        XCTAssertFalse(BetaEnvironment.unknown.featuresOn, "an unverified or failed check must behave as the App Store")
    }

    // MARK: when the card shows

    private func show(_ event: RatingCardTiming.Event, _ ending: ConversationEnding?, left: Bool = false,
                      asked: Bool = false, has: Bool = true, captioning: Bool = false) -> Bool {
        RatingCardTiming.shouldShow(event: event, ending: ending, leftWhileCaptioning: left,
                                    alreadyAsked: asked, hasConversation: has, isCaptioning: captioning)
    }

    func testHerOwnStopWaitsForNew() {
        XCTAssertFalse(show(.returnedToConversation, .userStop), "she paused on purpose: she may come back to it")
        XCTAssertTrue(show(.newTapped, .userStop))
    }

    func testAPauseWithoutHerShowsOnReturnOrNew() {
        for ending in [ConversationEnding.quietStop, .failure("The microphone stopped"), .appClosed] {
            XCTAssertTrue(show(.returnedToConversation, ending), "\(ending.kind)")
            XCTAssertTrue(show(.newTapped, ending), "\(ending.kind)")
        }
    }

    func testLeavingMidConversationShowsOnReturnEvenIfTheLastEndingWasHerStop() {
        XCTAssertTrue(show(.returnedToConversation, .userStop, left: true))
        XCTAssertTrue(show(.returnedToConversation, nil, left: true))
    }

    func testNeverWhileCaptioningNeverTwiceNeverEmpty() {
        XCTAssertFalse(show(.newTapped, .quietStop, captioning: true))
        XCTAssertFalse(show(.newTapped, .quietStop, asked: true))
        XCTAssertFalse(show(.returnedToConversation, .quietStop, asked: true))
        XCTAssertFalse(show(.newTapped, .userStop, has: false))
        XCTAssertFalse(show(.returnedToConversation, nil), "no ending and she never left: nothing to ask about")
    }

    func testEndingsFromStates() {
        XCTAssertEqual(ConversationEnding.from(.idle), .userStop)
        XCTAssertEqual(ConversationEnding.from(.pausedQuiet(minutes: 5)), .quietStop)
        XCTAssertEqual(ConversationEnding.from(.failed("No mic")), .failure("No mic"))
        XCTAssertNil(ConversationEnding.from(.listening))
        XCTAssertNil(ConversationEnding.from(.preparing))
    }

    // MARK: histogram

    func testPercentilesFromTheHistogram() {
        var h = PercentileHistogram(lower: 0, upper: 10, binWidth: 0.05)
        for i in 1...100 { h.add(Double(i) / 100) }   // 0.01 ... 1.00
        XCTAssertEqual(h.value(at: 0.5)!, 0.5, accuracy: 0.05)
        XCTAssertEqual(h.value(at: 0.95)!, 0.95, accuracy: 0.05)
        XCTAssertEqual(h.count, 100)
    }

    func testOutOfRangeAndNonFiniteValuesNeverCrashOrDisappear() {
        var h = PercentileHistogram(lower: 0, upper: 10, binWidth: 0.05)
        h.add(-3)            // a clock disagreement can make lag negative
        h.add(500)           // a frozen engine
        h.add(.nan)
        h.add(.infinity)
        XCTAssertEqual(h.count, 2)
        XCTAssertNotNil(h.value(at: 0.95))
        XCTAssertNil(PercentileHistogram(lower: 0, upper: 1, binWidth: 0.1).value(at: 0.5), "empty: no number, not zero")
    }

    func testMergeAddsCountsAndRefusesMismatchedShapes() {
        var a = PercentileHistogram(lower: 0, upper: 10, binWidth: 0.05)
        var b = a
        a.add(1); b.add(2); b.add(3)
        a.merge(b)
        XCTAssertEqual(a.count, 3)
        a.merge(PercentileHistogram(lower: 0, upper: 5, binWidth: 1))
        XCTAssertEqual(a.count, 3)
    }

    // MARK: measurements

    private func conversation() -> ConversationRecorder {
        var r = ConversationRecorder(id: UUID())
        r.startPressed(at: at(0), sinceLaunch: 2.1, launch: .init(fullDance: false, barShown: false))
        r.captioningStarted(at: at(0.5), battery: BatterySample(level: 0.80, charging: false))
        return r
    }

    func testLagMedianAndWorst() {
        var r = conversation()
        for (i, lag) in [0.6, 0.6, 0.6, 0.7, 0.6, 0.6, 0.6, 0.6, 0.6, 1.5].enumerated() {
            r.captionUpdate(text: "word \(i)", isFinal: false, speaker: 0, lagSeconds: lag, at: at(1 + Double(i)))
        }
        let e = r.entry(now: at(60))
        XCTAssertEqual(e.lag.p50Seconds!, 0.6, accuracy: 0.05)
        XCTAssertEqual(e.lag.p95Seconds!, 1.5, accuracy: 0.05)
        XCTAssertEqual(e.lag.samples, 10)
    }

    func testStartToFirstCaptionCountsFromStartAndIgnoresEmptyResults() {
        var r = conversation()
        r.captionUpdate(text: "   ", isFinal: false, speaker: nil, lagSeconds: nil, at: at(0.9))
        r.captionUpdate(text: "Hello", isFinal: false, speaker: nil, lagSeconds: nil, at: at(1.3))
        r.captionUpdate(text: "Hello there", isFinal: true, speaker: nil, lagSeconds: nil, at: at(2))
        XCTAssertEqual(r.entry(now: at(3)).startToFirstCaptionSeconds!, 1.3, accuracy: 0.001)
    }

    func testLaunchToStartIsKeptFromTheFirstStartOnly() {
        var r = conversation()
        r.startPressed(at: at(100), sinceLaunch: 99, launch: .init(fullDance: true, barShown: true))
        let e = r.entry(now: at(200))
        XCTAssertEqual(e.launchToStartSeconds, 2.1)
        XCTAssertEqual(e.launch, .init(fullDance: false, barShown: false))
    }

    func testRewriteRateCountsWordsChangedAfterAppearing() {
        var r = conversation()
        r.captionUpdate(text: "the waiter said", isFinal: false, speaker: 0, lagSeconds: nil, at: at(1))
        r.captionUpdate(text: "the water said they", isFinal: false, speaker: 0, lagSeconds: nil, at: at(2))   // 1 changed
        r.captionUpdate(text: "the waiter said they make", isFinal: true, speaker: 0, lagSeconds: nil, at: at(3)) // 1 changed
        r.captionUpdate(text: "ravioli", isFinal: false, speaker: 1, lagSeconds: nil, at: at(4))
        r.captionUpdate(text: "ravioli every morning", isFinal: true, speaker: 1, lagSeconds: nil, at: at(5))     // 0 changed
        // 2 changes over 8 final words.
        XCTAssertEqual(r.entry(now: at(6)).rewriteRate!, 0.25, accuracy: 0.001)
    }

    func testAWordThatDisappearsCountsAsARewrite() {
        var r = conversation()
        r.captionUpdate(text: "see you at seven", isFinal: false, speaker: 0, lagSeconds: nil, at: at(1))
        r.captionUpdate(text: "see you", isFinal: true, speaker: 0, lagSeconds: nil, at: at(2))
        XCTAssertEqual(r.entry(now: at(3)).rewriteRate!, 1.0, accuracy: 0.001, "2 changed over 2 final words, capped at 1")
    }

    func testNoWordsMeansNoRewriteRateRatherThanZero() {
        XCTAssertNil(conversation().entry(now: at(10)).rewriteRate)
    }

    func testSpeakersDetectedAndLiveRelabelsPerMinute() {
        var r = conversation()
        r.captionUpdate(text: "a", isFinal: false, speaker: 0, lagSeconds: nil, at: at(1))
        r.captionUpdate(text: "a b", isFinal: false, speaker: 1, lagSeconds: nil, at: at(2))   // relabel
        r.captionUpdate(text: "a b c", isFinal: true, speaker: 0, lagSeconds: nil, at: at(3))  // relabel
        r.captionUpdate(text: "d", isFinal: true, speaker: 2, lagSeconds: nil, at: at(4))      // new line: not a relabel
        r.captionUpdate(text: "e", isFinal: false, speaker: nil, lagSeconds: nil, at: at(5))   // unknown: not a relabel
        r.captioningStopped(at: at(120.5), battery: nil, ending: .userStop)                   // 2 minutes
        let e = r.entry(now: at(130))
        XCTAssertEqual(e.speakers.detected, 3)
        XCTAssertEqual(e.speakers.relabelsPerMinute!, 1.0, accuracy: 0.001)
        XCTAssertEqual(e.minutes, 2.0)
    }

    func testEndingAndMinutesAcrossPausesAndResumes() {
        var r = conversation()
        r.captioningStopped(at: at(60.5), battery: nil, ending: .quietStop)
        r.captioningStarted(at: at(500), battery: nil)
        XCTAssertNil(r.entry(now: at(530)).ending, "resumed: running, so no ending yet")
        XCTAssertEqual(r.entry(now: at(530)).minutes, 1.5, "a running stretch counts up to now")
        r.captioningStopped(at: at(560), battery: nil, ending: .failure("The microphone stopped"))
        let e = r.entry(now: at(9999))
        XCTAssertEqual(e.minutes, 2.0, "time paused never counts")
        XCTAssertEqual(e.ending, .failure("The microphone stopped"))
    }

    func testASecondStopForTheSameStretchChangesNothing() {
        var r = conversation()
        r.captioningStopped(at: at(60.5), battery: nil, ending: .userStop)
        r.captioningStopped(at: at(999), battery: nil, ending: .userStop)
        XCTAssertEqual(r.entry(now: at(1000)).minutes, 1.0)
    }

    func testBatteryDropScaledTo30MinutesIgnoringChargingAndUnknown() {
        var r = conversation()   // 80% at 0.5 s
        r.captioningStopped(at: at(600.5), battery: BatterySample(level: 0.77, charging: false), ending: .userStop)  // 3% in 10 min
        r.captioningStarted(at: at(700), battery: BatterySample(level: 0.77, charging: true))
        r.captioningStopped(at: at(1300), battery: BatterySample(level: 0.90, charging: true), ending: .userStop)    // charging: ignored
        r.captioningStarted(at: at(1400), battery: BatterySample(level: -1, charging: false))
        r.captioningStopped(at: at(2000), battery: BatterySample(level: 0.5, charging: false), ending: .userStop)   // unknown: ignored
        XCTAssertEqual(r.entry(now: at(2001)).battery.dropPercentPer30Min!, 9.0, accuracy: 0.01)
    }

    func testTooShortToJudgeBatteryGivesNoNumber() {
        var r = conversation()
        r.captioningStopped(at: at(10), battery: BatterySample(level: 0.79, charging: false), ending: .userStop)
        XCTAssertNil(r.entry(now: at(11)).battery.dropPercentPer30Min, "1% over 10 s would read as 180% per 30 min")
    }

    func testHottestThermalStateIsKept() {
        var r = conversation()
        r.thermal(.fair); r.thermal(.serious); r.thermal(.nominal)
        XCTAssertEqual(r.entry(now: at(5)).battery.maxThermalState, "serious")
    }

    func testMicLevelSummary() {
        var r = conversation()
        for v in [-60.0, -55, -40, -38, -36] { r.audioLevel(v) }
        let e = r.entry(now: at(5))
        XCTAssertEqual(e.micLevel.medianDBFS!, -39.5, accuracy: 1.0)
        XCTAssertEqual(e.micLevel.quietFraction!, 0.4, accuracy: 0.001)
    }

    func testRatingIsClampedAndNoteTrimmedAndEmptyNoteIsNone() {
        var r = conversation()
        r.rate(14, note: "   ")
        XCTAssertEqual(r.entry(now: at(5)).rating, 10)
        XCTAssertNil(r.entry(now: at(5)).note)
        r.rate(0, note: "  Lost it when the waiter talked fast \n")
        XCTAssertEqual(r.entry(now: at(5)).rating, 1)
        XCTAssertEqual(r.entry(now: at(5)).note, "Lost it when the waiter talked fast")
        XCTAssertTrue(r.asked)
    }

    func testSkipIsRecordedAsASkip() {
        var r = conversation()
        r.skipRating()
        let e = r.entry(now: at(5))
        XCTAssertNil(e.rating)
        XCTAssertTrue(e.ratingSkipped)
        XCTAssertTrue(r.asked)
    }

    func testLeavingMidConversationAndColdLaunchRestore() {
        var r = conversation()
        r.leftMidConversation()
        XCTAssertTrue(r.leftWhileCaptioning)
        r.restoredAfterAppClosed(at: at(120.5))
        XCTAssertEqual(r.ending, .appClosed)
        XCTAssertTrue(RatingCardTiming.shouldShow(event: .returnedToConversation, ending: r.ending,
                                                  leftWhileCaptioning: r.leftWhileCaptioning, alreadyAsked: r.asked,
                                                  hasConversation: true, isCaptioning: false))
    }

    func testComingBackWhileStillCaptioningMeansHerLaterStopIsStillHers() {
        var r = conversation()
        r.leftMidConversation()
        r.backWhileCaptioning()
        r.captioningStopped(at: at(60), battery: nil, ending: .userStop)
        XCTAssertFalse(RatingCardTiming.shouldShow(event: .returnedToConversation, ending: r.ending,
                                                   leftWhileCaptioning: r.leftWhileCaptioning, alreadyAsked: r.asked,
                                                   hasConversation: true, isCaptioning: false),
                       "she came back, kept captioning, then pressed Stop herself: wait for [ New ]")
    }

    func testLeavingWhilePausedIsNotLeavingMidConversation() {
        var r = conversation()
        r.captioningStopped(at: at(30), battery: nil, ending: .userStop)
        r.leftMidConversation()
        XCTAssertFalse(r.leftWhileCaptioning)
        r.restoredAfterAppClosed(at: at(500))
        XCTAssertEqual(r.ending, .userStop, "paused by her before leaving: still her pause")
    }

    func testRecorderSurvivesBeingWrittenToThePhone() throws {
        var r = conversation()
        r.captionUpdate(text: "one two", isFinal: true, speaker: 0, lagSeconds: 0.8, at: at(2))
        r.thermal(.fair)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(ConversationRecorder.self, from: encoder.encode(r))
        XCTAssertEqual(back.entry(now: at(10)), r.entry(now: at(10)))
    }

    // MARK: the report

    private func report(_ conversations: [ConversationReport]) -> FeedbackReport {
        FeedbackReport(app: .init(version: "1.0", build: "42", environment: .sandbox),
                       device: .init(model: "iPhone15,4", os: "iOS 26.1", lowPowerModeSeen: false),
                       settings: .init(theme: "paper", lettering: "openDyslexic", textSize: "medium", quietStop: "fiveMinutes"),
                       sentAt: at(9000), conversations: conversations)
    }

    func testReportMatchesTheSchemaDocument() throws {
        var r = conversation()
        r.captionUpdate(text: "hello there", isFinal: true, speaker: 0, lagSeconds: 0.6, at: at(1.8))
        r.audioLevel(-40); r.thermal(.fair)
        r.rate(8, note: "Lost it when the waiter talked fast")
        r.captioningStopped(at: at(1400), battery: BatterySample(level: 0.74, charging: false), ending: .userStop)
        let data = try report([r.entry(now: at(1500))]).json(timeZone: TimeZone(identifier: "America/Denver")!)
        let ours = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.schemaExample()) as? [String: Any])
        XCTAssertEqual(Self.keyPaths(ours), Self.keyPaths(schema), "report keys must match docs/beta/metrics-schema.md")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"startedAt\" : \"2025-10-09T02:53:20-06:00\""),
                      "local ISO 8601 with offset, as in the schema")
    }

    func testFileName() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(FeedbackReport.fileName(build: "42", date: t0, timeZone: utc), "seal-feedback-42-20251009-0853.json")
        XCTAssertEqual(FeedbackReport.fileName(build: "../x y", date: t0, timeZone: utc), "seal-feedback-..xy-20251009-0853.json",
                       "a build string can't put slashes or spaces in the name")
    }

    func testPreviewIsNewestFirstInPlainWords() {
        var older = conversation(); older.rate(6, note: nil)
        older.captioningStopped(at: at(2460), battery: nil, ending: .quietStop)
        var newer = ConversationRecorder(id: UUID())
        newer.startPressed(at: at(100_000), sinceLaunch: nil, launch: nil)
        newer.captioningStarted(at: at(100_000), battery: nil)
        newer.skipRating()
        newer.captioningStopped(at: at(100_480), battery: nil, ending: .userStop)
        let cards = FeedbackPreview.cards(for: report([older.entry(now: at(3000)), newer.entry(now: at(100_500))]),
                                          locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(cards[0].title.hasSuffix("· 8 min"), cards[0].title)
        XCTAssertEqual(cards[0].rows.first, FeedbackPreviewRow(label: "Your rating", value: "Skipped"))
        XCTAssertTrue(cards[0].rows.contains(FeedbackPreviewRow(label: "Ended", value: "You pressed Stop")))
        XCTAssertEqual(cards[1].rows.first, FeedbackPreviewRow(label: "Your rating", value: "6 / 10"))
        XCTAssertTrue(cards[1].rows.contains(FeedbackPreviewRow(label: "Ended", value: "It went quiet")))
    }

    // MARK: storage

    private func tempStore() throws -> FeedbackStore {
        try FeedbackStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("feedback-\(UUID())"))
    }

    func testOnlyFinishedConversationsThatWereSentAreRemoved() throws {
        let store = try tempStore()
        let a = conversation(), b = conversation(), current = conversation()
        store.upsert(a, finished: true)
        store.upsert(b, finished: true)
        store.upsert(current, finished: false)
        store.removeSent(ids: [a.id, current.id])
        let left = Set(store.all().map(\.recorder.id))
        XCTAssertEqual(left, [b.id, current.id], "b wasn't sent; the one on screen keeps going and is sent again later")
    }

    func testUpsertReplacesByIdAndFinishedSticks() throws {
        let store = try tempStore()
        var r = conversation()
        store.upsert(r, finished: true)
        r.rate(9, note: nil)
        store.upsert(r, finished: false)
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all()[0].recorder.rating, 9)
        XCTAssertTrue(store.all()[0].finished)
    }

    func testAConversationThatNeverStartedIsNotKept() throws {
        let store = try tempStore()
        store.upsert(ConversationRecorder(id: UUID()), finished: true)
        XCTAssertTrue(store.all().isEmpty)
    }

    func testAppStoreInstallDeletesEverything() throws {
        let store = try tempStore()
        store.upsert(conversation(), finished: true)
        store.deleteAll()
        XCTAssertTrue(store.all().isEmpty)
    }

    func testThousandsOfConversationsStillRoundTrip() throws {
        let store = try tempStore()
        for _ in 0..<300 { store.upsert(conversation(), finished: true) }
        XCTAssertEqual(store.all().count, 300, "no cap until sent (ADR 0023)")
        let entries = (0..<1500).map { _ in conversation().entry(now: at(100)) }
        let data = try report(entries).json()
        XCTAssertLessThan(data.count, 3_000_000, "1,500 conversations are still a small text attachment")
    }

    // MARK: never the conversation

    func testCaptionTextNeverReachesAReportPreviewSummaryOrTheFileOnThePhone() throws {
        let sentinel = "PURPLE-ELEPHANT-7731"
        let store = try tempStore()
        var r = conversation()
        r.captionUpdate(text: "meet \(sentinel) at", isFinal: false, speaker: 0, lagSeconds: 0.5, at: at(1))
        r.captionUpdate(text: "meet \(sentinel) at Luigi's", isFinal: true, speaker: 0, lagSeconds: 0.6, at: at(2))
        r.captionUpdate(text: "\(sentinel) still on screen", isFinal: false, speaker: 1, lagSeconds: 0.7, at: at(3))
        store.upsert(r, finished: false)   // written mid-utterance, the riskiest moment
        r.captioningStopped(at: at(60), battery: nil, ending: .failure("The microphone stopped"))
        r.rate(7, note: nil)
        store.upsert(r, finished: true)

        let rep = report(store.all().map { $0.recorder.entry(now: at(100)) })
        let json = String(decoding: try rep.json(), as: UTF8.self)
        let preview = FeedbackPreview.cards(for: rep).flatMap { [$0.title] + $0.rows.flatMap { [$0.label, $0.value] } }.joined()
        let file = try String(contentsOf: store.directory.appendingPathComponent("unsent.json"), encoding: .utf8)
        for (what, text) in [("report", json), ("summary", rep.summary), ("preview", preview), ("file", file)] {
            XCTAssertFalse(text.contains(sentinel), "caption text leaked into the \(what)")
            XCTAssertFalse(text.contains("Luigi"), "caption text leaked into the \(what)")
        }
    }

    // MARK: helpers

    /// The JSON example in docs/beta/metrics-schema.md, with its "…" placeholders made valid.
    static func schemaExample() throws -> Data {
        let doc = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/beta/metrics-schema.md")
        let text = try String(contentsOf: doc, encoding: .utf8)
        let start = try XCTUnwrap(text.range(of: "```json\n"))
        let end = try XCTUnwrap(text.range(of: "\n```", range: start.upperBound..<text.endIndex))
        return Data(text[start.upperBound..<end.lowerBound].utf8)
    }

    /// Every key path in a JSON object; arrays contribute their first element's shape.
    static func keyPaths(_ value: Any, prefix: String = "") -> Set<String> {
        if let dict = value as? [String: Any] {
            return dict.reduce(into: Set<String>()) { out, kv in
                let path = prefix.isEmpty ? kv.key : "\(prefix).\(kv.key)"
                out.insert(path)
                out.formUnion(keyPaths(kv.value, prefix: path))
            }
        }
        if let array = value as? [Any], let first = array.first { return keyPaths(first, prefix: prefix + "[]") }
        return []
    }
}

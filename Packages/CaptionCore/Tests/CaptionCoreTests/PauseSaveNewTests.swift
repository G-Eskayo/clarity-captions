import XCTest
@testable import CaptionCore

/// #102: pressing Stop pauses the conversation instead of saving and clearing it. [ Save ] saves on request and
/// holds [ Saved ] until the content changes; [ New ] clears; the conversation survives app switches.
final class PauseSaveNewTests: XCTestCase {

    private func stream(_ texts: [(Int?, String)]) -> CaptionStream {
        var s = CaptionStream()
        for (speaker, text) in texts { s.apply(text: text, isFinal: true, speaker: speaker) }
        return s
    }

    // MARK: ConversationSession: save on request, changed-since-save

    func testNothingToSaveBeforeAnyCaptions() {
        let session = ConversationSession()
        XCTAssertEqual(session.saveButton(lines: [], names: SpeakerNames()), .unavailable)
        XCTAssertFalse(session.hasUnsavedChanges(lines: [], names: SpeakerNames()))
    }

    func testBlankLinesAreNotAConversation() {
        var s = CaptionStream()
        s.apply(text: "   ", isFinal: true)
        XCTAssertEqual(ConversationSession().saveButton(lines: s.lines, names: SpeakerNames()), .unavailable)
    }

    func testCaptionsMakeItSaveableAndUnsaved() {
        let lines = stream([(0, "hello there")]).lines
        let session = ConversationSession()
        XCTAssertEqual(session.saveButton(lines: lines, names: SpeakerNames()), .save)
        XCTAssertTrue(session.hasUnsavedChanges(lines: lines, names: SpeakerNames()))
    }

    func testSavingHoldsSavedUntilTheContentChanges() throws {
        var s = stream([(0, "hello there")])
        var session = ConversationSession()
        session.captioningStarted(at: Date(timeIntervalSince1970: 100))
        let saved = try XCTUnwrap(session.makeSaved(lines: s.lines, names: SpeakerNames(), now: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(saved.startedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(session.saveButton(lines: s.lines, names: SpeakerNames()), .saved)
        XCTAssertFalse(session.hasUnsavedChanges(lines: s.lines, names: SpeakerNames()))

        // Time passing changes nothing; new captions do.
        s.apply(text: "and one more thing", isFinal: true, speaker: 1)
        XCTAssertEqual(session.saveButton(lines: s.lines, names: SpeakerNames()), .save)
        XCTAssertTrue(session.hasUnsavedChanges(lines: s.lines, names: SpeakerNames()))
    }

    func testNamingASpeakerAfterSavingIsAChangeToWhatWouldBeSaved() throws {
        let lines = stream([(0, "hello")]).lines
        var session = ConversationSession()
        _ = try XCTUnwrap(session.makeSaved(lines: lines, names: SpeakerNames(), now: Date()))
        var names = SpeakerNames()
        names.apply("Dana", to: 0)
        XCTAssertEqual(session.saveButton(lines: lines, names: names), .save)
    }

    func testSavingAgainUpdatesTheSameSavedConversation() throws {
        var s = stream([(0, "hello")])
        var session = ConversationSession()
        session.captioningStarted(at: Date(timeIntervalSince1970: 10))
        let first = try XCTUnwrap(session.makeSaved(lines: s.lines, names: SpeakerNames(), now: Date(timeIntervalSince1970: 20)))
        session.captioningStarted(at: Date(timeIntervalSince1970: 30))   // resumed: the start date must not move
        s.apply(text: "more", isFinal: true, speaker: 1)
        let second = try XCTUnwrap(session.makeSaved(lines: s.lines, names: SpeakerNames(), now: Date(timeIntervalSince1970: 40)))
        XCTAssertEqual(first.id, second.id, "saving again overwrites the same saved conversation")
        XCTAssertEqual(second.startedAt, Date(timeIntervalSince1970: 10))
        XCTAssertNotEqual(first.transcript, second.transcript)
    }

    func testSavingNothingSavesNothing() {
        var session = ConversationSession()
        XCTAssertNil(session.makeSaved(lines: [], names: SpeakerNames(), now: Date()))
        XCTAssertEqual(session.saveButton(lines: [], names: SpeakerNames()), .unavailable)
    }

    func testStartDateFallsBackToSaveTimeWhenCaptioningNeverStarted() throws {
        // A restored or demo conversation may have no recorded start; saving must still work.
        let lines = stream([(0, "hello")]).lines
        var session = ConversationSession()
        let saved = try XCTUnwrap(session.makeSaved(lines: lines, names: SpeakerNames(), now: Date(timeIntervalSince1970: 5)))
        XCTAssertEqual(saved.startedAt, Date(timeIntervalSince1970: 5))
    }

    func testANewConversationIsADifferentSavedConversation() throws {
        let lines = stream([(0, "hello")]).lines
        var a = ConversationSession()
        let first = try XCTUnwrap(a.makeSaved(lines: lines, names: SpeakerNames(), now: Date()))
        var b = ConversationSession()
        let second = try XCTUnwrap(b.makeSaved(lines: lines, names: SpeakerNames(), now: Date()))
        XCTAssertNotEqual(first.id, second.id)
    }

    func testAnOpenVolatileTailCountsAsContent() {
        var s = CaptionStream()
        s.apply(text: "still talk", isFinal: false, speaker: 0)
        XCTAssertEqual(ConversationSession().saveButton(lines: s.lines, names: SpeakerNames()), .save)
    }

    // MARK: PauseVeil: the dim, tap to clear, hold on empty space to bring back

    func testVeilShowsOnlyWhenPausedWithAConversation() {
        let veil = PauseVeil()
        XCTAssertTrue(veil.isVisible(state: .idle, hasConversation: true))
        XCTAssertTrue(veil.isVisible(state: .pausedQuiet(minutes: 5), hasConversation: true))
        XCTAssertTrue(veil.isVisible(state: .failed("x"), hasConversation: true))
        XCTAssertFalse(veil.isVisible(state: .idle, hasConversation: false), "nothing to save: no veil")
        XCTAssertFalse(veil.isVisible(state: .listening, hasConversation: true))
        XCTAssertFalse(veil.isVisible(state: .preparing, hasConversation: true))
    }

    func testTapClearsAndHoldOnEmptySpaceBringsItBack() {
        var veil = PauseVeil()
        veil.tap(state: .idle)
        XCTAssertFalse(veil.isVisible(state: .idle, hasConversation: true))
        veil.holdOnEmptySpace(state: .idle)
        XCTAssertTrue(veil.isVisible(state: .idle, hasConversation: true))
    }

    func testTapAndHoldDoNothingWhileCaptioning() {
        var veil = PauseVeil()
        veil.tap(state: .listening)
        XCTAssertTrue(veil.isVisible(state: .idle, hasConversation: true), "a tap while listening must not pre-clear the next pause")
        veil.tap(state: .idle)
        veil.holdOnEmptySpace(state: .listening)
        XCTAssertFalse(veil.isVisible(state: .idle, hasConversation: true))
    }

    func testResumingResetsTheVeilForTheNextPause() {
        var veil = PauseVeil()
        veil.tap(state: .idle)
        veil.captioningStarted()
        XCTAssertTrue(veil.isVisible(state: .idle, hasConversation: true))
    }

    func testRepeatedTapsAndHoldsAreIdempotent() {
        var veil = PauseVeil()
        for _ in 0..<5 { veil.tap(state: .idle) }
        XCTAssertFalse(veil.isVisible(state: .idle, hasConversation: true))
        for _ in 0..<5 { veil.holdOnEmptySpace(state: .idle) }
        XCTAssertTrue(veil.isVisible(state: .idle, hasConversation: true))
    }

    // MARK: Status word

    func testPausedWithAConversationSaysPaused() {
        XCTAssertEqual(StatusWords.headline(for: .idle, hasConversation: true), String(localized: "Paused"))
        XCTAssertEqual(StatusWords.headline(for: .idle, hasConversation: false), StatusWords.headline(for: .idle))
        XCTAssertEqual(StatusWords.headline(for: .listening, hasConversation: true), StatusWords.headline(for: .listening))
        XCTAssertEqual(StatusWords.headline(for: .pausedQuiet(minutes: 5), hasConversation: true),
                       StatusWords.headline(for: .pausedQuiet(minutes: 5)))
    }

    // MARK: Resume continues the same conversation on a new line

    func testBreakLineStopsTheNextSessionMergingIntoTheLastLine() {
        // A resumed engine restarts its audio clock at zero; without a break, "0.2 s after the last line ended at
        // 300 s" would read as a short pause and merge into the previous line.
        var s = CaptionStream()
        s.apply(text: "before the pause", isFinal: true, speaker: 0, range: 299...300)
        s.breakLine()
        s.apply(text: "after resuming", isFinal: true, speaker: 0, range: 0.2...1.0)
        XCTAssertEqual(s.lines.map(\.text), ["before the pause", "after resuming"])
    }

    func testBreakLineClosesAnOpenTailAndIsSafeOnEmptyAndRepeated() {
        var empty = CaptionStream()
        empty.breakLine()
        XCTAssertTrue(empty.lines.isEmpty)

        var s = CaptionStream()
        s.apply(text: "half a sent", isFinal: false, speaker: 0, range: 0...1)
        s.breakLine(); s.breakLine()
        XCTAssertTrue(s.lines.last?.isFinal ?? false)
        s.apply(text: "next", isFinal: false, speaker: 0, range: 0...0.5)
        XCTAssertEqual(s.lines.map(\.text), ["half a sent", "next"], "a new volatile result must not revise the closed line")
    }

    func testBreakLineWithoutTimingStillStartsANewLine() {
        var s = CaptionStream()
        s.apply(text: "one", isFinal: false, speaker: 0)
        s.breakLine()
        s.apply(text: "two", isFinal: false, speaker: 0)
        XCTAssertEqual(s.lines.map(\.text), ["one", "two"])
    }

    // MARK: Cold launch policy (Decision "coldlaunch" on #102)

    func testRecommendedPolicyRestoresOnlyRecentConversations() {
        let rule = ColdLaunchRule.restoreIfAwayLessThan(minutes: 30)
        let left = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(rule.shouldRestore(leftAt: left, now: left.addingTimeInterval(29 * 60)))
        XCTAssertFalse(rule.shouldRestore(leftAt: left, now: left.addingTimeInterval(30 * 60)))
        XCTAssertFalse(rule.shouldRestore(leftAt: left, now: left.addingTimeInterval(3 * 24 * 3600)))
    }

    func testAClockSetBackwardIsMeasuredByDistanceNotSign() {
        let rule = ColdLaunchRule.restoreIfAwayLessThan(minutes: 30)
        let left = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(rule.shouldRestore(leftAt: left, now: left.addingTimeInterval(-60)))
        XCTAssertFalse(rule.shouldRestore(leftAt: left, now: left.addingTimeInterval(-2 * 3600)))
    }

    func testTheOtherOptionsAreOneLineAway() {
        let left = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(ColdLaunchRule.alwaysClear.shouldRestore(leftAt: left, now: left))
        XCTAssertTrue(ColdLaunchRule.alwaysKeep.shouldRestore(leftAt: left, now: left.addingTimeInterval(1e7)))
        XCTAssertEqual(ColdLaunchRule.current, .restoreIfAwayLessThan(minutes: 30))
    }

    // MARK: Current-conversation snapshot (kept across app switches and cold launches)

    func testSnapshotRoundTripsLinesNamesSoundsAndSavedState() throws {
        var s = CaptionStream()
        s.apply(text: "hi mom", isFinal: true, speaker: 0)
        s.insertSoundLabel(.laughter)
        s.apply(text: "hello", isFinal: true, speaker: 1)
        var names = SpeakerNames()
        names.apply("Gil", to: 0)
        var session = ConversationSession()
        session.captioningStarted(at: Date(timeIntervalSince1970: 7))
        _ = session.makeSaved(lines: s.lines, names: names, now: Date(timeIntervalSince1970: 8))

        let snapshot = CurrentConversationSnapshot(lines: s.lines, names: names, session: session, leftAt: Date(timeIntervalSince1970: 9))
        let data = try JSONEncoder().encode(snapshot)
        let back = try JSONDecoder().decode(CurrentConversationSnapshot.self, from: data)
        let restored = back.restore()

        XCTAssertEqual(restored.stream.lines.map(\.text), s.lines.map(\.text))
        XCTAssertEqual(restored.stream.lines.map(\.speaker), s.lines.map(\.speaker))
        XCTAssertEqual(restored.stream.lines[1].soundLabel, .laughter)
        XCTAssertEqual(restored.names.name(for: 0), "Gil")
        XCTAssertEqual(restored.session.saveButton(lines: restored.stream.lines, names: restored.names), .saved,
                       "a restored saved conversation still reads [ Saved ]")
        XCTAssertEqual(back.leftAt, Date(timeIntervalSince1970: 9))
    }

    func testAnOpenTailIsRestoredAsFinishedText() {
        var s = CaptionStream()
        s.apply(text: "cut off mid", isFinal: false, speaker: 0)
        let restored = CurrentConversationSnapshot(lines: s.lines, names: SpeakerNames(), session: ConversationSession(), leftAt: Date()).restore()
        XCTAssertEqual(restored.stream.lines.map(\.text), ["cut off mid"])
        XCTAssertTrue(restored.stream.lines[0].isFinal)
    }

    func testStoreWritesReadsAndDeletes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("current-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try CurrentConversationStore(directory: dir)
        XCTAssertNil(store.load())
        let snap = CurrentConversationSnapshot(lines: stream([(0, "x")]).lines, names: SpeakerNames(), session: ConversationSession(), leftAt: Date())
        try store.save(snap)
        XCTAssertEqual(store.load()?.restore().stream.lines.map(\.text), ["x"])
        store.delete()
        XCTAssertNil(store.load())
        store.delete()   // deleting twice is harmless
    }

    func testACorruptFileIsTreatedAsNothingAndRemoved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("current-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try CurrentConversationStore(directory: dir)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertNil(store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testColdLaunchDecisionRestoresOrDeletes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("current-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try CurrentConversationStore(directory: dir)
        let left = Date(timeIntervalSince1970: 1_000)
        try store.save(CurrentConversationSnapshot(lines: stream([(0, "x")]).lines, names: SpeakerNames(), session: ConversationSession(), leftAt: left))
        XCTAssertNotNil(store.restoreOnColdLaunch(now: left.addingTimeInterval(60), rule: .restoreIfAwayLessThan(minutes: 30)))

        try store.save(CurrentConversationSnapshot(lines: stream([(0, "x")]).lines, names: SpeakerNames(), session: ConversationSession(), leftAt: left))
        XCTAssertNil(store.restoreOnColdLaunch(now: left.addingTimeInterval(3600), rule: .restoreIfAwayLessThan(minutes: 30)))
        XCTAssertNil(store.load(), "an expired conversation is deleted, not left on the phone")
    }

    // MARK: [ Saved ] green

    func testSavedGreenStaysAAAOnEveryPreset() {
        for preset in CaptionPreset.all {
            let green = SavedGreen.color(on: preset.background)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(green, preset.background), 7, preset.id)
        }
    }
}

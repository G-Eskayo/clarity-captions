import Foundation
import Testing
@testable import SystemReplayKit

@Suite struct SessionLogTests {
    func log(plan engine: String = "parakeet", reason: String? = nil) -> SessionLog {
        SessionLog(label: "t", audio: "a.wav", audioSeconds: 1, tailSeconds: 0, deliveryRate: 48_000, framesPerBuffer: 4_096,
                   host: "h", os: "o", startedAt: "s",
                   plan: .init(engine: engine, reason: reason, locale: "en-US", choice: "parakeet",
                               availableMemoryBytes: 1, memorySource: "test", modelPresent: true))
    }

    func update(_ engine: String, at: Double) -> SessionLog.Update {
        .init(at: at, text: "x", isFinal: false, lag: nil, speaker: nil, start: nil, end: nil, engine: engine, fallback: nil)
    }

    @Test func aSwitchMidSessionIsSeenFromTheUpdatesAlone() {
        var l = log()
        l.record(update("parakeet-ultra-pal6", at: 1))
        l.record(update("parakeet-ultra-pal6", at: 2))
        l.record(update("apple-speechanalyzer", at: 30))
        #expect(l.enginesSeen == [.init(name: "parakeet-ultra-pal6", firstAt: 1), .init(name: "apple-speechanalyzer", firstAt: 30)])
        #expect(l.leftParakeet)   // no fallback callback fired, and it still counts
    }

    @Test func aWholeParakeetSessionDidNotLeave() {
        var l = log()
        l.record(update("parakeet-ultra-pal6", at: 1))
        l.record(update("", at: 2))   // an update before the engine named itself doesn't count as a switch
        #expect(!l.leftParakeet)
        #expect(l.enginesSeen.count == 1)
    }

    @Test func aPlanOnAppleOrAFallbackCountsAsLeaving() {
        #expect(log(plan: "apple", reason: "lowMemory").leftParakeet)
        var l = log()
        l.fallbacks.append(.init(reason: "noWordsFromSpeech", at: 20))
        #expect(l.leftParakeet)
    }

    @Test func roundTripsThroughJSON() throws {
        var l = log(plan: "apple", reason: "modelMissing")
        l.record(update("apple-speechanalyzer", at: 0.5))
        l.lines = [.init(text: "hello", speaker: 0, soundLabel: nil)]
        let back = try JSONDecoder().decode(SessionLog.self, from: JSONEncoder().encode(l))
        #expect(back.plan.reason == "modelMissing")
        #expect(back.updates.count == 1)
        #expect(back.lines.first?.text == "hello")
        #expect(back.harness == SessionLog.harnessVersion)
    }

    @Test func wordStructPreservesTextAndTiming() throws {
        let word = SessionLog.Word(text: "hello", start: 1.5, end: 2.3)
        #expect(word.text == "hello")
        #expect(word.start == 1.5)
        #expect(word.end == 2.3)
    }

    @Test func updateWithWordsRoundTripsJSON() throws {
        var l = log()
        let words = [
            SessionLog.Word(text: "hello", start: 0.1, end: 0.5),
            SessionLog.Word(text: "world", start: 0.6, end: 1.0)
        ]
        let upd = SessionLog.Update(at: 1.0, text: "hello world", isFinal: true, lag: nil, speaker: nil,
                                    start: 0.1, end: 1.0, engine: "parakeet", fallback: nil, words: words)
        l.record(upd)
        let encoded = try JSONEncoder().encode(l)
        let back = try JSONDecoder().decode(SessionLog.self, from: encoded)
        #expect(back.updates.count == 1)
        #expect(back.updates[0].words?.count == 2)
        #expect(back.updates[0].words?[0].text == "hello")
        #expect(back.updates[0].words?[0].start == 0.1)
        #expect(back.updates[0].words?[0].end == 0.5)
        #expect(back.updates[0].words?[1].text == "world")
        #expect(back.updates[0].words?[1].start == 0.6)
        #expect(back.updates[0].words?[1].end == 1.0)
    }

    @Test func seamFieldCanBePopulated() throws {
        var l = log()
        l.seams = [.init(windowStart: 0.0, audioEnd: 0.1), .init(windowStart: 0.1, audioEnd: 0.2)]
        #expect(l.seams?.count == 2)
        #expect(l.seams?[0].windowStart == 0.0)
        #expect(l.seams?[0].audioEnd == 0.1)
        #expect(l.seams?[1].windowStart == 0.1)
        #expect(l.seams?[1].audioEnd == 0.2)
    }

    @Test func seamFieldRoundTripsJSON() throws {
        var l = log()
        l.seams = [.init(windowStart: 0.5, audioEnd: 1.0), .init(windowStart: 1.0, audioEnd: 1.5)]
        let encoded = try JSONEncoder().encode(l)
        let back = try JSONDecoder().decode(SessionLog.self, from: encoded)
        #expect(back.seams?.count == 2)
        #expect(back.seams?[0].windowStart == 0.5)
        #expect(back.seams?[0].audioEnd == 1.0)
    }

    @Test func olderSessionLogWithoutSeamsCanBeDecoded() throws {
        // Create a full session log, encode it, remove seams field, then decode
        var l = log()
        l.seams = [.init(windowStart: 0.0, audioEnd: 0.5)]
        let encoded = try JSONEncoder().encode(l)
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json.removeValue(forKey: "seams")  // Remove the seams field to simulate old log
        let oldData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(SessionLog.self, from: oldData)
        #expect(decoded.seams == nil)  // Field is missing, so it decodes as nil
    }

    @Test func lineFieldPreservesStartAndEnd() throws {
        let line = SessionLog.Line(text: "hello", speaker: 0, soundLabel: nil, start: 1.5, end: 2.3)
        #expect(line.text == "hello")
        #expect(line.speaker == 0)
        #expect(line.start == 1.5)
        #expect(line.end == 2.3)
    }

    @Test func lineWithStartAndEndRoundTripsJSON() throws {
        var l = log()
        l.lines = [
            .init(text: "hello", speaker: 0, soundLabel: nil, start: 0.5, end: 1.2),
            .init(text: "world", speaker: 1, soundLabel: nil, start: 1.3, end: 2.0)
        ]
        let encoded = try JSONEncoder().encode(l)
        let back = try JSONDecoder().decode(SessionLog.self, from: encoded)
        #expect(back.lines.count == 2)
        #expect(back.lines[0].text == "hello")
        #expect(back.lines[0].start == 0.5)
        #expect(back.lines[0].end == 1.2)
        #expect(back.lines[1].text == "world")
        #expect(back.lines[1].start == 1.3)
        #expect(back.lines[1].end == 2.0)
    }
}

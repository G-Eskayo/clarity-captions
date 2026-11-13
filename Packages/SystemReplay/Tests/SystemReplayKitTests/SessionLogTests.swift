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

    @Test func decodeWindowsDefaultsToEmpty() throws {
        let l = log()
        #expect(l.decodeWindows == [])
    }

    @Test func decodeWindowsRoundTripsNonEmpty() throws {
        var l = log()
        l.decodeWindows = [1.0, 2.5, 4.0]
        let back = try JSONDecoder().decode(SessionLog.self, from: JSONEncoder().encode(l))
        #expect(back.decodeWindows == [1.0, 2.5, 4.0])
    }

    @Test func decodeWindowsRoundTripsEmpty() throws {
        var l = log()
        l.decodeWindows = []
        let back = try JSONDecoder().decode(SessionLog.self, from: JSONEncoder().encode(l))
        #expect(back.decodeWindows == [])
    }
}

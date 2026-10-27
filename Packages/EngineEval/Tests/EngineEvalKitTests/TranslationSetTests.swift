import Foundation
import Testing
@testable import EngineEvalKit

// #159: translation test sets reuse the #145 result store and run plan.
struct TranslationSetTests {
    func write(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("set-\(UUID().uuidString).jsonl")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func loadsSegmentsAsClipsWithSetNameAsAccent() throws {
        let url = try write("""
        {"id": "flores-0000", "set": "flores", "group": "u", "source": "Hello.", "reference": "Hola."}

        {"id": "edacc-a", "set": "edacc-lines", "group": "S1", "source": "i think so", "reference": null}
        """)
        let segs = try TranslationSet.load(url)
        #expect(segs.map(\.id) == ["flores-0000", "edacc-a"])
        #expect(segs[1].source == "i think so")
        let clips = segs.map(\.asClip)
        #expect(clips[0].accent == "flores" && clips[0].audioSeconds == 0)
        let pending = RunPlan.pending(clips: clips, engine: "apple", model: "m", repeats: 2, done: [
            ResultKey(clipID: "flores-0000", engine: "apple", model: "m", repeat: 1)])
        #expect(pending.map(\.clip.clipID) == ["edacc-a", "flores-0000", "edacc-a"])
    }

    @Test func rejectsALineWithoutSource() throws {
        let url = try write(#"{"id": "x", "set": "s", "group": "g"}"#)
        #expect(throws: (any Error).self) { try TranslationSet.load(url) }
    }
}

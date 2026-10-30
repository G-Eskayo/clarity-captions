import XCTest
@testable import CaptionCore

/// The Hebrew engine's search and word assembly (#220), with a fake network; the real model runs in
/// ZipformerIntegrationTests (opt-in).
final class ZipformerDecoderTests: XCTestCase {
    /// An encoder that writes a scripted token into frame t of chunk c; the joiner reads it back.
    final class FakeNetwork: ZipformerNetwork {
        let dim = 2
        var script: [Int: [Int: Int]]
        var windows: [Int] = []
        var contexts: [[Int32]] = []
        init(_ script: [Int: [Int: Int]]) { self.script = script }
        func encode(_ frames: [Float]) throws -> [Float] {
            windows.append(frames.count)
            var out = [Float](repeating: 0, count: ZipformerStream.outFrames * dim)
            for (t, k) in script[windows.count - 1] ?? [:] { out[t * dim] = Float(k) }
            return out
        }
        func decode(_ context: [Int32]) throws -> [Float] { contexts.append(context); return [0, 0] }
        func join(_ e: ArraySlice<Float>, _ d: [Float]) throws -> [Float] {
            var l = [Float](repeating: 0, count: 10)
            l[Int(e[e.startIndex])] = 1
            return l
        }
    }

    private func frames(_ n: Int) -> [[Float]] { Array(repeating: [Float](repeating: 0, count: 80), count: n) }

    func testWindowsOf141FramesStep128AndTokensCarryTheirEncoderFrame() throws {
        let net = FakeNetwork([0: [3: 5], 1: [0: 7, 31: 5]])
        var s = ZipformerStream()
        XCTAssertTrue(try s.accept(frames(140), network: net).isEmpty, "no window yet")
        let a = try s.accept(frames(1), network: net)
        XCTAssertEqual(a.map(\.token), [5]); XCTAssertEqual(a.map(\.frame), [3])
        let b = try s.accept(frames(128), network: net)
        XCTAssertEqual(b.map(\.token), [7, 5]); XCTAssertEqual(b.map(\.frame), [32, 63])
        XCTAssertEqual(net.windows, [141 * 80, 141 * 80])
        XCTAssertEqual(net.contexts, [[-1, 0], [0, 5], [5, 7], [7, 5]], "the context shifts by one per token")
        XCTAssertEqual(s.decodedSeconds, 64 * 0.04, accuracy: 1e-9)
    }

    func testAWrongSizedEncoderOutputIsAnErrorNotAGuess() {
        final class Short: ZipformerNetwork {
            let dim = 2
            func encode(_ f: [Float]) throws -> [Float] { [0] }
            func decode(_ c: [Int32]) throws -> [Float] { [0, 0] }
            func join(_ e: ArraySlice<Float>, _ d: [Float]) throws -> [Float] { [1] }
        }
        var s = ZipformerStream()
        XCTAssertThrowsError(try s.accept(frames(141), network: Short()))
    }

    private let table = ZipformerWords.table(from: "<blk> 0\n▁של 1\nום 2\n▁מה 3\n▁ 4\nנש 5\nמע 6\n<unk> 7\n")

    func testPiecesJoinIntoWordsAndAWordIsFinalOnceTheNextStarts() {
        var w = ZipformerWords(table: table)
        var r = w.add([(1, 0), (2, 1)], decodedSeconds: 0.5)
        XCTAssertEqual(r.final, [])
        XCTAssertEqual(r.volatile, [TimedWord(text: "שלום", start: 0, end: 0.08)])
        r = w.add([(3, 10), (4, 11), (5, 12), (6, 13), (7, 14)], decodedSeconds: 0.6)
        XCTAssertEqual(r.final.map(\.text), ["שלום", "מה"])
        XCTAssertEqual(r.volatile.map(\.text), ["נשמע"], "a bare ▁ starts a word; <unk> is dropped")
        XCTAssertEqual(r.volatile.first?.start ?? 0, 0.44, accuracy: 1e-9)
    }

    func testAPauseSettlesTheLastWord() {
        var w = ZipformerWords(table: table)
        _ = w.add([(1, 0)], decodedSeconds: 0.5)
        let r = w.add([], decodedSeconds: 0.04 + 0.8)
        XCTAssertEqual(r.final.map(\.text), ["של"])
        XCTAssertEqual(r.volatile, [])
        XCTAssertEqual(w.flush(), [])
    }

    func testFlushFinalisesTheOpenWord() {
        var w = ZipformerWords(table: table)
        _ = w.add([(3, 0)], decodedSeconds: 0.1)
        XCTAssertEqual(w.flush().map(\.text), ["מה"])
    }

    func testTokensTableReadsSherpaFormatIncludingAPieceThatIsJustTheMarker() {
        XCTAssertEqual(table[4], "▁")
        XCTAssertEqual(table[1], "▁של")
        XCTAssertEqual(table.count, 8)
    }
}

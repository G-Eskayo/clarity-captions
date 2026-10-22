import XCTest
@testable import EngineEvalKit

/// Streaming-latency building blocks (#145): the simulated growing-window clock, the live display text, word timing.
final class LatencyKitTests: XCTestCase {
    func testGrowingWindowHopBoundWhenDecodeIsFast() async throws {
        var asked: [Double] = []
        let ups = try await GrowingWindow.simulate(duration: 1.2, hop: 0.5) { a in
            asked.append(a); return ("t\(a)", 0.1)
        }
        XCTAssertEqual(asked, [0.5, 1.0, 1.2])
        XCTAssertEqual(ups.map(\.t), [0.6, 1.1, 1.3].map { $0 }, accuracy: 1e-9)
        XCTAssertEqual(ups.last?.text, "t1.2")
    }

    func testGrowingWindowComputeBoundWhenDecodeIsSlow() async throws {
        var asked: [Double] = []
        let ups = try await GrowingWindow.simulate(duration: 3.0, hop: 0.5) { a in asked.append(a); return ("x", 1.0) }
        // decode at 0.5 ends 1.5 -> next decode uses audio up to 1.5, ends 2.5 -> uses 2.5, ends 3.5 -> final 3.0
        XCTAssertEqual(asked, [0.5, 1.5, 2.5, 3.0])
        XCTAssertEqual(ups.map(\.t), [1.5, 2.5, 3.5, 4.5], accuracy: 1e-9)
    }

    func testClipShorterThanHopDecodesOnceAtEnd() async throws {
        var asked: [Double] = []
        let ups = try await GrowingWindow.simulate(duration: 0.3, hop: 0.5) { a in asked.append(a); return ("y", 0.05) }
        XCTAssertEqual(asked, [0.3])
        XCTAssertEqual(ups.count, 1)
    }

    func testGrowingWindowAlwaysEndsWithFullAudio() async throws {
        for d in [0.01, 0.5, 0.99, 7.3, 29.9] {
            var asked: [Double] = []
            _ = try await GrowingWindow.simulate(duration: d, hop: 0.5) { a in asked.append(a); return ("", 0.2) }
            XCTAssertEqual(asked.last ?? -1, d, accuracy: 1e-12)
            XCTAssertEqual(asked, asked.sorted())
        }
    }

    func testDisplayedTextFinalsAccumulateVolatileReplaces() {
        var d = DisplayedText()
        XCTAssertEqual(d.apply("hel", isFinal: false), "hel")
        XCTAssertEqual(d.apply("hello", isFinal: false), "hello")
        XCTAssertEqual(d.apply("Hello there.", isFinal: true), "Hello there.")
        XCTAssertEqual(d.apply("how", isFinal: false), "Hello there. how")
        XCTAssertEqual(d.apply("", isFinal: false), "Hello there.")
        XCTAssertEqual(d.apply("How are you?", isFinal: true), "Hello there. How are you?")
    }

    func testWordTimingGroupsSubwordTokens() {
        let words = WordTiming.group([("▁hel", 0.0, 0.2), ("lo", 0.2, 0.4), ("▁there", 0.5, 0.9), (",", 0.9, 0.95)])
        XCTAssertEqual(words.map(\.word), ["hello", "there,"])
        XCTAssertEqual(words[0].start, 0.0); XCTAssertEqual(words[0].end, 0.4)
        XCTAssertEqual(words[1].end, 0.95)
    }

    func testWordTimingSpaceMarkersAndEmpty() {
        XCTAssertTrue(WordTiming.group([]).isEmpty)
        let w = WordTiming.group([(" yes", 1, 2), (" no", 2, 3)])
        XCTAssertEqual(w.map(\.word), ["yes", "no"])
        let first = WordTiming.group([("ok", 0, 1), ("ay", 1, 2)])  // no marker on the first token
        XCTAssertEqual(first.map(\.word), ["okay"])
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}

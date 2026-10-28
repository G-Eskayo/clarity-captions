import XCTest
@testable import CaptionCore

/// The committed tail-window decoder's pure part (design §2, test 1). Times in the decode are relative to the window
/// start; everything the committer returns is absolute.
final class TailCommitterTests: XCTestCase {
    private func w(_ text: String, _ start: Double, _ end: Double) -> TimedWord { TimedWord(text: text, start: start, end: end) }
    private func texts(_ words: [TimedWord]) -> [String] { words.map(\.text) }

    func testFirstDecodeCommitsNothingAndShowsEverythingAsVolatile() {
        var c = TailCommitter()
        let out = c.ingest(decode: [w("hello", 0.1, 0.4), w("there", 0.5, 0.8)], windowStart: 0, audioEnd: 3.0)
        XCTAssertEqual(out.final, [])
        XCTAssertEqual(texts(out.volatile), ["hello", "there"])
    }

    func testTwoAgreeingDecodesCommitTheStablePrefix() {
        var c = TailCommitter()
        _ = c.ingest(decode: [w("hello", 0.1, 0.4), w("there", 0.5, 0.8)], windowStart: 0, audioEnd: 2.0)
        let out = c.ingest(decode: [w("hello", 0.1, 0.4), w("there", 0.5, 0.8), w("friend", 2.0, 2.3)], windowStart: 0, audioEnd: 2.5)
        XCTAssertEqual(texts(out.final), ["hello", "there"])
        XCTAssertEqual(texts(out.volatile), ["friend"])
        XCTAssertEqual(c.commitPoint, 0.8, accuracy: 1e-9)
    }

    func testDisagreementInTheMiddleStopsTheCommitThere() {
        var c = TailCommitter()
        _ = c.ingest(decode: [w("a", 0.0, 0.2), w("big", 0.3, 0.5), w("dog", 0.6, 0.8)], windowStart: 0, audioEnd: 3)
        let out = c.ingest(decode: [w("a", 0.0, 0.2), w("bag", 0.3, 0.5), w("dog", 0.6, 0.8)], windowStart: 0, audioEnd: 3.5)
        XCTAssertEqual(texts(out.final), ["a"], "commit stops at the first disagreement, even if later words agree")
        XCTAssertEqual(texts(out.volatile), ["bag", "dog"])
    }

    func testWordsInsideTheStabilityMarginNeverCommit() {
        var c = TailCommitter()
        _ = c.ingest(decode: [w("one", 0.0, 0.3), w("two", 1.5, 1.8)], windowStart: 0, audioEnd: 2.0)
        let out = c.ingest(decode: [w("one", 0.0, 0.3), w("two", 1.5, 1.8)], windowStart: 0, audioEnd: 2.2)
        // two ends 0.4 s before the newest audio: inside the 0.6 s margin.
        XCTAssertEqual(texts(out.final), ["one"])
        XCTAssertEqual(texts(out.volatile), ["two"])
    }

    func testWindowOffsetIsAppliedOnceAndOutputIsAbsolute() {
        var c = TailCommitter()
        _ = c.ingest(decode: [w("x", 0.2, 0.5)], windowStart: 10, audioEnd: 12)
        let out = c.ingest(decode: [w("x", 0.2, 0.5)], windowStart: 10, audioEnd: 12.5)
        XCTAssertEqual(out.final, [w("x", 10.2, 10.5)])
        XCTAssertEqual(c.commitPoint, 10.5, accuracy: 1e-9)
    }

    func testContextWordsBeforeTheCommitPointAreDroppedAndNeverReEmitted() {
        var c = TailCommitter()
        _ = c.ingest(decode: [w("good", 0.0, 0.3), w("morning", 0.4, 0.8)], windowStart: 0, audioEnd: 2)
        _ = c.ingest(decode: [w("good", 0.0, 0.3), w("morning", 0.4, 0.8)], windowStart: 0, audioEnd: 2.5)
        // Next window starts 1 s of context before the commit point; the decoder re-reads "morning" with jitter.
        let out = c.ingest(decode: [w("morning", 0.0, 0.85), w("all", 1.6, 1.9)], windowStart: -0.2 + 0.4, audioEnd: 3.0)
        XCTAssertFalse(texts(out.final).contains("morning"))
        XCTAssertFalse(texts(out.volatile).contains("morning"))
        XCTAssertEqual(texts(out.volatile), ["all"])
    }

    func testARepeatedWordAcrossTheCommitPointIsNeitherDoubledNorSwallowed() {
        var c = TailCommitter()
        let d1 = [w("the", 0.0, 0.2), w("the", 0.25, 0.45), w("end", 0.5, 0.8)]
        _ = c.ingest(decode: [w("the", 0.0, 0.2)], windowStart: 0, audioEnd: 1.0)
        let first = c.ingest(decode: [w("the", 0.0, 0.2)], windowStart: 0, audioEnd: 1.0)
        XCTAssertEqual(texts(first.final), ["the"])
        _ = c.ingest(decode: d1, windowStart: 0, audioEnd: 2.0)
        let out = c.ingest(decode: d1, windowStart: 0, audioEnd: 2.5)
        XCTAssertEqual(texts(out.final), ["the", "end"], "the second 'the' is a new word, the first is not repeated")
    }

    func testAnEmptyDecodeCommitsNothingAndForgetsTheLastDecode() {
        var c = TailCommitter()
        _ = c.ingest(decode: [w("hi", 0.0, 0.3)], windowStart: 0, audioEnd: 1.0)
        let empty = c.ingest(decode: [], windowStart: 0, audioEnd: 1.5)
        XCTAssertEqual(empty.final, [])
        XCTAssertEqual(empty.volatile, [])
        let out = c.ingest(decode: [w("hi", 0.0, 0.3)], windowStart: 0, audioEnd: 2.0)
        XCTAssertEqual(out.final, [], "agreement needs two consecutive decodes, the empty one broke the run")
    }

    func testSilenceMovesTheCommitPointSoTheWindowStaysBounded() {
        var c = TailCommitter()
        _ = c.ingest(decode: [], windowStart: 0, audioEnd: 30)
        XCTAssertEqual(c.commitPoint, 28, accuracy: 1e-9, "silence before now - 2 s is committed as nothing")
        XCTAssertLessThanOrEqual(30 - c.commitPoint, TailCommitter.Config().maxUncommitted)
    }

    func testForceCommitAtTwelveSecondsUncommitted() {
        var c = TailCommitter()
        // Decoder flips the same word every time, so nothing ever agrees.
        var words: [TimedWord] = []
        for i in 0..<24 { words.append(w("w\(i)", Double(i) * 0.5, Double(i) * 0.5 + 0.3)) }
        let first = c.ingest(decode: words.map { w($0.text + "a", $0.start, $0.end) }, windowStart: 0, audioEnd: 11.9)
        XCTAssertEqual(first.final, [], "11.9 s uncommitted is still under the limit")
        let out = c.ingest(decode: words, windowStart: 0, audioEnd: 12.0)
        XCTAssertEqual(out.final.first?.text, "w0")
        XCTAssertTrue(out.final.allSatisfy { $0.end <= 10.0 }, "force commit keeps the last 2 s open")
        XCTAssertTrue(out.volatile.allSatisfy { $0.end > 10.0 })
        XCTAssertLessThanOrEqual(12.0 - c.commitPoint, TailCommitter.Config().maxUncommitted)
    }

    func testAShortWordReDecodedWithLaterTimingIsNotCommittedTwice() {
        var c = TailCommitter()
        _ = c.ingest(decode: [w("ok", 1.0, 1.1)], windowStart: 0, audioEnd: 3)
        _ = c.ingest(decode: [w("ok", 1.0, 1.1), w("so", 2.6, 2.8)], windowStart: 0, audioEnd: 3.5)
        // Re-decoded 60 ms later: its centre now lands after the commit point.
        let out = c.ingest(decode: [w("ok", 1.06, 1.16), w("so", 2.6, 2.8)], windowStart: 0, audioEnd: 4)
        XCTAssertFalse(texts(out.final + out.volatile).contains("ok"))
    }

    func testACommittedWordReDecodedWellAfterItsTimeIsNotRepeated() {
        // Seen on the real model: "jumps over the | the lazy". The re-decoded "the" moved past the commit point.
        var c = TailCommitter()
        let first = [w("jumps", 0.0, 0.3), w("over", 0.35, 0.6), w("the", 0.65, 0.75)]
        _ = c.ingest(decode: first, windowStart: 0, audioEnd: 2)
        XCTAssertEqual(texts(c.ingest(decode: first, windowStart: 0, audioEnd: 2.5).final), ["jumps", "over", "the"])
        let shifted = [w("jumps", 0.05, 0.35), w("over", 0.4, 0.7), w("the", 0.78, 0.9), w("lazy", 1.0, 1.3)]
        let out = c.ingest(decode: shifted, windowStart: 0, audioEnd: 3)
        XCTAssertEqual(texts(out.volatile), ["lazy"])
    }

    func testPunctuationChangesDoNotBreakTheAlignment() {
        var c = TailCommitter()
        _ = c.ingest(decode: [w("dog", 0.0, 0.3)], windowStart: 0, audioEnd: 2)
        _ = c.ingest(decode: [w("dog", 0.0, 0.3)], windowStart: 0, audioEnd: 2.5)
        let out = c.ingest(decode: [w("dog,", 0.2, 0.45), w("she", 0.6, 0.8)], windowStart: 0, audioEnd: 3)
        XCTAssertEqual(texts(out.volatile), ["she"])
    }

    func testFinishCommitsEverythingLeft() {
        var c = TailCommitter()
        _ = c.ingest(decode: [w("almost", 0.0, 0.4), w("done", 0.5, 0.8)], windowStart: 0, audioEnd: 1.0)
        let out = c.finish(decode: [w("almost", 0.0, 0.4), w("done", 0.5, 0.8), w("now", 0.85, 0.95)], windowStart: 0)
        XCTAssertEqual(texts(out), ["almost", "done", "now"])
        XCTAssertEqual(texts(c.finish(decode: [w("now", 0.85, 0.95)], windowStart: 0)), [], "a second finish adds nothing")
    }

    func testWindowStartKeepsLeftContextAndNeverGoesNegative() {
        var c = TailCommitter()
        XCTAssertEqual(c.windowStart(audioEnd: 0.5), 0)
        let open = [w("a", 3.0, 3.2), w("b", 4.9, 5.1)]
        _ = c.ingest(decode: open, windowStart: 0, audioEnd: 5)
        _ = c.ingest(decode: open, windowStart: 0, audioEnd: 5.5)
        XCTAssertEqual(c.windowStart(audioEnd: 5.5), 2.2, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(c.windowStart(audioEnd: 100), 100 - TailCommitter.Config().maxWindow,
                                    "never asks for more audio than the encoder takes")
    }

    // MARK: - Adversarial: 10,000 random sessions

    /// A random talker with pauses; each decode sees the fully heard words in its window, timing jitter on every word
    /// and a noisy, unstable tail (substituted or missing words) only inside the stability margin. Whatever happens,
    /// the finals must be exactly the true words, in order, with none doubled or skipped.
    func testRandomSessionsCommitExactlyTheTrueWordsInOrder() {
        var rng = SplitMix(seed: 0xC0FFEE)
        let margin = TailCommitter.Config().stabilityMargin
        for session in 0..<10_000 {
            var truth: [TimedWord] = []
            var t = rng.double(in: 0...1)
            for i in 0..<Int(rng.double(in: 1...40)) {
                let len = rng.double(in: 0.1...0.6)
                truth.append(w(i % 7 == 3 ? "the" : "w\(i)", t, t + len))
                t += len + (rng.double(in: 0...1) < 0.1 ? rng.double(in: 1.2...4) : rng.double(in: 0.02...0.3))
            }
            let total = t + 0.5
            var c = TailCommitter()
            var finals: [TimedWord] = []
            var audioEnd = 0.0
            func decode(at end: Double, noisy: Bool) -> (words: [TimedWord], start: Double) {
                let start = c.windowStart(audioEnd: end)
                var out: [TimedWord] = []
                for word in truth where word.start >= start && word.end <= end {
                    // Parakeet's token times move by a frame or two between windows: up to 0.12 s, more than half a short word.
                    let jitter = rng.double(in: -0.12...0.12)
                    var text = word.text
                    if noisy && word.end + jitter > end - margin {   // the end the committer sees
                        let r = rng.double(in: 0...1)
                        if r < 0.3 { continue }
                        if r < 0.6 { text = "noise\(Int(rng.double(in: 0...3)))" }
                    }
                    out.append(w(text, max(start, word.start + jitter) - start, word.end + jitter - start))
                }
                return (out, start)
            }
            while audioEnd < total {
                audioEnd += rng.double(in: 0.5...1.5)
                let d = decode(at: audioEnd, noisy: true)
                let out = c.ingest(decode: d.words, windowStart: d.start, audioEnd: audioEnd)
                XCTAssertTrue(out.final.allSatisfy { $0.end <= audioEnd }, "session \(session): committed unheard audio")
                finals += out.final
            }
            let d = decode(at: audioEnd, noisy: false)
            finals += c.finish(decode: d.words, windowStart: d.start)
            let got = texts(finals), want = texts(truth)
            if got != want {
                XCTFail("session \(session): finals \(got) != truth \(want)")
                return
            }
        }
    }
}

/// Deterministic generator so a failure reproduces.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}

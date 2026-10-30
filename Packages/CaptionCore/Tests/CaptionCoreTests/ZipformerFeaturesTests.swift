import XCTest
@testable import CaptionCore

/// The Hebrew engine's front end (#220): Kaldi fbank as the zipformer was trained on it. The fixture is torchaudio's
/// output for the same signal (scripts/engine-eval/zipformer_coreml/fbank_fixture.py), so Swift and the Python
/// scoring path see the same features.
final class ZipformerFeaturesTests: XCTestCase {
    private struct Fixture: Decodable { let samples: Int; let frames: [[Float]] }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "zipformer-fbank", withExtension: "json",
                                                  subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// The fixture's signal, made the same way as in fbank_fixture.py.
    private func signal(_ n: Int) -> [Float] {
        (0..<n).map { i in
            let t = Double(i)
            return Float(0.3 * sin(2 * .pi * 440 * t / 16000) + 0.2 * sin(2 * .pi * 1234.5 * t / 16000)
                         + 0.05 * (t / 8000) * sin(2 * .pi * 3000 * t / 16000))
        }
    }

    private func assertMatches(_ got: [[Float]], _ want: [[Float]], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.count, want.count, "frame count", file: file, line: line)
        var worst: Float = 0
        for (g, w) in zip(got, want) {
            XCTAssertEqual(g.count, 80, file: file, line: line)
            for (a, b) in zip(g, w) { worst = max(worst, abs(a - b)) }
        }
        // Log mel energies run from about -15 to 10; float32 FFT rounding stays far below a hundredth.
        XCTAssertLessThan(worst, 0.01, "largest difference from torchaudio", file: file, line: line)
    }

    func testOneBlockMatchesTorchaudiosKaldiFbank() throws {
        let fx = try fixture()
        var f = ZipformerFeatures()
        f.append(signal(fx.samples))
        // torchaudio (snip_edges false) also emits frames whose window runs past the end, reflecting the signal; a
        // live stream never knows its end, so it stops at the last whole window: the first frames must match.
        let got = f.takeFrames()
        XCTAssertEqual(got.count, (fx.samples - 280) / 160 + 1)
        assertMatches(got, Array(fx.frames.prefix(got.count)))
    }

    func testFeedingInOddPiecesGivesTheSameFrames() throws {
        let fx = try fixture()
        let x = signal(fx.samples)
        var whole = ZipformerFeatures()
        whole.append(x)
        let want = whole.takeFrames()
        var pieces = ZipformerFeatures()
        var got: [[Float]] = []
        var i = 0
        for size in [7, 100, 119, 121, 333, 1, 1600] where i < x.count {
            pieces.append(Array(x[i..<min(x.count, i + size)]))
            got += pieces.takeFrames()
            i += size
        }
        pieces.append(Array(x[i...]))
        got += pieces.takeFrames()
        XCTAssertEqual(got, want)
    }

    func testFramesAreNeverHandedOutTwiceAndBufferedAudioIsBounded() {
        var f = ZipformerFeatures()
        for _ in 0..<100 {
            f.append([Float](repeating: 0.01, count: 1600))
            _ = f.takeFrames()
        }
        XCTAssertLessThan(f.bufferedSamples, 400 + 160, "only the samples the next window needs are kept")
        XCTAssertEqual(f.takeFrames().count, 0)
    }

    func testSilenceGivesTheLogFloorNotMinusInfinity() {
        var f = ZipformerFeatures()
        f.append([Float](repeating: 0, count: 1600))
        let frames = f.takeFrames()
        XCTAssertFalse(frames.isEmpty)
        XCTAssertTrue(frames.allSatisfy { $0.allSatisfy { $0.isFinite } })
    }
}

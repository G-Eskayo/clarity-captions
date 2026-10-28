import XCTest
@testable import CaptionCore

/// Room and call together (#172): two sources' samples, already in one format, summed into one stream for one engine.
/// The engine must get every moment exactly once, in order, and a source that goes quiet (no permission, unplugged
/// mic, no call yet) must not hold the other one up.
final class AudioMixerTests: XCTestCase {
    private func mixer(maxLag: Int = 4) -> AudioMixer { AudioMixer(inputs: 2, maxLagFrames: maxLag) }

    func testSamplesFromBothInputsAreAddedTogether() {
        var m = mixer()
        XCTAssertEqual(m.push([0.1, 0.2, 0.3], into: 0), [])
        XCTAssertEqual(m.push([0.5, 0.5, 0.5], into: 1), [0.6, 0.7, 0.8].map(Float.init))
    }

    func testOnlyTheOverlapIsEmittedAndTheRestWaits() {
        var m = mixer(maxLag: 100)
        _ = m.push([0.25, 0.25, 0.25, 0.25, 0.25], into: 0)
        XCTAssertEqual(m.push([0.5, 0.5], into: 1), [0.75, 0.75])
        XCTAssertEqual(m.push([0.5, 0.5, 0.5], into: 1), [0.75, 0.75, 0.75])
        XCTAssertEqual(m.push([0.5], into: 1), [], "input 0 is used up: wait for it")
    }

    func testAQuietInputIsPaddedWithSilenceOnceTheOtherIsTooFarAhead() {
        var m = mixer(maxLag: 4)
        XCTAssertEqual(m.push([1, 1, 1], into: 0), [], "within the lag allowance: wait")
        XCTAssertEqual(m.push([1, 1], into: 0), [1, 1, 1, 1, 1], "past the allowance: emit, the quiet input counts as silence")
    }

    func testALateInputDoesNotReplayTimeAlreadyPaddedOver() {
        var m = mixer(maxLag: 2)
        XCTAssertEqual(m.push([0.25, 0.25, 0.25], into: 0), [0.25, 0.25, 0.25])
        // Input 1 wakes up: its first samples belong to "now", not to the 3 frames already sent as silence.
        XCTAssertEqual(m.push([0.5, 0.5], into: 1), [])
        XCTAssertEqual(m.push([0.25, 0.25], into: 0), [0.75, 0.75])
    }

    func testNothingIsLostOrRepeatedOverManyUnevenPushes() {
        var m = mixer(maxLag: 64)
        var out: [Float] = []
        var total = 0
        let sizes = [7, 13, 1, 29, 5, 64, 3, 17]
        // Two clocks that never drift more than one push apart, arriving in alternating order.
        for i in 0..<200 {
            let n = sizes[i % sizes.count], first = i % 2
            out += m.push([Float](repeating: 0.25, count: n), into: first)
            out += m.push([Float](repeating: 0.25, count: n), into: 1 - first)
            total += n
        }
        XCTAssertEqual(out.count, total, "every frame both inputs delivered is emitted once")
        XCTAssertTrue(out.allSatisfy { $0 == 0.5 }, "no frame was mixed with silence or with itself")
    }

    func testAnInputOutOfRangeIsIgnored() {
        var m = mixer()
        XCTAssertEqual(m.push([1, 1], into: 7), [])
        XCTAssertEqual(m.push([1, 1], into: -1), [])
    }

    func testTheSumIsKeptInRange() {
        var m = mixer()
        _ = m.push([0.9, -0.9], into: 0)
        XCTAssertEqual(m.push([0.9, -0.9], into: 1), [1, -1], "clipped, not wrapped")
    }
}

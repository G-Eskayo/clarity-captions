import XCTest
@testable import CaptionCore

final class AudioLevelTests: XCTestCase {
    func testSilenceClamps() {
        let silentSamples = Array(repeating: Float(0), count: 100)
        let level = AudioLevel.rmsDBFS(silentSamples)
        XCTAssertEqual(level, -60, accuracy: 0.01)
    }

    func testVeryQuietSoundClamps() {
        let quietSamples = Array(repeating: Float(0.00001), count: 100)
        let level = AudioLevel.rmsDBFS(quietSamples)
        XCTAssertLessThanOrEqual(level, -60)
    }

    func testEmptySampleArrayClamps() {
        let level = AudioLevel.rmsDBFS([])
        XCTAssertEqual(level, -60, accuracy: 0.01)
    }

    func testFullScaleSignal() {
        let fullScale = Array(repeating: Float(1.0), count: 100)
        let level = AudioLevel.rmsDBFS(fullScale)
        XCTAssertEqual(level, 0, accuracy: 0.1)
    }

    func testHalfAmplitudeSignal() {
        let halfScale = Array(repeating: Float(0.5), count: 100)
        let level = AudioLevel.rmsDBFS(halfScale)
        XCTAssertEqual(level, -6, accuracy: 0.1)
    }
}

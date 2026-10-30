import AVFoundation
import XCTest
@testable import CaptionCore

/// A sound file as the engine's audio source (#220 screenshots: debug builds replay real Hebrew speech through the
/// whole app in the simulator, which has no useful microphone).
final class FileAudioSourceTests: XCTestCase {
    private func file(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fas-\(UUID()).wav")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let f = try AVAudioFile(forWriting: url, settings: format.settings)
        let n = AVAudioFrameCount(seconds * 16_000)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        for i in 0..<Int(n) { buf.floatChannelData![0][i] = Float(i % 100) / 100 }
        try f.write(from: buf)
        return url
    }

    func testEverySampleArrivesInOrderAtAboutRealTime() throws {
        let src = FileAudioSource(url: try file(seconds: 0.5), speed: 1)
        let format = try src.open()
        XCTAssertEqual(format.sampleRate, 16_000)
        let done = expectation(description: "all audio")
        let lock = NSLock()
        var got: [Float] = []
        let began = Date()
        try src.start { b in
            lock.withLock { got += Array(UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength))) }
            if lock.withLock({ got.count }) >= 8_000 { done.fulfill() }
        }
        wait(for: [done], timeout: 5)
        src.stop()
        XCTAssertEqual(got.count, 8_000)
        XCTAssertEqual(got[0..<200], (0..<200).map { Float($0 % 100) / 100 }[...])
        XCTAssertGreaterThan(Date().timeIntervalSince(began), 0.3, "paced, not dumped at once")
    }

    func testStopEndsDeliveryAndIsSafeTwice() throws {
        let src = FileAudioSource(url: try file(seconds: 3), speed: 1)
        _ = try src.open()
        let lock = NSLock()
        var count = 0
        try src.start { _ in lock.withLock { count += 1 } }
        Thread.sleep(forTimeInterval: 0.3)
        src.stop(); src.stop()
        let after = lock.withLock { count }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(lock.withLock { count }, after)
    }

    func testAMissingFileFailsAtOpen() {
        XCTAssertThrowsError(try FileAudioSource(url: URL(fileURLWithPath: "/nope.wav")).open())
    }
}

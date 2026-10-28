import AVFoundation
import XCTest
@testable import CaptionCore

/// The engine's per-buffer work assumes one buffer at a time, as a single mic tap delivers them. Room and call
/// together (#172) are two sources, each calling back on its own thread, so the mixed source must hand the engine
/// one buffer at a time too, and never two at once.
final class MixedAudioSourceThreadingTests: XCTestCase {
    func testTwoSourcesOnTwoThreadsNeverDeliverAtTheSameTime() throws {
        let a = ThreadedSource(), b = ThreadedSource()
        let mixed = MixedAudioSource([a, b], maxLagSeconds: 0.001)   // one source running ahead: both threads emit
        _ = try mixed.open()
        let inside = ManagedAtomicFlag()
        var overlaps = 0, delivered = 0
        let counts = NSLock()
        try mixed.start { _ in
            if inside.enter() == false { counts.withLock { overlaps += 1 } }
            Thread.sleep(forTimeInterval: 0.002)   // engine work: widen the window two callers could share
            inside.leave()
            counts.withLock { delivered += 1 }
        }
        let group = DispatchGroup()
        for source in [a, b] {
            DispatchQueue.global().async(group: group) { for _ in 0..<200 { source.emit(frames: 480) } }
        }
        group.wait()
        mixed.stop()
        XCTAssertGreaterThan(delivered, 10, "too few deliveries to prove anything: \(delivered)")
        XCTAssertEqual(overlaps, 0, "the engine was handed two buffers at once")
    }
}

private final class ManagedAtomicFlag {
    private let lock = NSLock()
    private var busy = false
    /// Returns false when someone was already inside.
    func enter() -> Bool { lock.withLock { defer { busy = true }; return !busy } }
    func leave() { lock.withLock { busy = false } }
}

/// A source whose buffers arrive on whatever thread calls `emit`.
private final class ThreadedSource: AudioSource {
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    func open() throws -> AVAudioFormat { format }
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws { self.onBuffer = onBuffer }
    func stop() { onBuffer = nil }
    func emit(frames: AVAudioFrameCount) {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = 0.1 }
        onBuffer?(buffer)
    }
}

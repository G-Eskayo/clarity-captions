#if os(macOS)
import AVFoundation
import XCTest
@testable import CaptionCore

/// Owner, 2026-10-28 ~21:00 UTC: a Bluetooth headset's mic is opened once and kept open, even while it gives only
/// silence. Closing and reopening it every 2.5 s switches the headset in and out of call mode, and around an iPhone call
/// can hand it to the phone, so the person stops hearing the call. Other inputs keep their silence restarts (the Mac's
/// own mic right after AirPods disconnect really does come back on a restart).
final class RoomMicSilenceTests: XCTestCase {
    /// A mic that only ever gives exact digital silence, counting how often it is opened and closed.
    private final class SilentMic: AudioSource {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        private let lock = NSLock()
        private var _starts = 0, _stops = 0
        var starts: Int { lock.withLock { _starts } }
        var stops: Int { lock.withLock { _stops } }

        func open() throws -> AVAudioFormat { format }
        func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
            lock.withLock { _starts += 1 }
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
            buffer.frameLength = 480   // zero-filled
            onBuffer(buffer)
        }
        func stop() { lock.withLock { _stops += 1 } }
    }

    private final class Mics {
        private let lock = NSLock()
        private var made: [SilentMic] = []
        var all: [SilentMic] { lock.withLock { made } }
        func make() -> AudioSource { let mic = SilentMic(); lock.withLock { made.append(mic) }; return mic }
    }

    /// The mics made, and how often each had been stopped while captions were still running.
    private func run(_ choice: RoomMicChoice, transport: AudioDeviceInfo.Transport, for seconds: TimeInterval) -> (mics: [SilentMic], stopsWhileRunning: [Int]) {
        let mics = Mics()
        let source = RoomMicSource(route: { (choice, 42) }, transportOf: { _ in transport },
                                   makeMic: { _ in mics.make() }, silenceCheckDelay: 0.05)
        XCTAssertNoThrow(try source.start { _ in })
        Thread.sleep(forTimeInterval: seconds)
        let made = mics.all
        let stopsWhileRunning = made.map(\.stops)
        source.stop()
        XCTAssertEqual(made.last?.stops, 1, "stopping captions closes the mic")
        return (made, stopsWhileRunning)
    }

    func testABluetoothHeadsetGivingSilenceIsNotClosedAndReopened() {
        let (mics, stops) = run(.headset, transport: .bluetooth, for: 0.6)   // a dozen silence checks' worth
        XCTAssertEqual(mics.count, 1, "the headset's mic is opened once")
        XCTAssertEqual(mics.first?.starts, 1)
        XCTAssertEqual(stops, [0], "and never closed while captions run")
    }

    func testBluetoothAsTheRoomsInputIsKeptOpenToo() {
        // The speakers out, the AirPods' mic still the input (the 14:43 log): still a Bluetooth mic, still kept.
        let (mics, stops) = run(.room, transport: .bluetooth, for: 0.6)
        XCTAssertEqual(mics.count, 1)
        XCTAssertEqual(stops, [0])
    }

    func testTheMacsOwnMicGivingSilenceIsStillRestarted() {
        let (mics, _) = run(.room, transport: .builtIn, for: 0.6)
        XCTAssertGreaterThan(mics.count, 1, "the built-in mic gets its restarts, as before")
        XCTAssertLessThanOrEqual(mics.count, 6, "and still gives up after a few")
    }
}
#endif

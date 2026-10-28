#if os(macOS)
import AudioToolbox
import AVFoundation

/// A headset's microphone on the Mac (#172: AirPods Max). Built on an AudioQueue, not AVAudioEngine: with AirPods as
/// the input, AVAudioEngine delivered only zeros (measured on the owner's AirPods Max, 2026-10-28, and in marvin-voice
/// 2026-10-27), while an AudioQueue follows the headphones into headset mode and asks macOS for 16 kHz mono itself.
public final class HeadsetMicAudioSource: AudioSource {
    public static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private static let bufferFrames: UInt32 = 1_600   // 0.1 s; three in flight

    /// The Core Audio UID of the device to record from; nil means the Mac's default input.
    private let deviceUID: String?
    private var queue: AudioQueueRef?

    public init(deviceUID: String? = nil) {
        self.deviceUID = deviceUID
    }

    public func open() throws -> AVAudioFormat { Self.format }

    public func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard queue == nil else { return }
        var asbd = Self.format.streamDescription.pointee
        var newQueue: AudioQueueRef?
        let status = AudioQueueNewInputWithDispatchQueue(&newQueue, &asbd, 0, DispatchQueue(label: "captions.headset-mic")) { queue, buffer, _, packets, _ in
            if packets > 0, let pcm = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: packets), let ch = pcm.floatChannelData {
                pcm.frameLength = packets
                memcpy(ch[0], buffer.pointee.mAudioData, Int(packets) * MemoryLayout<Float>.size)
                onBuffer(pcm)
            }
            AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        }
        guard status == noErr, let newQueue else { throw CallAudioError.coreAudio(step: "headset mic queue", status: status) }
        if let deviceUID {
            var uid = deviceUID as CFString
            AudioQueueSetProperty(newQueue, kAudioQueueProperty_CurrentDevice, &uid, UInt32(MemoryLayout<CFString>.size))
        }
        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?
            AudioQueueAllocateBuffer(newQueue, Self.bufferFrames * UInt32(MemoryLayout<Float>.size), &buffer)
            if let buffer { AudioQueueEnqueueBuffer(newQueue, buffer, 0, nil) }
        }
        let started = AudioQueueStart(newQueue, nil)
        guard started == noErr else {
            AudioQueueDispose(newQueue, true)
            throw CallAudioError.coreAudio(step: "headset mic start", status: started)
        }
        queue = newQueue
    }

    public func stop() {
        guard let queue else { return }
        AudioQueueStop(queue, true)
        AudioQueueDispose(queue, true)
        self.queue = nil
    }
}
#endif

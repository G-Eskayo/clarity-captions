import AVFoundation

/// A sound file as the engine's audio source, delivered at real-time pace in 100 ms buffers (#220). Debug builds use
/// it to replay real speech through the whole app in the simulator, whose microphone hears nothing useful; it is the
/// same path as the microphone from the converter on. Ends with the file (nothing after the last buffer).
public final class FileAudioSource: AudioSource {
    private let url: URL
    private let speed: Double
    private var file: AVAudioFile?
    private let lock = NSLock()
    private var running = false

    public init(url: URL, speed: Double = 1) {
        self.url = url
        self.speed = speed
    }

    public func open() throws -> AVAudioFormat {
        let f = try AVAudioFile(forReading: url)
        file = f
        return f.processingFormat
    }

    public func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard let file else { throw TranscriptionError.noCompatibleAudioFormat }
        lock.withLock { running = true }
        let frames = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
        let pause = 0.1 / speed
        Thread.detachNewThread { [weak self] in
            while let self, self.lock.withLock({ self.running }), file.framePosition < file.length {
                guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
                      (try? file.read(into: buf)) != nil, buf.frameLength > 0 else { break }
                onBuffer(buf)
                Thread.sleep(forTimeInterval: pause)
            }
        }
    }

    public func stop() { lock.withLock { running = false } }
}

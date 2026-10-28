import AVFoundation

/// Where the caption engine's sound comes from (#172): the microphone on every device, or, on the Mac, another app's
/// sound (a FaceTime call). The engine converts whatever format a source delivers, so a source only has to say what
/// that format is and hand over buffers.
public protocol AudioSource: AnyObject {
    /// Gets ready and returns the format every buffer will arrive in. Throws a plain error if there is nothing to
    /// listen to. Called once per session, before `start`.
    func open() throws -> AVAudioFormat
    /// Starts delivering buffers, on a thread of the source's choosing.
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws
    /// Stops and releases everything opened. Safe to call more than once, and before `open`.
    func stop()
}

/// The microphone, through `AVAudioEngine`: what the engine always used before #172.
public final class MicAudioSource: AudioSource {
    private let audioEngine = AVAudioEngine()
    private let micMode: MicMode
    private var tapped = false

    public init(micMode: MicMode = .standard) {
        self.micMode = micMode
    }

    public func open() throws -> AVAudioFormat {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        switch micMode {
        case .raw: try session.setCategory(.record, mode: .measurement)
        case .standard: try session.setCategory(.record, mode: .default)
        case .voiceProcessing: try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        }
        try session.setActive(true)
        #endif
        // Must happen before the tap format is read.
        if micMode == .voiceProcessing { try audioEngine.inputNode.setVoiceProcessingEnabled(true) }
        return audioEngine.inputNode.outputFormat(forBus: 0)
    }

    public func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0)) { buffer, _ in onBuffer(buffer) }
        tapped = true
        audioEngine.prepare()
        try audioEngine.start()
    }

    public func stop() {
        if tapped { audioEngine.inputNode.removeTap(onBus: 0); tapped = false }
        audioEngine.stop()
    }
}

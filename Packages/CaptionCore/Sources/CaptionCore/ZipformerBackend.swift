import AVFoundation
import Foundation

/// Hebrew captions on Seal's own engine (#220): the ivrit.ai 66M streaming zipformer, compressed for Core ML, from
/// the folder bundled in the app. It streams natively, so unlike Parakeet there is no re-decoded window: every
/// 1.28 s of audio goes through the encoder once and its words come out in order. A word stays volatile until the
/// next starts or a pause passes, then is final. Like Parakeet it is Seal's engine (`choice` .parakeet), so a failed
/// load, silence from speech, memory pressure or critical heat hands the session to Apple's engine (design §5).
final class ZipformerBackend: SpeechRecognizerBackend, @unchecked Sendable {
    static let variant = "he-pal4"
    let name = "zipformer-" + ZipformerBackend.variant
    let choice = CaptionEngineChoice.parakeet
    let analyzerFormat: AVAudioFormat? = nil
    var onTrigger: (@Sendable (FallbackTrigger) -> Void)?
    /// Each chunk's seconds of compute, for the developer panel.
    var onDecode: (@Sendable (Double) -> Void)?

    /// How often the loop looks for a new chunk. A chunk is 1.28 s, so a word waits at most this long extra.
    static let poll = 0.1
    static let watchdogSpeechDBFS = ParakeetBackend.watchdogSpeechDBFS

    private let modelURL: URL
    private let lock = NSLock()
    private var network: CoreMLZipformer?
    private var incoming: [Float] = []
    private var loudest = -Double.infinity
    private var heardSeconds = 0.0
    private var loop: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<RecognizedPiece, Error>.Continuation?
    private var memorySource: DispatchSourceMemoryPressure?
    private var settleRequested = false
    // Touched only by the decode loop, then by `finish` after the loop has ended.
    private var features = ZipformerFeatures()
    private var stream = ZipformerStream()
    private var words = ZipformerWords(table: [:])
    private var emitter = ParakeetEmitter()
    private var watchdog = SilentEngineWatchdog()

    init(modelURL: URL) { self.modelURL = modelURL }

    func prepare() async throws {
        if lock.withLock({ self.network != nil }) { return }
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw SpeechModelError.modelMissing(modelURL) }
        let url = modelURL
        let network = try await Task.detached(priority: .userInitiated) { () throws -> CoreMLZipformer in
            let n = try CoreMLZipformer(folder: url)
            // One warm chunk, so the first real one is not the slow one; then a clean state for the session.
            var s = ZipformerStream()
            _ = try s.accept(Array(repeating: [Float](repeating: -10, count: 80), count: ZipformerStream.window), network: n)
            try n.reset()
            return n
        }.value
        lock.withLock {
            self.network = network
            self.words = ZipformerWords(table: network.tokens)
        }
    }

    func start() async throws -> AsyncThrowingStream<RecognizedPiece, Error> {
        guard let network = lock.withLock({ self.network }) else { throw SpeechModelError.modelMissing(modelURL) }
        let (out, continuation) = AsyncThrowingStream.makeStream(of: RecognizedPiece.self)
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in self?.onTrigger?(.memoryWarning) }
        source.resume()
        lock.withLock {
            self.continuation = continuation
            self.memorySource = source
            self.loop = Task.detached(priority: .userInitiated) { [weak self] in await self?.run(network) }
        }
        return out
    }

    func feed(buffer: AVAudioPCMBuffer) {}

    func feed(samples16k: [Float], level: Double) {
        lock.withLock {
            incoming.append(contentsOf: samples16k)
            loudest = max(loudest, level)
            heardSeconds += Double(samples16k.count) / 16_000
        }
    }

    /// Face to face (#60): the engine didn't hear up to `seconds`. The gap is fed as silence so word times stay on
    /// the session clock (a streaming model needs its audio contiguous). Never backwards.
    func skip(to seconds: Double) {
        lock.withLock {
            let gap = seconds - heardSeconds
            guard gap > 0 else { return }
            incoming.append(contentsOf: [Float](repeating: 0, count: Int((gap * 16_000).rounded())))
            heardSeconds = seconds
        }
    }

    func settle() { lock.withLock { settleRequested = true } }

    private func run(_ network: CoreMLZipformer) async {
        var reportedCritical = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.poll))
            if Task.isCancelled { break }
            let (samples, level, settle) = lock.withLock { () -> ([Float], Double, Bool) in
                defer { incoming = []; loudest = -.infinity; settleRequested = false }
                return (incoming, loudest, settleRequested)
            }
            var failed = false
            var heard = 0
            if !samples.isEmpty {
                let began = ContinuousClock.now
                features.append(samples)
                let frames = features.takeFrames()
                do {
                    let before = stream.decodedSeconds
                    let tokens = try stream.accept(frames, network: network)
                    if stream.decodedSeconds > before {
                        let d = ContinuousClock.now - began
                        onDecode?(Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
                    }
                    let (final, open) = words.add(tokens, decodedSeconds: stream.decodedSeconds)
                    heard = tokens.count
                    emit(final: final, volatile: open)
                } catch {
                    failed = true
                }
                if watchdog.observe(seconds: Double(samples.count) / 16_000, speech: level > Self.watchdogSpeechDBFS,
                                    words: heard, failed: failed) {
                    onTrigger?(.noWordsFromSpeech)
                }
            }
            if settle { emit(final: words.flush(), volatile: []) }
            let thermal = ProcessInfo.processInfo.thermalState
            if thermal == .critical, !reportedCritical { reportedCritical = true; onTrigger?(.thermal(.critical)) }
        }
    }

    private func emit(final: [TimedWord], volatile: [TimedWord]) {
        let c = lock.withLock { continuation }
        for piece in emitter.pieces(final: final, volatile: volatile) { c?.yield(piece) }
    }

    func finish() async {
        let loop = lock.withLock { self.loop }
        loop?.cancel()
        await loop?.value
        let network = lock.withLock { () -> CoreMLZipformer? in
            self.loop = nil; memorySource?.cancel(); memorySource = nil
            return continuation != nil ? self.network : nil
        }
        if let network {
            // The last words: what's left, plus two chunks of silence so the encoder reaches the end.
            let rest = lock.withLock { () -> [Float] in defer { incoming = [] }; return incoming }
            features.append(rest + [Float](repeating: 0, count: 2 * 20_480 + 8_000))
            if let tokens = try? stream.accept(features.takeFrames(), network: network) {
                let (final, _) = words.add(tokens, decodedSeconds: stream.decodedSeconds)
                emit(final: final + words.flush(), volatile: [])
            } else {
                emit(final: words.flush(), volatile: [])
            }
        }
        let c = lock.withLock { () -> AsyncThrowingStream<RecognizedPiece, Error>.Continuation? in
            defer { continuation = nil }
            return continuation
        }
        c?.finish()
        release()
    }

    func cancel() async {
        let loop = lock.withLock { self.loop }
        loop?.cancel()
        await loop?.value
        let c = lock.withLock { () -> AsyncThrowingStream<RecognizedPiece, Error>.Continuation? in
            memorySource?.cancel(); memorySource = nil; self.loop = nil
            defer { continuation = nil }
            return continuation
        }
        c?.finish()
        release()
    }

    private func release() { lock.withLock { network = nil } }
}

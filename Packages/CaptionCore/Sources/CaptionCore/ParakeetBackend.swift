import AVFoundation
import FluidAudio
import Foundation

/// Turns the committer's output into pieces CaptionStream already understands (design §2 "Mapping"). Pure.
/// - Newly final words: one final piece, split where they span a pause of `pauseSeconds` or more, so a new line starts
///   in the same place it would with Apple's engine.
/// - Still-open words: one volatile piece.
/// - While a tail is on screen, the first piece's start is widened to the tail's start, so it always replaces the
///   tail instead of committing a stale one beside it.
struct ParakeetEmitter: Sendable {
    let pauseSeconds: Double
    private var openTail: [TimedWord] = []

    init(pauseSeconds: Double = CaptionStream.defaultPauseSeconds) { self.pauseSeconds = pauseSeconds }

    mutating func pieces(final: [TimedWord], volatile: [TimedWord]) -> [RecognizedPiece] {
        var out: [RecognizedPiece] = []
        var groups: [[TimedWord]] = []
        for word in final {
            if let last = groups.last?.last, word.start - last.end >= pauseSeconds { groups.append([word]) }
            else if groups.isEmpty { groups.append([word]) }
            else { groups[groups.count - 1].append(word) }
        }
        var tailStart = openTail.first?.start
        for group in groups {
            out.append(Self.piece(group, isFinal: true, widenTo: tailStart))
            tailStart = nil
        }
        if !final.isEmpty { openTail = [] }
        if !volatile.isEmpty, volatile != openTail {
            out.append(Self.piece(volatile, isFinal: false, widenTo: tailStart))
            openTail = volatile
        }
        return out
    }

    private static func piece(_ words: [TimedWord], isFinal: Bool, widenTo tailStart: Double?) -> RecognizedPiece {
        let start = min(words[0].start, tailStart ?? .infinity)
        return RecognizedPiece(text: words.map(\.text).joined(separator: " "), isFinal: isFinal,
                               words: words.map { RecognizedWord(text: $0.text, range: min($0.start, $0.end)...max($0.start, $0.end)) },
                               start: start, end: words.map(\.end).max())
    }
}

/// The 16 kHz audio Parakeet still needs: from the window start to now. Bounded: never more than `maxSeconds`.
struct SampleWindow: Sendable {
    static let rate = 16_000.0
    let maxSeconds: Double
    private(set) var samples: [Float] = []
    /// Session time of `samples[0]`.
    private(set) var startTime = 0.0
    /// The loudest buffer fed since the last `take`, in dBFS.
    private var loudestSinceTake = -Double.infinity

    init(maxSeconds: Double = 20) { self.maxSeconds = maxSeconds }

    var endTime: Double { startTime + Double(samples.count) / Self.rate }

    mutating func append(_ more: [Float], level: Double) {
        samples.append(contentsOf: more)
        loudestSinceTake = max(loudestSinceTake, level)
        let excess = samples.count - Int(maxSeconds * Self.rate)
        if excess > 0 { drop(excess) }
    }

    /// Face to face (#60): this engine didn't hear the audio up to `time` (another voice's turn). The gap is silence,
    /// so word times stay on the session clock; a gap longer than the window just starts it afresh. Never backwards.
    mutating func skip(to time: Double) {
        let gap = time - endTime
        guard gap > 0 else { return }
        if gap >= maxSeconds {
            samples = []
            startTime = time
        } else {
            append([Float](repeating: 0, count: Int((gap * Self.rate).rounded())), level: -.infinity)
        }
    }

    /// Drops audio before `time` (session seconds).
    mutating func trim(before time: Double) {
        let n = Int(((time - startTime) * Self.rate).rounded(.down))
        if n > 0 { drop(min(n, samples.count)) }
    }

    /// The audio from `from` to now, and the loudest buffer that arrived since the last take.
    mutating func take(from: Double) -> (samples: [Float], start: Double, end: Double, loudest: Double) {
        let first = max(0, min(samples.count, Int(((from - startTime) * Self.rate).rounded(.down))))
        let loudest = loudestSinceTake
        loudestSinceTake = -.infinity
        return (Array(samples[first...]), startTime + Double(first) / Self.rate, endTime, loudest)
    }

    private mutating func drop(_ n: Int) {
        samples.removeFirst(n)
        startTime += Double(n) / Self.rate
    }
}

/// Parakeet Ultra through FluidAudio's AsrManager, decoded as a committed tail window (design §2). Loads only from the
/// bundled folder: `ModelHub.offlineMode` is on and the URL has no default (ADR 0014).
final class ParakeetBackend: SpeechRecognizerBackend, @unchecked Sendable {
    static let variant = "ultra-pal6"
    let name = "parakeet-" + ParakeetBackend.variant
    let choice = CaptionEngineChoice.parakeet
    let analyzerFormat: AVAudioFormat? = nil
    var onTrigger: (@Sendable (FallbackTrigger) -> Void)?
    /// Each decode's seconds, for the developer panel. Called on the decode task.
    var onDecode: (@Sendable (Double) -> Void)?

    private let modelURL: URL
    private let lock = NSLock()
    private var manager: AsrManager?
    private var window = SampleWindow()
    private var loop: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<RecognizedPiece, Error>.Continuation?
    private var memorySource: DispatchSourceMemoryPressure?
    // Touched only by the decode loop, then by `finish` after the loop has ended.
    private var committer = TailCommitter()
    private var emitter = ParakeetEmitter()
    private var watchdog = SilentEngineWatchdog()
    private var decodeTimes: [Double] = []

    init(modelURL: URL) {
        self.modelURL = modelURL
        ModelHub.offlineMode = true
    }

    func prepare() async throws {
        if lock.withLock({ self.manager != nil }) { return }
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw SpeechModelError.modelMissing(modelURL) }
        let url = modelURL
        let models = try await Task.detached(priority: .userInitiated) {
            try AsrModels.loadLocal(from: url, version: .ultra)
        }.value
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        // One warm decode, so the first real one is not the slow one.
        var state = TdtDecoderState.make(decoderLayers: AsrModelVersion.ultra.decoderLayers)
        _ = try await manager.transcribe([Float](repeating: 0, count: Int(SampleWindow.rate)), decoderState: &state)
        lock.withLock { self.manager = manager }
    }

    func start() async throws -> AsyncThrowingStream<RecognizedPiece, Error> {
        guard let manager = lock.withLock({ self.manager }) else { throw ASRError.notInitialized }
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: RecognizedPiece.self)
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in self?.onTrigger?(.memoryWarning) }
        source.resume()
        lock.withLock {
            self.continuation = continuation
            self.memorySource = source
            self.loop = Task.detached(priority: .userInitiated) { [weak self] in await self?.run(manager) }
        }
        return stream
    }

    func feed(buffer: AVAudioPCMBuffer) {}

    func feed(samples16k: [Float], level: Double) {
        lock.withLock { window.append(samples16k, level: level) }
    }

    /// Quieter than this, with nothing open, skips the decode (the beta report's quiet line).
    static let silenceGateDBFS = -50.0
    /// Louder than this counts as someone talking for the watchdog: well above a quiet room.
    static let watchdogSpeechDBFS = -40.0

    private func run(_ manager: AsrManager) async {
        var hop = AdaptiveHop.floor
        var reportedCritical = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(hop))
            if Task.isCancelled { break }
            let audioEnd = lock.withLock { window.endTime }
            let shot = lock.withLock { window.take(from: committer.windowStart(audioEnd: audioEnd)) }
            var heard = 0
            var failed = false
            if shot.loudest < Self.silenceGateDBFS && committer.isSettled {
                // Silence gate: a quiet table with nothing open costs no decode.
                _ = committer.ingest(decode: [], windowStart: shot.start, audioEnd: shot.end)
            } else if let words = await decode(shot.samples, start: shot.start, manager: manager) {
                let out = committer.ingest(decode: words.map { TimedWord(text: $0.text, start: $0.start - shot.start, end: $0.end - shot.start) },
                                           windowStart: shot.start, audioEnd: shot.end)
                heard = out.final.count + out.volatile.count
                for piece in emitter.pieces(final: out.final, volatile: out.volatile) { yield(piece) }
            } else {
                failed = true
            }
            let keep = committer.windowStart(audioEnd: shot.end)
            lock.withLock { window.trim(before: keep) }
            if watchdog.observe(seconds: hop, speech: shot.loudest > Self.watchdogSpeechDBFS, words: heard, failed: failed) {
                onTrigger?(.noWordsFromSpeech)
            }
            let thermal = ProcessInfo.processInfo.thermalState
            if thermal == .critical, !reportedCritical { reportedCritical = true; onTrigger?(.thermal(.critical)) }
            hop = AdaptiveHop.next(decodeTimes: decodeTimes, thermal: thermal)
        }
    }

    /// Words in session time, or nil if the decode failed (the next hop tries again).
    private func decode(_ samples: [Float], start: Double, manager: AsrManager) async -> [TimedWord]? {
        guard !samples.isEmpty else { return [] }
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: Int(SampleWindow.rate))
        let padded = samples.count >= minimum ? samples : samples + [Float](repeating: 0, count: minimum - samples.count)
        let began = ContinuousClock.now
        var state = TdtDecoderState.make(decoderLayers: AsrModelVersion.ultra.decoderLayers)
        guard let result = try? await manager.transcribe(padded, decoderState: &state) else { return nil }
        let d = ContinuousClock.now - began
        let seconds = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        decodeTimes.append(seconds)
        if decodeTimes.count > 5 { decodeTimes.removeFirst(decodeTimes.count - 5) }
        onDecode?(seconds)
        let end = start + Double(samples.count) / SampleWindow.rate
        // Padding is silence after the real audio: anything placed there is cut off at the real end.
        return ParakeetWords.words(from: result.tokenTimings ?? [], windowStart: start)
            .filter { $0.start < end }
            .map { TimedWord(text: $0.text, start: $0.start, end: min($0.end, end)) }
    }

    private func yield(_ piece: RecognizedPiece) {
        let c = lock.withLock { continuation }
        c?.yield(piece)
    }

    func finish() async {
        let (loop, manager) = lock.withLock { (self.loop, self.manager) }
        loop?.cancel()
        await loop?.value
        lock.withLock { self.loop = nil; memorySource?.cancel(); memorySource = nil }
        if let manager, lock.withLock({ continuation != nil }) {
            let audioEnd = lock.withLock { window.endTime }
            let shot = lock.withLock { window.take(from: committer.windowStart(audioEnd: audioEnd)) }
            let words = await decode(shot.samples, start: shot.start, manager: manager) ?? []
            let final = committer.finish(decode: words.map { TimedWord(text: $0.text, start: $0.start - shot.start, end: $0.end - shot.start) },
                                         windowStart: shot.start)
            for piece in emitter.pieces(final: final, volatile: []) { yield(piece) }
        }
        let c = lock.withLock { () -> AsyncThrowingStream<RecognizedPiece, Error>.Continuation? in
            defer { continuation = nil }
            return continuation
        }
        c?.finish()
        await release()
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
        await release()
    }

    private func release() async {
        let manager = lock.withLock { () -> AsrManager? in
            defer { self.manager = nil }
            return self.manager
        }
        await manager?.cleanup()
    }
}

/// The bundled speech model is missing (ADR 0014): fail loudly, never download.
public enum SpeechModelError: Error, Equatable, CustomStringConvertible {
    case modelMissing(URL)
    public var description: String {
        switch self {
        case .modelMissing(let url): "The speech model is missing from the app (\(url.lastPathComponent))."
        }
    }
}

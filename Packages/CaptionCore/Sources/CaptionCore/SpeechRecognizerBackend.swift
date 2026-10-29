import AVFoundation
import Foundation
import Speech

/// One word as a recognizer reported it. `range` is nil when the recognizer gave no time for it.
public struct RecognizedWord: Sendable, Equatable {
    public let text: String
    public let range: ClosedRange<Double>?
    public init(text: String, range: ClosedRange<Double>?) {
        self.text = text
        self.range = range
    }
}

/// Engine-neutral result (design §1): what TranscriptionEngine needs to build a CaptionUpdate.
public struct RecognizedPiece: Sendable, Equatable {
    public let text: String
    public let isFinal: Bool
    public let words: [RecognizedWord]
    /// The audio span the piece claims. Usually first word start to last word end; Parakeet widens the start to
    /// cover the tail it replaces, so CaptionStream treats it as a revision.
    public let start: Double?
    public let end: Double?

    public init(text: String, isFinal: Bool, words: [RecognizedWord], start: Double? = nil, end: Double? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.words = words
        self.start = start ?? words.compactMap { $0.range?.lowerBound }.min()
        self.end = end ?? words.compactMap { $0.range?.upperBound }.max()
    }

    public var wordEnds: [Double] { words.compactMap { $0.range?.upperBound } }
}

/// One speech recognizer behind TranscriptionEngine (ADR 0025). Apple's SpeechAnalyzer and Parakeet both implement it.
/// Only one is live at a time.
protocol SpeechRecognizerBackend: AnyObject, Sendable {
    /// "apple-speechanalyzer" / "parakeet-ultra-pal6": goes in diagnostics and the beta report.
    var name: String { get }
    var choice: CaptionEngineChoice { get }
    /// The format the backend wants buffers in, or nil for the 16 kHz mono side path. Known after `prepare`.
    var analyzerFormat: AVAudioFormat? { get }
    /// Loads the model. Never opens the microphone.
    func prepare() async throws
    func start() async throws -> AsyncThrowingStream<RecognizedPiece, Error>
    /// Called on the audio thread; must not block.
    func feed(buffer: AVAudioPCMBuffer)
    /// Called on the audio thread with the diarizer's 16 kHz mono samples and their level (dBFS); must not block.
    func feed(samples16k: [Float], level: Double)
    /// Face to face (#60): the engine didn't hear the audio before session time `seconds` (another voice's turn); the
    /// next audio fed starts there. Keeps its word times on the session clock.
    func skip(to seconds: Double)
    /// Face to face (#60): the engine stops hearing audio for now (the other voice's turn). Its open words become
    /// final without feeding it silence, which could cover the start of the next turn it has to hear.
    func settle()
    /// Flushes: the remaining words come out as final, then the stream ends.
    func finish() async
    /// Frees the model. Safe more than once, and after a failed prepare.
    func cancel() async
    /// Something the backend noticed that may need a fallback (heat, memory, no words).
    var onTrigger: (@Sendable (FallbackTrigger) -> Void)? { get set }
}

/// Apple's on-device SpeechAnalyzer/SpeechTranscriber (ADR 0001): the code that used to live in TranscriptionEngine,
/// moved, not rewritten.
final class AppleSpeechBackend: SpeechRecognizerBackend, @unchecked Sendable {
    let name = "apple-speechanalyzer"
    let choice = CaptionEngineChoice.apple
    var onTrigger: (@Sendable (FallbackTrigger) -> Void)?
    private let locale: Locale
    private let lock = NSLock()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var format: AVAudioFormat?
    private var builder: AsyncStream<AnalyzerInput>.Continuation?
    private var started = false

    init(locale: Locale) { self.locale = locale }

    var analyzerFormat: AVAudioFormat? { lock.withLock { format } }

    func prepare() async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        // The one-time, system-provisioned model fetch noted in CONTEXT.md "On-device only".
        try await SpeechModelInstaller.install(locale: locale) { _ in }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // Load the model before the first word, not on it.
        try await analyzer.prepareToAnalyze(in: format)
        lock.withLock {
            self.transcriber = transcriber
            self.analyzer = analyzer
            self.format = format
        }
    }

    func start() async throws -> AsyncThrowingStream<RecognizedPiece, Error> {
        guard let (transcriber, analyzer) = lock.withLock({ self.transcriber.flatMap { t in self.analyzer.map { (t, $0) } } }) else {
            throw TranscriptionError.converterUnavailable
        }
        let (sequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        lock.withLock { self.builder = builder }
        try await analyzer.start(inputSequence: sequence)
        lock.withLock { started = true }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await result in transcriber.results {
                        continuation.yield(Self.piece(from: result.text, isFinal: result.isFinal))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func feed(buffer: AVAudioPCMBuffer) {
        let (builder, start) = lock.withLock { () -> (AsyncStream<AnalyzerInput>.Continuation?, CMTime?) in
            defer { skippedTo = nil }
            return (self.builder, skippedTo)
        }
        // After a skip the analyzer is told where this buffer sits, so the gap isn't read as contiguous audio.
        builder?.yield(start.map { AnalyzerInput(buffer: buffer, bufferStartTime: $0) } ?? AnalyzerInput(buffer: buffer))
    }

    func feed(samples16k: [Float], level: Double) {}

    private var skippedTo: CMTime?
    func skip(to seconds: Double) { lock.withLock { skippedTo = CMTime(seconds: seconds, preferredTimescale: 16_000) } }

    func settle() {
        guard let analyzer = lock.withLock({ started ? self.analyzer : nil }) else { return }
        Task { try? await analyzer.finalize(through: nil) }
    }

    func finish() async {
        let (analyzer, started) = takeAnalyzer()
        guard let analyzer else { return }
        if started {
            do { try await analyzer.finalizeAndFinishThroughEndOfInput() }
            catch { await analyzer.cancelAndFinishNow() }   // never leave a recognizer allocated
        } else {
            await analyzer.cancelAndFinishNow()   // loaded ahead but never started (#119)
        }
    }

    func cancel() async {
        let (analyzer, _) = takeAnalyzer()
        await analyzer?.cancelAndFinishNow()
    }

    private func takeAnalyzer() -> (SpeechAnalyzer?, Bool) {
        lock.withLock {
            builder?.finish()
            builder = nil
            let taken = (analyzer, started)
            analyzer = nil
            transcriber = nil
            return taken
        }
    }

    /// Apple's result text to words: every word in a run gets that run's audio time.
    static func piece(from text: AttributedString, isFinal: Bool) -> RecognizedPiece {
        var words: [RecognizedWord] = []
        for run in text.runs {
            let runText = String(text[run.range].characters)
            let range = run.audioTimeRange.map { r -> ClosedRange<Double> in
                let a = r.start.seconds, b = r.end.seconds
                return min(a, b)...max(a, b)
            }
            for word in runText.components(separatedBy: .whitespacesAndNewlines) where !word.isEmpty {
                words.append(RecognizedWord(text: word, range: range))
            }
        }
        return RecognizedPiece(text: String(text.characters), isFinal: isFinal, words: words)
    }
}

/// Emphasis per word from the loudness series (#emphasis): a word with no time is normal. Pure, so the Apple and
/// Parakeet paths give the same levels for the same words.
enum WordEmphasis {
    static func levels(for words: [RecognizedWord], baseline: Double?, loudness: (ClosedRange<Double>) -> Double?,
                       fallback: Double) -> [EmphasisLevel] {
        words.map { word in
            guard let range = word.range else { return .normal }
            return EmphasisMapper.level(wordDBFS: loudness(range) ?? fallback, baseline: baseline)
        }
    }
}

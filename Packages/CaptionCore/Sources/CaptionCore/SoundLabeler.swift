import AVFoundation
import Foundation
import SoundAnalysis

/// On-device ambient sound recognition (ADR 0016) using the system-provided SNClassifySoundRequest.
/// Runs on its own serial queue, never blocks the audio thread. Emits SoundLabelKind events
/// through an async stream, applying confidence threshold and debounce before yielding.
final class SoundLabeler: NSObject, @unchecked Sendable, SNResultsObserving {
    private let queue = DispatchQueue(label: "caption.sound-labeler")
    private let lock = NSLock()
    private var analyzer: SNAudioStreamAnalyzer?
    private var detector = SoundLabelDetector()
    private var continuation: AsyncStream<SoundLabelKind>.Continuation?
    private var failure: Error?
    private var audioTimeAtLastSample = 0.0

    /// Prepare the sound classifier. Must be called before feed().
    func prepare() throws {
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
        guard let audioFormat else { throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "audio-format")) }

        queue.async { [self] in
            self.lock.lock()
            defer { self.lock.unlock() }
            do {
                let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                let newAnalyzer = try SNAudioStreamAnalyzer(format: audioFormat)
                try newAnalyzer.add(request, withObserver: self)
                self.analyzer = newAnalyzer
            } catch {
                self.failure = error
            }
        }
    }

    // MARK: - SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        processClassification(result)
    }

    func requestDidComplete(_ request: SNRequest) {}

    func request(_ request: SNRequest, didFailWithError error: Error) {
        lock.lock(); failure = error; lock.unlock()
    }

    /// Consume audio and emit recognized sounds through an async stream.
    /// The stream is non-throwing and never closes due to internal errors (errors are logged but don't terminate).
    func stream() -> AsyncStream<SoundLabelKind> {
        AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.continuation = continuation
            self?.lock.unlock()
        }
    }

    /// Never blocks the audio thread: feed runs on its own serial queue.
    func feed(_ samples: [Float], atAudioTime audioTime: Double) {
        audioTimeAtLastSample = audioTime
        queue.async { [self] in
            self.lock.lock()
            guard let analyzer = self.analyzer else { self.lock.unlock(); return }
            self.lock.unlock()
            let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
            guard let audioFormat else { return }
            let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(samples.count))
            guard let buffer else { return }
            guard let channel = buffer.floatChannelData else { return }
            channel[0].update(from: samples, count: samples.count)
            buffer.frameLength = AVAudioFrameCount(samples.count)
            analyzer.analyze(buffer, atAudioFramePosition: 0)
        }
    }

    /// One line for dev diagnostics.
    var diagnostics: String {
        lock.lock(); defer { lock.unlock() }
        let err = failure.map { " ERR \($0)" } ?? ""
        return "sound: heard to \(String(format: "%.1f", audioTimeAtLastSample))s\(err)"
    }

    func finish() {
        queue.sync { [self] in
            self.lock.lock()
            defer { self.lock.unlock() }
            self.analyzer?.completeAnalysis()
            self.analyzer = nil
            self.continuation?.finish()
        }
    }

    private func processClassification(_ result: SNClassificationResult) {
        lock.lock()
        defer { lock.unlock() }
        for classification in result.classifications {
            let identifier = classification.identifier
            let confidence = classification.confidence
            if let label = detector.label(identifier: identifier, confidence: Double(confidence), at: audioTimeAtLastSample) {
                continuation?.yield(label)
            }
        }
    }
}

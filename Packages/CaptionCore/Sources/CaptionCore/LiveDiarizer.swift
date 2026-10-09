import CoreML
import FluidAudio
import Foundation

public enum SpeakerModelError: Error, Equatable, CustomStringConvertible {
    case modelMissing(URL)

    public var description: String {
        switch self {
        case .modelMissing(let url):
            "The speaker-labeling model is missing from the app (expected at \(url.lastPathComponent)). Run scripts/fetch-diarizer-models.sh and rebuild."
        }
    }
}

/// Streaming speaker diarization (ADR 0008) on FluidAudio's Sortformer: 16 kHz mono Float32 in,
/// speaker segments out. The model is a pre-compiled folder shipped inside the app (ADR 0014);
/// nothing is ever downloaded at runtime.
final class LiveDiarizer: @unchecked Sendable {
    private let modelURL: URL
    private let diarizer = SortformerDiarizer(config: .default)
    private let queue = DispatchQueue(label: "caption.diarizer")
    private let lock = NSLock()
    private var finalized: [SpeakerSegment] = []
    private var tentative: [SpeakerSegment] = []
    private var failure: Error?
    private var updates = 0
    private var speakersSeen = Set<Int>()
    private var latestEnd = 0.0

    init(modelURL: URL) {
        self.modelURL = modelURL
        // Any code path that still tries to download a model must throw, not reach the network.
        ModelHub.offlineMode = true
    }

    /// `config` must match the shipped model variant and precision (fastV2_1, fp16): FluidAudio only
    /// logs a warning on a mismatch and then diarizes wrongly and slowly.
    func prepare() async throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw SpeakerModelError.modelMissing(modelURL)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        diarizer.initialize(models: try SortformerModels(config: .default, main: model))
    }

    /// Never blocks the audio thread: inference runs on a serial queue.
    func feed(_ samples: [Float]) {
        queue.async { [self] in
            do {
                diarizer.addAudio(samples)
                if let update = try diarizer.process() { merge(update) }
            } catch {
                lock.lock(); failure = error; lock.unlock()
            }
        }
    }

    /// Finalized segments are permanent; tentative ones are rebuilt every update.
    var segments: [SpeakerSegment] {
        lock.lock(); defer { lock.unlock() }
        return finalized + tentative
    }

    /// One line for the spike UI: is the diarizer running, how many distinct speakers has it reported?
    var diagnostics: String {
        lock.lock(); defer { lock.unlock() }
        let who = speakersSeen.sorted().map { String($0 + 1) }.joined(separator: ",")
        let err = failure.map { " ERR \($0)" } ?? ""
        return "diarizer: \(updates) updates · speakers [\(who)] · heard to \(String(format: "%.1f", latestEnd))s\(err)"
    }

    var lastError: Error? { lock.lock(); defer { lock.unlock() }; return failure }

    func finish() { queue.sync { _ = try? diarizer.finalizeSession() } }

    private func merge(_ update: DiarizerTimelineUpdate) {
        func convert(_ s: DiarizerSegment) -> SpeakerSegment {
            SpeakerSegment(speaker: s.speakerIndex, start: Double(s.startTime), end: Double(s.endTime))
        }
        lock.lock(); defer { lock.unlock() }
        updates += 1
        finalized += update.finalizedSegments.map(convert)
        tentative = update.tentativeSegments.map(convert)
        for seg in finalized + tentative { speakersSeen.insert(seg.speaker); latestEnd = max(latestEnd, seg.end) }
    }
}

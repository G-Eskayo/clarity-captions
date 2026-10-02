import FluidAudio
import Foundation

/// Streaming speaker diarization (ADR 0008) on FluidAudio's Sortformer: 16 kHz mono Float32 in,
/// speaker segments out. Spike-grade: models are fetched on first use; bundling them so first
/// launch makes no network call is a separate task.
final class LiveDiarizer: @unchecked Sendable {
    private let diarizer = SortformerDiarizer(config: .default)
    private let queue = DispatchQueue(label: "caption.diarizer")
    private let lock = NSLock()
    private var finalized: [SpeakerSegment] = []
    private var tentative: [SpeakerSegment] = []
    private var failure: Error?
    private var updates = 0
    private var speakersSeen = Set<Int>()
    private var latestEnd = 0.0

    func prepare() async throws {
        let models = try await SortformerModels.loadFromHuggingFace(config: .default)
        diarizer.initialize(models: models)
    }

    /// Never blocks the audio thread: inference runs on a serial queue.
    func feed(_ samples: [Float]) {
        queue.async { [self] in
            do {
                try diarizer.addAudio(samples)
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

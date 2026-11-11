import FluidAudio
import Foundation

/// One caption line's audio range, as the caption engine would report it. Phrases form a single stream (one line at a
/// time, as on screen) in time order; `SpeakerPathReplay` asks for each one's label the way the app does.
public struct SpeakerReplayPhrase: Equatable, Sendable, Codable {
    public let start: Double
    public let end: Double
    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// One label request and what the app's speaker path answered.
public struct SpeakerReplayEmission: Equatable, Sendable, Codable {
    public let now: Double        // audio seconds fed when the caption result arrived
    public let phrase: Int
    public let isFinal: Bool
    public let label: Int?        // SpeakerLabelSmoother: what the screen shows (0-based, order of appearance)
    public let rawSlot: Int?      // SpeakerAligner: the plain-overlap slot, for comparison (face to face uses it)
}

public struct SpeakerReplayResult: Sendable {
    public let emissions: [SpeakerReplayEmission]
    public let finalSegments: [SpeakerSegment]   // the bare model's own output, after finalizeSession
    public let audioSeconds: Double
    public let loadSeconds: Double               // MLModel load + Sortformer initialize
    public let chunkMillis: [Double]             // wall time to feed and process each app-sized buffer
}

/// The app's live speaker path replayed over a recording (#271): the real `LiveDiarizer` fed at the app's buffer size,
/// and every caption result labeled by a session `SpeakerLabelSmoother` against the segments the app would have had at
/// that moment, exactly as `TranscriptionEngine.makeResultStream` does. Same schedule as SpeakerStabilityReplayTests
/// (#91): the tap delivers ~85 ms buffers (4096 frames at 48 kHz = 1365 at 16 kHz); a live result for the line being
/// spoken every half second; the final about a second after the line ends.
///
/// The diarizer is drained after every buffer, so labels reflect a diarizer that keeps up with real time; `chunkMillis`
/// shows whether it would (each buffer is 85 ms of audio). Audio is pulled a buffer at a time, so a long recording is
/// never held in memory and peak memory is the model's, not the harness's.
public enum SpeakerReplayError: Error, Equatable {
    case phrasesNotAStream   // phrases must be non-empty ranges, in time order, never overlapping (one line at a time)
}

public enum SpeakerPathReplay {
    public static let appChunk = 1365
    public static let sampleRate = 16_000.0

    /// One caption line at a time, as on screen: each phrase has positive length and starts at or after the previous end.
    public static func isStream(_ phrases: [SpeakerReplayPhrase]) -> Bool {
        guard phrases.allSatisfy({ $0.end > $0.start && $0.start >= 0 }) else { return false }
        return zip(phrases, phrases.dropFirst()).allSatisfy { $1.start >= $0.end }
    }

    /// Factory-based run: accepts a diarizer factory for alternative models (Nemotron3, LS-EEND, etc).
    /// `next` returns the next run of 16 kHz mono samples (any length), or nil at the end of the recording.
    /// `onChunk` runs after each buffer with the audio seconds fed so far (the eval samples memory there).
    public static func run(next: () throws -> [Float]?, phrases: [SpeakerReplayPhrase],
                           diarizer: () async throws -> LiveDiarizer, volatileEvery: Double = 0.5, finalDelay: Double = 1.0,
                           onChunk: ((Double) -> Void)? = nil) async throws -> SpeakerReplayResult {
        guard isStream(phrases) else { throw SpeakerReplayError.phrasesNotAStream }
        let t0 = Date()
        let d = try await diarizer()
        try await d.prepare()
        let loadSeconds = Date().timeIntervalSince(t0)

        var smoother = SpeakerLabelSmoother()   // one per session (#91)
        var emissions: [SpeakerReplayEmission] = []
        var chunkMillis: [Double] = []
        var finalized = Set<Int>()
        var nextFinal = 0                       // phrases finalize in order: their ends are increasing
        var nextVolatile = volatileEvery
        var fed = 0

        func ask(_ p: Int, isFinal: Bool, now: Double) {
            let ph = phrases[p]
            let end = isFinal ? ph.end : min(now, ph.end)
            guard end > ph.start else { return }
            let segments = d.segments
            let label = smoother.label(start: ph.start, end: end, segments: segments, isFinal: isFinal)
            let raw = SpeakerAligner.speaker(start: ph.start, end: end, segments: segments)
            emissions.append(SpeakerReplayEmission(now: now, phrase: p, isFinal: isFinal, label: label, rawSlot: raw))
        }

        func step(_ chunk: ArraySlice<Float>) {
            let c0 = DispatchTime.now().uptimeNanoseconds
            d.feed(Array(chunk))
            d.drain()
            chunkMillis.append(Double(DispatchTime.now().uptimeNanoseconds - c0) / 1e6)
            fed += chunk.count
            let now = Double(fed) / sampleRate
            while nextFinal < phrases.count && now >= phrases[nextFinal].end + finalDelay {
                finalized.insert(nextFinal); ask(nextFinal, isFinal: true, now: now); nextFinal += 1
            }
            if now >= nextVolatile {
                nextVolatile += volatileEvery
                // One line is being spoken at a time: the latest one that has started and isn't final yet.
                if let p = phrases.lastIndex(where: { $0.start < now && now < $0.end + finalDelay }), !finalized.contains(p) {
                    ask(p, isFinal: false, now: now)
                }
            }
            onChunk?(now)
        }

        var pending: [Float] = []
        while let more = try next() {
            pending += more
            var i = 0
            while pending.count - i >= appChunk { step(pending[i..<(i + appChunk)]); i += appChunk }
            pending.removeFirst(i)
        }
        if !pending.isEmpty { step(pending[...]) }
        let audioSeconds = Double(fed) / sampleRate
        // Silence after the recording so the last lines get their finals, as the app's tail does.
        let tail = [Float](repeating: 0, count: appChunk)
        while nextFinal < phrases.count { step(tail[...]) }
        if let e = d.lastError { throw e }
        d.finish()
        return SpeakerReplayResult(emissions: emissions, finalSegments: d.segments, audioSeconds: audioSeconds,
                                   loadSeconds: loadSeconds, chunkMillis: chunkMillis)
    }

    /// Convenience overload for Sortformer: modelURL and config → factory.
    public static func run(next: () throws -> [Float]?, phrases: [SpeakerReplayPhrase], modelURL: URL,
                           config: SortformerConfig = .default, volatileEvery: Double = 0.5, finalDelay: Double = 1.0,
                           onChunk: ((Double) -> Void)? = nil) async throws -> SpeakerReplayResult {
        return try await run(next: next, phrases: phrases,
                           diarizer: { LiveDiarizer(modelURL: modelURL, config: config) },
                           volatileEvery: volatileEvery, finalDelay: finalDelay, onChunk: onChunk)
    }
}

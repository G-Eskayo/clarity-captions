import Foundation

/// Tracks acoustic traits (pitch, speech rate) per speaker during transcription, fed from both
/// audio samples (for pitch) and text timing (for speech rate). Lock-protected like LiveDiarizer (#247).
final class SpeakerVoiceTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _traits: [Int: SpeakerTraits] = [:]
    private var pitchHistogram: [Int: [Double]] = [:]
    private var speechRateSamples: [Int: [(words: Int, seconds: Double)]] = [:]
    private static let maxPitchSamples = 500
    private static let maxRateSamples = 200

    /// Feed audio samples to estimate pitch per speaker via diarizer segments.
    /// - Parameters:
    ///   - samples: one buffer chunk of audio
    ///   - sampleRate: sample rate of the buffer (typically 16000)
    ///   - bufferStartTime: session-relative start time of this buffer in seconds
    ///   - segments: speaker segments (session-absolute times) from the diarizer
    func feed(_ samples: [Float], sampleRate: Int, bufferStartTime: Double, segments: [SpeakerSegment]) {
        guard !segments.isEmpty, !samples.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }

        let bufferStartSample = Int(bufferStartTime * Double(sampleRate))
        let bufferEndSample = bufferStartSample + samples.count

        for segment in segments {
            let segmentStartSample = Int(segment.start * Double(sampleRate))
            let segmentEndSample = Int(segment.end * Double(sampleRate))
            let overlapStart = max(segmentStartSample, bufferStartSample)
            let overlapEnd = min(segmentEndSample, bufferEndSample)
            guard overlapStart < overlapEnd else { continue }

            let localStart = overlapStart - bufferStartSample
            let localEnd = overlapEnd - bufferStartSample
            guard localStart >= 0, localEnd <= samples.count else { continue }

            let segmentSamples = Array(samples[localStart..<localEnd])
            if let pitch = estimatePitch(segmentSamples, sampleRate: sampleRate) {
                if pitchHistogram[segment.speaker] == nil {
                    pitchHistogram[segment.speaker] = []
                }
                pitchHistogram[segment.speaker]?.append(pitch)
                let count = pitchHistogram[segment.speaker]?.count ?? 0
                if count > Self.maxPitchSamples {
                    let excess = count - Self.maxPitchSamples
                    pitchHistogram[segment.speaker]?.removeFirst(excess)
                }
            }
        }
        updateTraits()
    }

    /// Feed text-based timing to estimate speech rate per speaker.
    func addLine(speaker: Int?, text: String, speechSeconds: Double) {
        guard let speaker, speechSeconds > 0 else { return }
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        guard words > 0 else { return }

        lock.lock(); defer { lock.unlock() }
        if speechRateSamples[speaker] == nil {
            speechRateSamples[speaker] = []
        }
        speechRateSamples[speaker]?.append((words: words, seconds: speechSeconds))
        let count = speechRateSamples[speaker]?.count ?? 0
        if count > Self.maxRateSamples {
            let excess = count - Self.maxRateSamples
            speechRateSamples[speaker]?.removeFirst(excess)
        }
        updateTraits()
    }

    var traits: [Int: SpeakerTraits] {
        lock.lock(); defer { lock.unlock() }
        return self._traits
    }

    /// Remap speaker IDs in pitch and rate samples from raw to smoothed labels.
    /// Used to align pitch data (keyed by diarizer raw IDs) with rate data (keyed by smoothed IDs).
    func remapSpeaker(from rawID: Int, to smoothedID: Int) {
        lock.lock(); defer { lock.unlock() }

        // Move pitch histogram from raw ID to smoothed ID.
        if let pitchSamples = pitchHistogram.removeValue(forKey: rawID) {
            if pitchHistogram[smoothedID] == nil {
                pitchHistogram[smoothedID] = pitchSamples
            } else {
                pitchHistogram[smoothedID]?.append(contentsOf: pitchSamples)
            }
        }

        updateTraits()
    }

    private func updateTraits() {
        var result: [Int: SpeakerTraits] = [:]
        let speakers = Set(pitchHistogram.keys).union(Set(speechRateSamples.keys))

        for speaker in speakers {
            var pitch: Double? = nil
            if let samples = pitchHistogram[speaker], !samples.isEmpty {
                pitch = computeMedian(samples)
            }

            var rate: Double? = nil
            if let samples = speechRateSamples[speaker], !samples.isEmpty {
                let totalWords = samples.map(\.words).reduce(0, +)
                let totalSeconds = samples.map(\.seconds).reduce(0, +)
                if totalSeconds > 0 {
                    rate = Double(totalWords) / totalSeconds
                }
            }

            result[speaker] = SpeakerTraits(speaker: speaker, pitchHz: pitch, speechRate: rate)
        }
        self._traits = result
    }

    private func estimatePitch(_ samples: [Float], sampleRate: Int) -> Double? {
        guard samples.count >= sampleRate / 20 else { return nil }
        let frameSamples = min(512, samples.count)
        guard frameSamples >= 32 else { return nil }

        var energy = 0.0
        for i in 0..<frameSamples {
            energy += Double(samples[i] * samples[i])
        }
        energy /= Double(frameSamples)
        guard energy > 1e-6 else { return nil }

        // Detect voices from 50 Hz (low males) to 400 Hz (children).
        // At 16 kHz: minLag (400 Hz) = 40 samples, maxLag (50 Hz) = 320 samples.
        let minLag = sampleRate / 400
        let maxLag = min(sampleRate / 50, frameSamples - 1)
        var maxCorr = 0.0
        var bestLag = 0

        for lag in minLag..<maxLag {
            var corr = 0.0
            for i in 0..<(frameSamples - lag) {
                corr += Double(samples[i] * samples[i + lag])
            }
            if corr > maxCorr {
                maxCorr = corr
                bestLag = lag
            }
        }

        guard bestLag > 0, maxCorr > energy * Double(frameSamples) * 0.3 else { return nil }
        return Double(sampleRate) / Double(bestLag)
    }

    private func computeMedian(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted.count % 2 == 0
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            : sorted[sorted.count / 2]
    }
}

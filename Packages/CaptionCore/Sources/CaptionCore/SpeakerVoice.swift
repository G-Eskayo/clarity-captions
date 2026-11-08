import AVFoundation
import Foundation

/// Moved from the #247 spike: matching individual speaker voices to a translation language's on-device voice,
/// so "Speak it in my ear" can adapt pitch and rate per speaker (#247). Spanish only, #254.
public struct VoiceMatch {
    /// Spanish speaker calibration: pitch (semitones) and rate (fraction of normal) per speaker (0–3).
    /// Nil (no-op) for non-Spanish or no calibration. Populated at app init from the shipped literal.
    nonisolated(unsafe) public static var spanishCalibration: [VoiceCalibration]?

    /// Load Spanish calibration from a JSON file at the given path.
    public static func loadSpanishCalibration(from path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        spanishCalibration = try? JSONDecoder().decode([VoiceCalibration].self, from: data)
    }

    /// Match a speaker's voice to the shipped calibration for a language, returning pitch and rate
    /// adjustments for that speaker if found. Safe to call with nil calibration (returns nil).
    /// Selects the best calibration entry based on the speaker's measured voice characteristics.
    public static func match(speaker: Int?, from traits: [Int: SpeakerTraits], language: String) -> (pitch: Double, rate: Double)? {
        guard language == "es", let speaker, let speakerTraits = traits[speaker], let cal = spanishCalibration, !cal.isEmpty else { return nil }

        // If we have measured pitch and rate, select the best matching calibration by minimizing distance.
        // Otherwise, use the speaker ID (with bounds checking) for compatibility.
        let selectedIdx: Int
        if let measuredPitch = speakerTraits.pitchHz, let measuredRate = speakerTraits.speechRate {
            // Compute distance from measured traits to each calibration profile.
            // For pitch, we expect a range of 80-300 Hz, normalized to 0-1.
            // For rate, we expect a range of 1-4 words/sec, normalized to 0-1.
            let normalizedPitch = (measuredPitch - 50) / 250  // 50-300 Hz -> 0-1
            var bestIdx = 0
            var bestDistance = Double.infinity

            for (idx, calibration) in cal.enumerated() {
                // Rate distance: compare measured rate to expected rate with calibration applied.
                // Typical rate without calibration is ~2.0 wps; with calibration it's 2.0 * rateMultiplier.
                let calibratedRate = 2.0 * calibration.rateMultiplier
                let rateDistance = abs(measuredRate - calibratedRate) / 4.0  // Normalize to 0-1

                // Pitch distance: calibration shifts are in semitones, we compare the effect.
                // Each semitone changes pitch by a factor of 2^(1/12) ≈ 1.0595.
                let pitchMultiplier = pow(2.0, Double(calibration.pitchSemitones) / 12.0)
                let calibratedPitch = 170 * pitchMultiplier  // Assume ~170 Hz baseline (middle of range)
                let calibratedPitchNorm = (calibratedPitch - 50) / 250
                let pitchDistance = abs(normalizedPitch - calibratedPitchNorm)

                let distance = pitchDistance + rateDistance
                if distance < bestDistance {
                    bestDistance = distance
                    bestIdx = idx
                }
            }
            selectedIdx = bestIdx
        } else {
            // No measured traits; use speaker ID with bounds checking (for tests or when traits aren't available).
            selectedIdx = min(speaker, cal.count - 1)
        }

        let c = cal[selectedIdx]
        let pitch = pow(2.0, Double(c.pitchSemitones) / 12.0)
        return (pitch: pitch, rate: c.rateMultiplier)
    }
}

/// Pitch (in semitones, ±12 for one octave) and rate (1.0 = normal) for one speaker in a language.
public struct VoiceCalibration: Codable, Equatable, Sendable {
    public let pitchSemitones: Int
    public let rateMultiplier: Double

    public init(pitchSemitones: Int, rateMultiplier: Double) {
        self.pitchSemitones = pitchSemitones
        self.rateMultiplier = rateMultiplier
    }
}

/// Per-speaker acoustic traits tracked during a session: pitch histogram, typical rate.
public struct SpeakerTraits: Equatable, Sendable {
    public let speaker: Int
    /// Measured pitch in Hz; nil if no pitch samples yet.
    public let pitchHz: Double?
    /// Measured speech rate in words/second; nil if insufficient timing yet.
    public let speechRate: Double?

    public init(speaker: Int, pitchHz: Double?, speechRate: Double?) {
        self.speaker = speaker
        self.pitchHz = pitchHz
        self.speechRate = speechRate
    }
}

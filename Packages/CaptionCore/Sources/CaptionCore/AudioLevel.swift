import Foundation

struct AudioLevel {
    /// Computes RMS dBFS (decibels relative to full scale) for a buffer of Float32 samples.
    /// Returns a value floor-clamped at -60 dB so silence doesn't produce -infinity.
    static func rmsDBFS(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -60 }
        let rms = sqrt(samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count))
        let dbfs = 20 * log10(max(rms, 1e-6))
        return max(dbfs, -60)
    }
}

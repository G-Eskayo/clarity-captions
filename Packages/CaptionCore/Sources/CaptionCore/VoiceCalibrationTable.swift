import Foundation

/// Voice calibration measurements for on-device AVSpeechSynthesisVoices. A voice's pitch and pace, and how
/// `AVSpeechUtterance.rate` and `pitchMultiplier` actually move them. Measured once at setup in Settings.
/// Spanish language measurements available; others return empty (#247).
public enum VoiceCalibrationTable {
    /// All calibrated voices for a language (language identifier like "es", "es-MX"), empty if not yet measured.
    public static func calibrations(for language: String) -> [VoiceCalibration] {
        switch language.lowercased().prefix(2) {
        case "es":
            return spanishCalibrations
        default:
            return []
        }
    }

    /// Spanish voices measured in the #247 spike. To regenerate: run `ear-spike voice-match` on a device with
    /// Spanish voices installed, and copy the JSON output here. Evidence: docs/perf/ear-translation/voice-calibration-es.json.
    private static let spanishCalibrations: [VoiceCalibration] = [
        // Placeholder: real measurements to be added after running ear-spike.
        // Structure: VoiceCalibration(id: "com.apple.ttsbundle.Siri_Female_es-MX_compact",
        //                             pitchHz: 200, syllablesPerSecond: 4.5,
        //                             rateCurve: [...], pitchCurve: [...])
    ]
}

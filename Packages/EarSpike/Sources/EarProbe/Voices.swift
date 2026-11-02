@preconcurrency import AVFoundation
import EarSpikeKit
import Foundation
@preconcurrency import Translation

/// One translation language and the on-device voice that can speak it (#233).
public struct VoiceRow: Codable, Sendable {
    public let language: String        // Locale.Language minimal identifier, e.g. "he", "zh-Hant"
    public let fromEnglish: String     // LanguageAvailability status en -> language on this device
    public let voice: String?          // matched AVSpeechSynthesisVoice.language, nil = captions only
    public let voicesInLanguage: Int   // how many voices of any region/quality the device has
    public let bestQuality: String?    // default / enhanced / premium among the matched region's voices
    public let sampleVoice: String?    // identifier of the voice the lag test uses
}

public enum Voices {
    public static func quality(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q { case .premium: "premium"; case .enhanced: "enhanced"; default: "default" }
    }

    /// Prefer premium, then enhanced, then default, among the voices for one language code; skip novelty voices.
    public static func best(for code: String) -> AVSpeechSynthesisVoice? {
        let novelty: Set<String> = ["Albert", "Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos", "Good News",
                                    "Jester", "Organ", "Superstar", "Trinoids", "Whisper", "Wobble", "Zarvox",
                                    "Deranged", "Hysterical", "Pipe Organ", "Fred", "Junior", "Kathy", "Ralph"]
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == code && !novelty.contains($0.name) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    public static func table() async -> [VoiceRow] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let codes = Array(Set(all.map(\.language))).sorted()
        let english = Locale.Language(identifier: "en")
        let availability = LanguageAvailability()
        var rows: [VoiceRow] = []
        let supported: [Locale.Language] = await availability.supportedLanguages
        for language in supported.sorted(by: { $0.minimalIdentifier < $1.minimalIdentifier }) {
            let id = language.minimalIdentifier
            var status = "source"
            if !id.hasPrefix("en") {
                let s: LanguageAvailability.Status = await availability.status(from: english, to: language)
                status = "\(s)"
            }
            let match = VoiceCoverage.voice(for: id, among: codes)
            let base = id.split(separator: "-").first.map(String.init) ?? id
            let inLanguage = all.filter { VoiceCoverage.voice(for: base, among: [$0.language]) != nil }.count
            let pick = match.flatMap { Voices.best(for: $0) }
            rows.append(VoiceRow(language: id, fromEnglish: status, voice: match, voicesInLanguage: inLanguage,
                                 bestQuality: pick.map { Voices.quality($0.quality) }, sampleVoice: pick?.identifier))
        }
        return rows
    }
}

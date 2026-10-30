import Foundation

/// Which on-device voice (an `AVSpeechSynthesisVoice.language` code like "he-IL") can speak a translation language
/// (a `Locale.Language` identifier like "he", "pt-PT" or "zh-Hant"), #233. Pure, so the matching is tested apart from
/// whatever voices a device has.
public enum VoiceCoverage {
    /// Same language and region first, then the same language in any region. Chinese matches by script: Traditional
    /// takes Taiwan or Hong Kong, Simplified takes the mainland. Norwegian ("no") and Bokmål ("nb") are one.
    public static func voice(for language: String, among voices: [String]) -> String? {
        let want = parts(language)
        let have = voices.map { ($0, parts($0)) }
        let sameLanguage = have.filter { $0.1.language == want.language }
        if want.language == "zh", let script = want.script {
            let regions: Set<String> = script == "hant" ? ["tw", "hk", "mo"] : ["cn", "sg"]
            return sameLanguage.first { regions.contains($0.1.region ?? "") }?.0
        }
        if let region = want.region, let exact = sameLanguage.first(where: { $0.1.region == region }) { return exact.0 }
        return sameLanguage.first?.0
    }

    private struct Parts { let language: String; let script: String?; let region: String? }

    private static func parts(_ code: String) -> Parts {
        let bits = code.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
        var language = bits.first ?? ""
        if language == "no" { language = "nb" }
        var script: String?
        var region: String?
        for bit in bits.dropFirst() {
            if bit.count == 4 { script = bit } else if region == nil { region = bit }
        }
        return Parts(language: language, script: script, region: region)
    }
}

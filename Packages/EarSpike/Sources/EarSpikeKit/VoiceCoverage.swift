import Foundation

/// Which on-device voice (an `AVSpeechSynthesisVoice.language` code like "he-IL") can speak a translation language
/// (a `Locale.Language` identifier like "he", "pt-PT" or "zh-Hant"), #233. Pure, so the matching is tested apart from
/// whatever voices a device has.
public enum VoiceCoverage {
    /// Both sides are expanded to language, script and region ("zh" is zh-Hans-CN, "zh-TW" is zh-Hant-TW, "es" is
    /// es-Latn-ES). A voice must share the language and the script; the language's own (or main) region wins, then any
    /// region. Norwegian ("no") and Bokmål ("nb") are one.
    public static func voice(for language: String, among voices: [String]) -> String? {
        let want = parts(language)
        let same = voices.map { ($0, parts($0)) }
            .filter { $0.1.language == want.language && ($0.1.script == nil || want.script == nil || $0.1.script == want.script) }
        return (same.first { $0.1.region == want.region } ?? same.first)?.0
    }

    private struct Parts { let language: String; let script: String?; let region: String? }

    private static func parts(_ code: String) -> Parts {
        var id = code.replacingOccurrences(of: "_", with: "-")
        if id.lowercased() == "no" || id.lowercased().hasPrefix("no-") { id = "nb" + id.dropFirst(2) }
        let full = Locale.Language(identifier: Locale.Language(identifier: id).maximalIdentifier)
        return Parts(language: full.languageCode?.identifier.lowercased() ?? id.lowercased(),
                     script: full.script?.identifier.lowercased(),
                     region: full.region?.identifier.lowercased())
    }
}

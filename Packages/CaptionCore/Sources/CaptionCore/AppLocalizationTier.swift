import Foundation

/// Localization tier: whether a language is fully translated, in beta, or English-only (untranslated).
public enum LanguageTier: Equatable, Sendable {
    case full, beta, untranslated
}

public enum AppLocalizationTier {
    /// Tier for a given language code. English is always full even if not in the translated set.
    /// Beta = translated but not native-checked. Untranslated = no translation yet.
    public static func tier(for localeIdentifier: String,
                           translatedLanguageCodes: Set<String> = ["en"],
                           nativeCheckedLanguageCodes: Set<String> = []) -> LanguageTier {
        let locale = Locale(identifier: localeIdentifier)
        let bcp47 = locale.identifier(.bcp47)
        let languageString = (bcp47.split(separator: "-").first.map(String.init) ?? "").lowercased()

        if languageString == "en" { return .full }

        if nativeCheckedLanguageCodes.contains(languageString) { return .full }
        if translatedLanguageCodes.contains(languageString) { return .beta }
        return .untranslated
    }
}

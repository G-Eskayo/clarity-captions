import Foundation

public enum LanguageSelection {
    /// Default locale based on device preference and supported locales. Returns nil if device language is
    /// ambiguous (multiple supported variants) or unsupported, in which case first run must ask.
    public static func defaultLocale(deviceLocaleIdentifier: String, supportedLocaleIdentifiers: [String]) -> String? {
        guard !supportedLocaleIdentifiers.isEmpty else { return nil }

        let device = Locale(identifier: deviceLocaleIdentifier)
        let deviceBCP47 = device.identifier(.bcp47)

        let supported = supportedLocaleIdentifiers.map { Locale(identifier: $0) }

        // Exact BCP47 match wins.
        if let exact = supported.first(where: { $0.identifier(.bcp47).lowercased() == deviceBCP47.lowercased() }) {
            return exact.identifier
        }

        // Single same-language-code match wins; multiple is ambiguous.
        let deviceLangCode = (deviceBCP47.split(separator: "-").first.map(String.init) ?? "").lowercased()
        guard !deviceLangCode.isEmpty else { return nil }
        let sameLanguage = supported.filter { lang in
            (lang.identifier(.bcp47).split(separator: "-").first.map(String.init) ?? "").lowercased() == deviceLangCode
        }
        if sameLanguage.count == 1 {
            return sameLanguage[0].identifier
        }

        // Ambiguous or unsupported.
        return nil
    }

    /// True if the device language is ambiguous or unsupported, so first run must ask the user.
    public static func mustAskOnFirstRun(deviceLocaleIdentifier: String, supportedLocaleIdentifiers: [String]) -> Bool {
        defaultLocale(deviceLocaleIdentifier: deviceLocaleIdentifier, supportedLocaleIdentifiers: supportedLocaleIdentifiers) == nil
    }
}

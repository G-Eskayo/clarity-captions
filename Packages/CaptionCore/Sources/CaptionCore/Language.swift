import Foundation

public enum AppLocalizationCatalog {
    private static let translatedBaseLanguages = Set(["en"])

    public static func isTranslated(localeIdentifier: String) -> Bool {
        let locale = Locale(identifier: localeIdentifier)
        guard let languageCode = locale.language.languageCode?.identifier else { return false }
        return translatedBaseLanguages.contains(languageCode)
    }
}

public enum LanguageSelection {
    public static func mustAskOnFirstRun(deviceLocaleIdentifier: String, supportedLocaleIdentifiers: [String]) -> Bool {
        let selectedLocale = select(deviceLocaleIdentifier: deviceLocaleIdentifier, supportedLocaleIdentifiers: supportedLocaleIdentifiers)
        return selectedLocale == nil
    }

    public static func defaultLocale(deviceLocaleIdentifier: String, supportedLocaleIdentifiers: [String]) -> String? {
        select(deviceLocaleIdentifier: deviceLocaleIdentifier, supportedLocaleIdentifiers: supportedLocaleIdentifiers)
    }

    private static func select(deviceLocaleIdentifier: String, supportedLocaleIdentifiers: [String]) -> String? {
        guard !supportedLocaleIdentifiers.isEmpty else { return nil }

        let device = Locale(identifier: deviceLocaleIdentifier)
        guard let deviceLanguageCode = device.language.languageCode?.identifier else { return nil }

        let exactMatch = supportedLocaleIdentifiers.first { $0 == deviceLocaleIdentifier }
        if let match = exactMatch { return match }

        let sameLanguageMatches = supportedLocaleIdentifiers.filter { supported in
            let supportedLocale = Locale(identifier: supported)
            guard let supportedLanguageCode = supportedLocale.language.languageCode?.identifier else { return false }
            return supportedLanguageCode == deviceLanguageCode
        }

        if sameLanguageMatches.count == 1 {
            return sameLanguageMatches[0]
        }

        return nil
    }
}

public struct LanguageStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var selectedLocaleIdentifier: String? {
        defaults.string(forKey: "language.selectedLocale")
    }

    public func setSelectedLocaleIdentifier(_ identifier: String) {
        defaults.set(identifier, forKey: "language.selectedLocale")
    }
}

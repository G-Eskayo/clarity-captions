import Foundation

extension Locale {
    /// Localized display name of this locale (e.g., "Français", "Español", "English").
    public var localizedDisplayName: String {
        let lang = identifier(.bcp47)
        return Locale(identifier: lang).localizedString(forIdentifier: lang) ?? lang
    }
}

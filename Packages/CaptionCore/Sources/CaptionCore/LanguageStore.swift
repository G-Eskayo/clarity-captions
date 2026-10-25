import Foundation

/// Saves the selected language between launches. Returns en-US as the default if nothing is saved yet.
public struct LanguageStore {
    public static let defaultLocale = "en-US"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var selectedLocaleIdentifier: String {
        get { defaults.string(forKey: "language.selected") ?? Self.defaultLocale }
        set { defaults.set(newValue, forKey: "language.selected") }
    }

    /// True if a language has been explicitly selected (stored in UserDefaults).
    public var hasSelection: Bool {
        defaults.string(forKey: "language.selected") != nil
    }
}

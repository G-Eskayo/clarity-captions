import Foundation

/// Gathers the locales Apple's speech engines support, formats as JSON for research (#36).
/// Pure: the four lists and OS string are passed in, so JSON output is testable without device APIs.
public struct SpeechLocaleReport {
    /// The locales each source supports, passed in (deduplicated and sorted by bcp47 string).
    public let supportedLocales: [Locale]
    public let installedLocales: [Locale]
    public let dictionarySupported: [Locale]
    public let dictionaryInstalled: [Locale]
    /// e.g. "iOS 18.2.1" or "macOS 15.2"
    public let osVersion: String

    /// Creates a report from the four locale lists and OS version string.
    public init(
        supportedLocales: [Locale],
        installedLocales: [Locale],
        dictionarySupported: [Locale],
        dictionaryInstalled: [Locale],
        osVersion: String
    ) {
        let key = CaptionLanguage.bcp47
        func dedup(_ locales: [Locale]) -> [Locale] {
            var seen = Set<String>()
            return locales.filter { seen.insert(key($0)).inserted }.sorted { key($0) < key($1) }
        }
        self.supportedLocales = dedup(supportedLocales)
        self.installedLocales = dedup(installedLocales)
        self.dictionarySupported = dedup(dictionarySupported)
        self.dictionaryInstalled = dedup(dictionaryInstalled)
        self.osVersion = osVersion
    }

    /// JSON object matching the schema from `scripts/speech-locales/probe.swift`.
    public func asJSON() -> [String: Any] {
        let key = CaptionLanguage.bcp47
        return [
            "os": osVersion,
            "date": ISO8601DateFormatter().string(from: Date()),
            "SpeechTranscriber.supportedLocales": supportedLocales.map(key).sorted(),
            "SpeechTranscriber.installedLocales": installedLocales.map(key).sorted(),
            "DictationTranscriber.supportedLocales": dictionarySupported.map(key).sorted(),
            "DictationTranscriber.installedLocales": dictionaryInstalled.map(key).sorted(),
        ]
    }
}

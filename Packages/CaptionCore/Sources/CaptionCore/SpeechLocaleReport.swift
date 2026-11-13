import Foundation
import Speech

public struct SpeechLocaleReport {
    /// Generates a JSON report of the device's speech framework capabilities.
    ///
    /// JSON keys (sorted): "date", "DictationTranscriber.installedLocales", "DictationTranscriber.supportedLocales",
    /// "SFSpeechRecognizer.supportedLocales", "SpeechTranscriber.installedLocales", "SpeechTranscriber.supportedLocales".
    /// All locale lists are deduplicated and sorted in BCP 47 format.
    public static func json(
        os: String,
        date: Date,
        speechTranscriberSupported: [Locale],
        speechTranscriberInstalled: [Locale],
        dictationSupported: [Locale],
        dictationInstalled: [Locale],
        sfSpeechSupported: [Locale]
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let isoDate = formatter.string(from: date)

        let report: [String: Any] = [
            "date": isoDate,
            "DictationTranscriber.installedLocales": sortedBcp47(dictationInstalled),
            "DictationTranscriber.supportedLocales": sortedBcp47(dictationSupported),
            "SFSpeechRecognizer.supportedLocales": sortedBcp47(sfSpeechSupported),
            "SpeechTranscriber.installedLocales": sortedBcp47(speechTranscriberInstalled),
            "SpeechTranscriber.supportedLocales": sortedBcp47(speechTranscriberSupported),
            "os": os,
        ]

        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Generates a human-readable summary of the device's speech framework capabilities.
    ///
    /// Format: "ST: X supported, DT: Y supported (Z new)"
    /// where Z is the count of DictationTranscriber locales not in SpeechTranscriber.
    /// All counts are deduplicated.
    public static func summary(
        os: String,
        speechTranscriberSupported: [Locale],
        dictationSupported: [Locale]
    ) -> String {
        let speechBcp47 = Set(sortedBcp47(speechTranscriberSupported))
        let dictationBcp47 = Set(sortedBcp47(dictationSupported))
        let dictationOnlyCount = dictationBcp47.count - dictationBcp47.intersection(speechBcp47).count

        return "ST: \(speechBcp47.count) supported, DT: \(dictationBcp47.count) supported (\(dictationOnlyCount) new)"
    }

    private static func sortedBcp47(_ locales: [Locale]) -> [String] {
        Set(locales.map { $0.identifier(.bcp47) }).sorted()
    }
}

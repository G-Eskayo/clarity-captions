import CaptionCore
import Foundation
import Speech
import UIKit

/// Gathers what speech locales are available on this device (#36): calls the live APIs and wraps the result
/// in a SpeechLocaleReport for JSON export. Used by the developer panel's "Copy speech locales" button.
enum SpeechLocaleDump {
    /// Collects the four locale lists from Apple's APIs and OS version, returns a ready-to-serialize report.
    static func current() async -> SpeechLocaleReport {
        let os = UIDevice.current.systemVersion
        let device = UIDevice.current.systemName
        let osVersion = "\(device) \(os)"

        async let supported = SpeechTranscriber.supportedLocales
        async let installed = SpeechTranscriber.installedLocales
        async let dictSupported = DictationTranscriber.supportedLocales
        async let dictInstalled = DictationTranscriber.installedLocales

        return SpeechLocaleReport(
            supportedLocales: await supported,
            installedLocales: await installed,
            dictionarySupported: await dictSupported,
            dictionaryInstalled: await dictInstalled,
            osVersion: osVersion
        )
    }
}

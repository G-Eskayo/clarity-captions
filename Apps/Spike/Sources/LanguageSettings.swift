import CaptionCore
import Foundation
import UIKit

/// What Settings shows for the caption language (#37) and translation (#53).
struct LanguageSettingsState: Equatable {
    var captions: Locale
    /// No language picked yet: captions follow the device's language.
    var followsDevice: Bool
    var translationOn: Bool
    var target: Locale?
    /// The translation language pack for this pair: nil when it's on the device, else 0...1 while it downloads.
    var downloadProgress: Double?

    /// The saved choices, with the device's language filling in what hasn't been picked.
    static func current(store: CaptionLanguageStore = CaptionLanguageStore(),
                        preferred: [String] = Locale.preferredLanguages) -> LanguageSettingsState {
        let saved = store.captionLanguage
        // Until the engine's supported list is read (#37 wiring), the device's first language stands in.
        let captions = saved ?? Locale(identifier: preferred.first ?? "en-US")
        var state = LanguageSettingsState(captions: captions, followsDevice: saved == nil, translationOn: store.translationOn,
                                          target: store.translationTarget ?? CaptionLanguage.translationTarget(captions: captions, preferred: preferred))
        #if DEBUG
        if let id = DemoMode.language { state.captions = Locale(identifier: id); state.followsDevice = id == preferred.first }
        if let id = DemoMode.translate { state.translationOn = true; state.target = Locale(identifier: id) }
        state.downloadProgress = DemoMode.translateProgress
        #endif
        return state
    }

    static func name(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// "iPad" or "iPhone", for "matches this iPad".
    static var deviceWord: String { UIDevice.current.model }

    /// Settings' sample caption in the caption language, and its translation. A short fixed table: the real
    /// captions are translated live, this is only the preview line.
    static func sample(_ locale: Locale) -> String? {
        switch locale.language.languageCode?.identifier {
        case "en": String(localized: "Let's book a table for seven.")
        case "es": "¿Reservamos una mesa para siete?"
        case "fr": "On réserve une table pour sept ?"
        case "de": "Reservieren wir einen Tisch für sieben?"
        default: nil
        }
    }
}

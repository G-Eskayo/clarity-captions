import CaptionCore
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// What Settings shows for the caption language (#37) and translation (#53).
struct LanguageSettingsState: Equatable {
    var captions: Locale
    /// No language picked yet: captions follow the device's language.
    var followsDevice: Bool
    var translationOn: Bool
    var target: Locale?
    /// The caption language's own download (#37), while one runs or after one failed.
    var captionDownload: CaptionLanguageSwitch.Phase = .ready
    /// The translation language pack for this pair: nil when it's on the device, else 0...1 while it downloads. Apple's
    /// download sheet reports no progress, so a real download shows `translationPreparing` instead (demo screens only).
    var downloadProgress: Double?
    /// Apple's language pack download for this pair is open or running (#53).
    var translationPreparing = false
    /// The pair can't be translated (Cantonese): said plainly, not hidden (#53).
    var unsupportedPair = false
    /// Translation is a one-time in-app purchase (owner, #171).
    var translationOwned = false
    /// The App Store's price for it, as StoreKit shows it; nil until the store answers.
    var translationPrice: String?
    /// A purchase or restore is open: the buttons don't take a second tap.
    var purchaseBusy = false
    /// Live Translation in your ear (#233): offered on this device, and what it's doing.
    var earOffered = false
    var ear: EarState = .off
    /// A plain line from the purchase (Ask to Buy, nothing to restore, didn't go through), or nil.
    var purchaseMessage: String?

    #if os(iOS)
    /// The saved choices, with the device's language filling in what hasn't been picked. The Mac has its own (#209).
    @MainActor
    static func current(languages: CaptionLanguageCenter = .shared, translation: TranslationCenter = .shared,
                        ear: EarCenter = .shared, preferred: [String] = Locale.preferredLanguages) -> LanguageSettingsState {
        let captions = languages.current
        var state = LanguageSettingsState(captions: captions, followsDevice: languages.followsDevice,
                                          translationOn: translation.isOn, target: translation.target)
        state.captionDownload = languages.change.phase
        state.translationOwned = translation.purchase.isOwned
        state.translationPrice = translation.price
        state.translationPreparing = translation.preparing
        state.unsupportedPair = translation.unsupportedPair
        state.purchaseBusy = [.buying, .restoring].contains(translation.purchase.activity)
        state.purchaseMessage = translation.purchase.message
        state.earOffered = EarCenter.offered
        state.ear = ear.state
        #if DEBUG
        if let id = DemoMode.language { state.followsDevice = id == preferred.first }
        if let p = DemoMode.translateProgress { state.downloadProgress = p }
        #endif
        return state
    }
    #endif

    static func name(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// "iPad", "iPhone" or "Mac", for "matches this iPad".
    static var deviceWord: String {
        #if os(iOS)
        UIDevice.current.model
        #else
        String(localized: "Mac")
        #endif
    }

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

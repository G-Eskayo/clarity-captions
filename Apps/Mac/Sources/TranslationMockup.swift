import CaptionCore
import SwiftUI

/// Live Translation on the Mac (#213), for the owner's approval before it's wired, through the screenshot contract
/// (`-SealTranslateMockup <step>`). It draws the real `CallPopupView` and the shared `SettingsPage`; only the data is
/// made up. The room speaks Spanish, the calls French, and she reads English.
struct TranslationMockup: View {
    enum Step: String, CaseIterable {
        /// Settings before the Mac's own purchase: Unlock at its $1.99 price.
        case offer
        /// Settings once bought and on: a From for the room and one for calls, then Into.
        case settings
        /// A FaceTime call: the other person's words translated, hers left as she said them.
        case call
        /// The room: everyone near the Mac translated.
        case room
    }

    let step: Step
    let style: CaptionStyle

    private let spanish = Locale(identifier: "es-MX")
    private let french = Locale(identifier: "fr-FR")
    private let english = Locale(identifier: "en-US")

    private var callLines: [CallPopupView.Line] {
        [
            CallPopupView.Line(id: 0, speaker: 0, name: "Dana", text: "Tu m'entends bien ?", translation: "Can you hear me okay?"),
            CallPopupView.Line(id: 1, speaker: 1, name: String(localized: "You"), text: "Yes, loud and clear."),
            CallPopupView.Line(id: 2, speaker: 0, name: "Dana", text: "Dimanche, ça marche toujours pour le dîner.",
                               translation: "Sunday still works for dinner."),
            CallPopupView.Line(id: 3, speaker: 0, name: "Dana", text: "Les enfants veulent te dire bonjour", volatile: true),
        ]
    }

    private var roomLines: [CallPopupView.Line] {
        [
            CallPopupView.Line(id: 0, speaker: 0, name: nil, text: "¿Reservamos una mesa para siete?",
                               translation: "Shall we book a table for seven?"),
            CallPopupView.Line(id: 1, speaker: 1, name: nil, text: "Sí, a las ocho está bien.", translation: "Yes, eight o'clock is fine."),
            CallPopupView.Line(id: 2, speaker: 0, name: nil, text: "Perfecto, la llamo ahora", volatile: true),
        ]
    }

    var body: some View {
        switch step {
        case .offer, .settings: settings
        case .call, .room: popup
        }
    }

    private var popup: some View {
        CallPopupView(
            lines: step == .call ? callLines : roomLines,
            status: .captioning,
            style: style,
            control: PrimaryControl.for(.listening),
            roomLevelDBFS: -28,
            statusOverride: step == .call ? CallSignal.captioningWords(app: "FaceTime") : nil
        )
        .frame(width: 440, height: 480)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var settings: some View {
        var language = LanguageSettingsState(captions: spanish, followsDevice: false, translationOn: step == .settings,
                                             target: english, callCaptions: french)
        language.translationOwned = step == .settings
        language.translationPrice = "$1.99"
        return SettingsPage(style: .constant(style), idleStop: .constant(.default), store: nil,
                            onGear: {}, onOpen: { _ in }, language: language)
            .frame(width: 440, height: 520)
            .background(style.background.color)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

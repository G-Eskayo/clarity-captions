import CaptionCore
import SwiftUI

/// The call pop-up (#172) with fixed demo lines, for screenshots through the screenshot contract
/// (`-SealPopupMockup <variant>`). It draws the real `CallPopupView`; only the data is made up.
struct CallPopupMockup: View {
    enum Variant: String, CaseIterable {
        /// Captioning a call.
        case auto
        /// Captioning, before anyone has spoken.
        case waiting
        /// Captions switched off.
        case stopped
        /// #246: captioning a Spanish call translated into English, in the look `-SealTranslatedLook` names.
        case translated
    }

    let variant: Variant
    let style: CaptionStyle

    private let lines = [
        CallPopupView.Line(id: 0, speaker: 0, name: "Dana", text: "Hi! Can you read me okay on the computer?"),
        CallPopupView.Line(id: 1, speaker: 1, name: "Sam", text: "We're all here, the kids want to say hello."),
        CallPopupView.Line(id: 2, speaker: 0, name: "Dana", text: "Sunday still works for dinner", volatile: true),
    ]

    /// #246: the iPhone demo's Spanish conversation (DemoMode.spanishScript) with its stand-in translations; the voice
    /// part-way through the newest line.
    private let translatedLines = [
        CallPopupView.Line(id: 0, speaker: 0, name: nil, text: "¿Está encendido? Di algo para que lo veamos.",
                           translation: "Is it on? Say something so we can see.", saidLanguage: "es-ES"),
        CallPopupView.Line(id: 1, speaker: 1, name: nil, text: "Hola. Mis palabras aparecen en la pantalla.",
                           translation: "Hi. My words are showing up on the screen.", saidLanguage: "es-ES"),
        CallPopupView.Line(id: 2, speaker: 0, name: nil, text: "También funciona en modo avión. Nada sale del teléfono.",
                           translation: "It works in airplane mode too. Nothing leaves the phone.", saidLanguage: "es-ES",
                           speakingFirm: 5),
    ]
    var look: TranslatedCaptionLook = .today

    var body: some View {
        let state: CaptionState = variant == .stopped ? .idle : .listening
        let shown = variant == .auto || variant == .translated
        CallPopupView(
            lines: variant == .translated ? translatedLines : variant == .auto ? lines : [],
            status: CallPopupView.Status(state, hasLines: shown),
            style: style,
            control: PrimaryControl.for(state),
            roomLevelDBFS: shown ? -28 : -60,   // someone talking; a quiet room
            translatedLook: look
        )
        .frame(width: 440)
        .frame(height: shown ? (variant == .translated ? 580 : 420) : nil)
        .fixedSize(horizontal: false, vertical: !shown)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

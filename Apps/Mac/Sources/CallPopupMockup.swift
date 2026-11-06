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
        /// Translated captions (#246).
        case translated
    }

    let variant: Variant
    let style: CaptionStyle

    private var lines: [CallPopupView.Line] {
        let baseLines = [
            CallPopupView.Line(id: 0, speaker: 0, name: "Dana", text: "Hi! Can you read me okay on the computer?"),
            CallPopupView.Line(id: 1, speaker: 1, name: "Sam", text: "We're all here, the kids want to say hello."),
            CallPopupView.Line(id: 2, speaker: 0, name: "Dana", text: "Sunday still works for dinner", volatile: true),
        ]
        if variant == .translated {
            return [
                CallPopupView.Line(id: 0, speaker: 0, name: "Dana", text: "¿Hola, buenas tardes. ¿En qué le puedo ayudar?",
                                  translation: "Hi, good afternoon. How can I help you?"),
                CallPopupView.Line(id: 1, speaker: 1, name: "Sam", text: "Necesito el tren al aeropuerto.",
                                  translation: "I need the train to the airport."),
                CallPopupView.Line(id: 2, speaker: 0, name: "Dana", text: "Sale del andén cuatro, cada veinte minutos.",
                                  translation: "It leaves from platform four, every twenty minutes.", volatile: true),
            ]
        }
        return baseLines
    }

    var body: some View {
        let state: CaptionState = variant == .stopped ? .idle : .listening
        let hasLines = variant == .auto || variant == .translated
        CallPopupView(
            lines: hasLines ? lines : [],
            status: CallPopupView.Status(state, hasLines: hasLines),
            style: style,
            control: PrimaryControl.for(state),
            roomLevelDBFS: hasLines ? -28 : -60   // someone talking; a quiet room
        )
        .frame(width: 440)
        .frame(height: hasLines ? 420 : nil)
        .fixedSize(horizontal: false, vertical: !hasLines)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

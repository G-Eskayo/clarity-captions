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
    }

    let variant: Variant
    let style: CaptionStyle

    private let lines = [
        CallPopupView.Line(id: 0, speaker: 0, name: "Dana", text: "Hi! Can you read me okay on the computer?"),
        CallPopupView.Line(id: 1, speaker: 1, name: "Sam", text: "We're all here, the kids want to say hello."),
        CallPopupView.Line(id: 2, speaker: 0, name: "Dana", text: "Sunday still works for dinner", volatile: true),
    ]

    var body: some View {
        let state: CaptionState = variant == .stopped ? .idle : .listening
        CallPopupView(
            lines: variant == .auto ? lines : [],
            status: CallPopupView.Status(state, hasLines: variant == .auto),
            style: style,
            buttonTitle: PrimaryControl.for(state).title,
            roomLevelDBFS: variant == .auto ? -28 : -60   // someone talking; a quiet room
        )
        .frame(width: 440)
        .frame(height: variant == .auto ? 420 : nil)
        .fixedSize(horizontal: false, vertical: variant != .auto)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

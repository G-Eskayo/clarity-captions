import CaptionCore
import SwiftUI

/// The #178 steps with fixed demo lines, for screenshots through the screenshot contract
/// (`-SealCallMockup ringing|call|ended`, `-SealCallPhase 0...1` for a frame of the ring). It draws the real
/// `CallPopupView` and `CallBannerView`; only the data is made up.
struct CallArrivalMockup: View {
    enum Step: String, CaseIterable {
        /// Captioning the room when a call rings: the banner under the pop-up.
        case ringing
        /// After [ Caption call ]: the call's captions, the room's conversation paused.
        case call
        /// The call ended: offer to save its transcript.
        case ended
    }

    let step: Step
    let style: CaptionStyle
    var phase: Double = 0.18

    private let room = [
        CallPopupView.Line(id: 0, speaker: 0, name: "Rosa", text: "Do you want tea, or should I make coffee?"),
        CallPopupView.Line(id: 1, speaker: 1, name: nil, text: "Tea, please. The decaf one."),
        CallPopupView.Line(id: 2, speaker: 0, name: "Rosa", text: "Okay, it's on", volatile: true),
    ]
    private let call = [
        CallPopupView.Line(id: 10, speaker: 0, name: "Dana", text: "Hi! Can you read me okay on the computer?"),
        CallPopupView.Line(id: 11, speaker: 1, name: nil, text: "Yes, the words are coming up as you talk."),
        CallPopupView.Line(id: 12, speaker: 0, name: "Dana", text: "Sunday still works for dinner", volatile: true),
    ]

    var body: some View {
        VStack(spacing: 10) {
            CallPopupView(
                lines: step == .ringing ? room : call,
                status: step == .ended ? .stopped("") : .captioning,
                style: style,
                buttonTitle: PrimaryControl.for(step == .ended ? .idle : .listening).title,
                buttonEnabled: step != .ended,
                pinned: .constant(true),
                statusWords: step == .ringing ? String(localized: "Captioning the room") : step == .ended ? String(localized: "Call ended") : nil
            )
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            switch step {
            case .ringing: CallBannerView(kind: .ringing, style: style, phase: phase)
            case .ended: CallBannerView(kind: .ended, style: style)
            case .call: PausedConversationNote(style: style)
            }
        }
        .frame(width: 440)
    }
}

/// Under the pop-up while a call is captioned: the room's conversation is kept, and comes back after the call.
struct PausedConversationNote: View {
    let style: CaptionStyle

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(style.gear.color)
            Text("Your conversation is paused. It comes back when the call ends.")
                .font(.system(size: 14))
                .foregroundStyle(style.text.color.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(style.background.color)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(style.text.color.opacity(0.14), lineWidth: 1))
        )
        .environment(\.colorScheme, style.background.isDark ? .dark : .light)
    }
}

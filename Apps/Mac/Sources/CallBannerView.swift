import CaptionCore
import SwiftUI

/// The banner under the pop-up when a call arrives mid-conversation (#178), and again when it ends to offer saving the
/// call's transcript. Two bracketed choices, in the app's gummy buttons. The same view draws the live banner and the
/// mock-up frames, so what Gil approves is what ships.
struct CallBannerView: View {
    enum Kind: Equatable {
        /// A call is ringing or has just started: caption it instead of the room?
        case ringing
        /// The call ended: save its transcript, or return to the conversation (owner, 2026-10-28).
        case ended
    }

    let kind: Kind
    let style: CaptionStyle
    /// Where the ring animation is, 0...1, for frozen screenshot frames. Nil: animate live.
    var phase: Double? = nil
    /// The question under the title, when it differs (no conversation on screen to pause).
    var detailOverride: String? = nil
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                icon.frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(style.text.color)
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(style.text.color.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button(action: onPrimary) { label(primaryTitle) }
                    .buttonStyle(GummyButtonStyle(style: style))
                    .keyboardShortcut(.defaultAction)
                Button(action: onSecondary) { label(secondaryTitle) }
                    .buttonStyle(GummyButtonStyle(fill: style.background.mixed(with: style.text, 0.14), label: style.text))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(style.background.color)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(style.text.color.opacity(0.14), lineWidth: 1))
        )
        .environment(\.colorScheme, style.background.isDark ? .dark : .light)
    }

    private func label(_ words: String) -> some View {
        Text(words)
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    private var title: String {
        switch kind {
        case .ringing: String(localized: "You're getting a call")
        case .ended: String(localized: "The call ended")
        }
    }

    private var detail: String {
        if let detailOverride { return detailOverride }
        return switch kind {
        case .ringing: String(localized: "Pause this conversation and caption the call?")
        case .ended: String(localized: "Save this call's transcript, or go back to your conversation where it left off.")
        }
    }

    private var primaryTitle: String {
        switch kind {
        case .ringing: String(localized: "Caption call")
        case .ended: String(localized: "Save transcript")
        }
    }

    private var secondaryTitle: String {
        switch kind {
        case .ringing: String(localized: "Not now")
        case .ended: String(localized: "Return")
        }
    }

    @ViewBuilder private var icon: some View {
        switch kind {
        case .ringing:
            if let phase {
                RingingPhone(phase: phase, color: style.gear.color)
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    RingingPhone(phase: (t / RingingPhone.period).truncatingRemainder(dividingBy: 1), color: style.gear.color)
                }
            }
        case .ended:
            Image(systemName: "phone.down.circle.fill")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(style.gear.color)
        }
    }
}

/// A phone handset that rings in bursts: two quick wobbles, then a rest, with sound arcs that swell while it shakes.
/// `phase` runs 0...1 over one ring (`period` seconds); drawn from it alone so any frame can be captured.
struct RingingPhone: View {
    static let period: Double = 1.6
    let phase: Double
    let color: Color

    /// The first 45% of each ring shakes; the rest is still.
    private var shake: Double {
        let p = phase / 0.45
        return p < 1 ? sin(p * .pi * 4) * (1 - p * 0.3) : 0
    }
    private var swell: Double { phase < 0.5 ? sin(phase / 0.5 * .pi) : 0 }

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.14))
            Image(systemName: "phone.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(color)
                .rotationEffect(.degrees(shake * 16))
                .offset(x: -3, y: 3)
            ForEach(0..<2) { i in
                Arc()
                    .stroke(color.opacity(swell * (i == 0 ? 0.9 : 0.55)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 20 + CGFloat(i) * 9 + swell * 3, height: 20 + CGFloat(i) * 9 + swell * 3)
                    .offset(x: 12, y: -12)
            }
        }
    }

    /// The quarter circle of a sound wave, up and to the right of the handset.
    private struct Arc: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.addArc(center: CGPoint(x: rect.minX, y: rect.maxY), radius: rect.width / 2,
                     startAngle: .degrees(-80), endAngle: .degrees(-10), clockwise: false)
            return p
        }
    }
}

private extension RGBA {
    /// This color moved `amount` of the way toward `other`: an opaque tint, so the gummy lip under it still reads.
    func mixed(with other: RGBA, _ amount: Double) -> RGBA {
        RGBA(r + (other.r - r) * amount, g + (other.g - g) * amount, b + (other.b - b) * amount)
    }
}

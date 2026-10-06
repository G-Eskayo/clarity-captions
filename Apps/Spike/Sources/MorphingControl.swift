import CaptionCore
import SwiftUI

/// The one control at the bottom of the screen. Start, Getting ready, Try again and Stop are the SAME view in
/// different shapes: a wide pill that sweeps into a small red circle (and back), changing color and content as it
/// goes, instead of one button disappearing and another appearing (which flashed).
struct MorphingControl: View {
    let control: PrimaryControl
    /// The width of the pill state: the full row in portrait, a fixed width in landscape.
    let fullWidth: CGFloat
    /// Pill fill (the look's text color) and pill label (the look's background color): the look's 7:1 contrast.
    let fill: Color
    let label: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var compact: Bool { control.presentation == .compact }
    private let stopRed = Color(red: 0.80, green: 0.12, blue: 0.12)
    private var diameter: CGFloat { PrimaryControl.compactDiameter }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: compact ? diameter / 2 : 18, style: .continuous) }

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(control.title)
                    .font(.title.bold())
                    .foregroundStyle(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)
                    .opacity(compact ? 0 : 1)
                    .scaleEffect(compact ? 0.6 : 1)
                Image(systemName: "xmark")
                    .font(.title2.bold())
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(.white)
                    .opacity(compact ? 1 : 0)
                    .scaleEffect(compact ? 1 : 0.4)
                    .rotationEffect(.degrees(compact ? 0 : -90))
            }
            .frame(width: compact ? diameter : fullWidth, height: compact ? diameter : 72)
            .background(compact ? stopRed : fill, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(control.isEnabled ? 1 : 0.5)
        .disabled(!control.isEnabled)
        .accessibilityLabel(control.accessibilityLabel)
        // Reduce Motion: a plain quick crossfade instead of the sweep.
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.78), value: control.presentation)
        .animation(.easeInOut(duration: 0.2), value: control.title)
    }
}

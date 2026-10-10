import CaptionCore
import SwiftUI

/// The one control at the bottom of the screen. Start, Getting ready, Try again and Stop are the SAME view in
/// different shapes: a wide pill that sweeps into a small red circle (and back), changing color and content as it
/// goes, instead of one button disappearing and another appearing (which flashed). The pill is button style A
/// (design #96, image 10): a capsule on a thin darker lip that sinks when pressed; the lip fades out as the pill
/// sweeps into the circle, which keeps its own look.
struct MorphingControl: View {
    let control: PrimaryControl
    /// The width of the pill state: the full row in portrait, a fixed width in landscape.
    let fullWidth: CGFloat
    /// Pill fill (the look's text color) and pill label (the look's background color): the look's 7:1 contrast.
    let fill: RGBA
    let label: RGBA
    /// DEBUG demos only: draw the pressed pill without a finger (simctl can't tap).
    var forcePressed: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var compact: Bool { control.presentation == .compact }
    private let stopRed = Color(red: 0.80, green: 0.12, blue: 0.12)
    private var diameter: CGFloat { PrimaryControl.compactDiameter }
    /// The bar is 72 pt tall; the pill takes all of it but the resting lip.
    private var pillHeight: CGFloat { 72 - GummyButtonStyle.restingLip }
    /// A capsule as a pill, a circle when compact: the same rounded rectangle, so the sweep stays smooth.
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: (compact ? diameter : pillHeight) / 2, style: .continuous) }

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(control.title)
                    .font(.title.bold())
                    .foregroundStyle(label.color)
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
            .frame(width: compact ? diameter : fullWidth, height: compact ? diameter : pillHeight)
            .background(compact ? stopRed : fill.color, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(MorphingGummyStyle(shape: shape, lip: fill.gummyLip.color, showsLip: !compact, forcePressed: forcePressed))
        .opacity(control.isEnabled ? 1 : 0.5)
        .disabled(!control.isEnabled)
        .accessibilityLabel(control.accessibilityLabel)
        // Reduce Motion: a plain quick crossfade instead of the sweep.
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.78), value: control.presentation)
        .animation(.easeInOut(duration: 0.2), value: control.title)
    }
}

/// Button style A for the morphing control: the pill sinks onto its lip when pressed (3 pt resting, 1 pt pressed,
/// then springs back, as GummyButtonStyle does); as a circle there is no lip and no sink.
private struct MorphingGummyStyle: ButtonStyle {
    let shape: RoundedRectangle
    let lip: Color
    let showsLip: Bool
    let forcePressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        GummyBody(configuration: configuration, shape: shape, lip: lip, showsLip: showsLip, forcePressed: forcePressed)
    }

    private struct GummyBody: View {
        let configuration: Configuration
        let shape: RoundedRectangle
        let lip: Color
        let showsLip: Bool
        let forcePressed: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = showsLip && (configuration.isPressed || forcePressed)
            let sink = GummyButtonStyle.restingLip - GummyButtonStyle.pressedLip
            configuration.label
                .offset(y: pressed ? sink : 0)
                .background(shape.fill(lip).offset(y: GummyButtonStyle.restingLip).opacity(showsLip ? 1 : 0))
                .padding(.bottom, GummyButtonStyle.restingLip)
                .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.55), value: pressed)
        }
    }
}

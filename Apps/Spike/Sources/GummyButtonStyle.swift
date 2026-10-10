import CaptionCore
import SwiftUI

/// Button style A, final (design #96, image 10): a flat pill sitting on a thin darker lip. Resting, the lip shows
/// 3 pt; pressed, the pill sinks so only 1 pt shows, then springs back when let go. Fill is the look's text color and
/// the label its background color (the look's 7:1 contrast), as the Start button already does.
///
/// To adopt it elsewhere: `.buttonStyle(GummyButtonStyle(style: style))`.
struct GummyButtonStyle: ButtonStyle {
    let fill: RGBA
    let label: RGBA
    var cornerRadius: CGFloat? = nil   // nil: a capsule
    /// DEBUG demos only: draw the pressed state without a finger (simctl can't tap).
    var forcePressed: Bool = false

    init(style: CaptionStyle, cornerRadius: CGFloat? = nil, forcePressed: Bool = false) {
        self.fill = style.text
        self.label = style.background
        self.cornerRadius = cornerRadius
        self.forcePressed = forcePressed
    }

    static let restingLip: CGFloat = 3
    static let pressedLip: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        GummyBody(configuration: configuration, fill: fill, label: label, cornerRadius: cornerRadius, forcePressed: forcePressed)
    }

    private struct GummyBody: View {
        let configuration: Configuration
        let fill: RGBA
        let label: RGBA
        let cornerRadius: CGFloat?
        let forcePressed: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed || forcePressed
            let sink = GummyButtonStyle.restingLip - GummyButtonStyle.pressedLip
            configuration.label
                .foregroundStyle(label.color)
                .background(shape.fill(fill.color))
                .offset(y: pressed ? sink : 0)
                .background(shape.fill(fill.gummyLip.color).offset(y: GummyButtonStyle.restingLip))
                .padding(.bottom, GummyButtonStyle.restingLip)
                .opacity(isEnabled ? 1 : 0.5)
                .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.55), value: pressed)
        }

        private var shape: AnyShape {
            if let cornerRadius { AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)) } else { AnyShape(Capsule()) }
        }
    }
}

import CaptionCore
import SwiftUI

/// Small icon buttons (gear, saved list, close, back) (#180): pressed, the icon dims and gives a little, then springs
/// back; on the Mac a soft round highlight shows on hover. Reduce Motion: the dim only, no give.
///
/// To adopt it: `.buttonStyle(PressableIconStyle(tint: iconColor))`.
public struct PressableIconStyle: ButtonStyle {
    let tint: Color
    let forcePressed: Bool
    let forceHover: Bool

    /// `forcePressed` / `forceHover`: DEBUG demos only, to draw the state without a finger or pointer.
    public init(tint: Color, forcePressed: Bool = false, forceHover: Bool = false) {
        self.tint = tint
        self.forcePressed = forcePressed
        self.forceHover = forceHover
    }

    public func makeBody(configuration: Configuration) -> some View {
        IconBody(label: configuration.label, pressed: configuration.isPressed || forcePressed, tint: tint, forceHover: forceHover)
    }

    private struct IconBody<Label: View>: View {
        let label: Label
        let pressed: Bool
        let tint: Color
        let forceHover: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let lit = hovering || forceHover
            label
                .background(Circle().fill(tint.opacity(lit ? PressFeedback.hoverOpacity : 0)).padding(2))
                .opacity(pressed ? PressFeedback.iconPressedOpacity : 1)
                .scaleEffect(pressed && !reduceMotion ? PressFeedback.iconScale : 1)
                .animation(PressFeedback.animation(reduceMotion), value: pressed)
                .animation(.easeOut(duration: 0.15), value: lit)
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// The Stop circle's press (#180): it darkens and gives a little. Reduce Motion: the darkening only.
    public func circlePress<S: Shape>(_ pressed: Bool, in shape: S) -> some View {
        modifier(CirclePress(pressed: pressed, shape: shape))
    }
}

private struct CirclePress<S: Shape>: ViewModifier {
    let pressed: Bool
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(shape.fill(.black.opacity(pressed ? PressFeedback.stopDarken : 0)))
            .scaleEffect(pressed && !reduceMotion ? PressFeedback.stopScale : 1)
            .animation(PressFeedback.animation(reduceMotion), value: pressed)
    }
}

extension PressFeedback {
    /// The press spring; Reduce Motion: a quick fade.
    static func animation(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: springResponse, dampingFraction: springDamping)
    }
}

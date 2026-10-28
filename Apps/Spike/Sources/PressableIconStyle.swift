import SwiftUI

/// Small icon buttons (gear, saved list, close, back) (#180): they answer a press instead of sitting flat. Pressed,
/// the icon dims and gives a little; let go, it springs back. On the Mac a soft round highlight shows on hover.
/// Reduce Motion: the dim only, no give.
struct PressableIconStyle: ButtonStyle {
    /// The icon's colour, for the hover highlight behind it.
    var tint: Color
    /// DEBUG demos only: draw the pressed / hovered state without a finger (simctl can't tap).
    var forcePressed = false
    var forceHover = false

    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration, tint: tint, forcePressed: forcePressed, forceHover: forceHover)
    }

    private struct IconBody: View {
        let configuration: Configuration
        let tint: Color
        let forcePressed: Bool
        let forceHover: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let pressed = configuration.isPressed || forcePressed
            configuration.label
                .background(Circle().fill(tint.opacity((hovering || forceHover) ? 0.12 : 0)).padding(2))
                .opacity(pressed ? 0.5 : 1)
                .scaleEffect(pressed && !reduceMotion ? 0.88 : 1)
                .animation(reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.22, dampingFraction: 0.55), value: pressed)
                .animation(.easeOut(duration: 0.15), value: hovering || forceHover)
                .onHover { hovering = $0 }
        }
    }
}

import CaptionCore
import SwiftUI

/// Debug only (-ClarityDemoAlive, #180 mock-up): the Listening light options side by side and the buttons pressing by
/// themselves (simctl can't tap), drawn with the real views on Paper (light) or Night (dark), following the system.
struct AliveDemoView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var roomLevel: Double = -50

    private var style: CaptionStyle {
        CaptionStyle.standard.applying(CaptionPreset.all.first { $0.id == (scheme == .dark ? "night" : "paper") }!)
    }

    var body: some View {
        let style = style
        VStack(alignment: .leading, spacing: 18) {
            heading("Listening light", style)
            lightRow("A  Gentle · 2.4 s", pulse: .gentle, style)
            lightRow("B  Steady · 1.4 s", pulse: .steady, style)
            lightRow("C  Follows the room", pulse: .room, style)
            lightRow("Reduce Motion", pulse: .gentle, style, still: true)

            heading("Buttons", style).padding(.top, 12)
            HStack(spacing: 24) {
                icon("gearshape", style, label: "Press")
                icon("list.bullet", style, label: "Press")
                icon("gearshape", style, label: "Mac hover", hover: true)
                Spacer()
                VStack(spacing: 6) {
                    MorphingControl(control: PrimaryControl.for(.listening), fullWidth: 200, fill: style.text,
                                    label: style.background, forcePressed: pressed) {}
                    caption("Stop", style)
                }
            }
            VStack(spacing: 6) {
                MorphingControl(control: PrimaryControl.for(.idle), fullWidth: 340, fill: style.text,
                                label: style.background, forcePressed: pressed) {}
                caption(pressed ? "Pressed" : "Resting", style)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 70)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(style.background.color)
        .ignoresSafeArea()
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
                pressed.toggle()
            }
        }
        .task {
            // A pretend room for option C: someone talks, pauses, talks louder.
            let levels: [Double] = [-50, -40, -34, -45, -55, -38, -31, -48]
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600_000_000)
                i = (i + 1) % levels.count
                withAnimation(.easeInOut(duration: 0.5)) { roomLevel = levels[i] }
            }
        }
    }

    private func heading(_ text: String, _ style: CaptionStyle) -> some View {
        Text(text).font(.title3.bold()).foregroundStyle(style.text.color)
    }

    private func caption(_ text: String, _ style: CaptionStyle) -> some View {
        Text(text).font(.footnote).foregroundStyle(style.text.color.opacity(0.6))
    }

    private func lightRow(_ name: String, pulse: ListeningLight.Pulse, _ style: CaptionStyle, still: Bool = false) -> some View {
        HStack {
            // The status line as the main screen draws it.
            HStack(spacing: 6) {
                ListeningLightView(background: style.background, pulse: pulse, roomLevelDBFS: roomLevel, forceReduceMotion: still)
                Text("Listening").font(.subheadline.weight(.semibold)).opacity(0.8)
            }
            .foregroundStyle(style.text.color)
            Spacer()
            caption(name, style)
        }
    }

    private func icon(_ name: String, _ style: CaptionStyle, label: String, hover: Bool = false) -> some View {
        VStack(spacing: 6) {
            Button {} label: {
                Image(systemName: name).font(.title2).foregroundStyle(style.gear.color).frame(width: 44, height: 44)
            }
            .buttonStyle(PressableIconStyle(tint: style.gear.color, forcePressed: !hover && pressed, forceHover: hover))
            caption(label, style)
        }
    }
}

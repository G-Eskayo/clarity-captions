import CaptionCore
import SwiftUI

/// MOCK-UP for #172, not wired UI: the call-captions pop-up drawn with fixed demo lines so Gil can choose between the
/// variants in the draft PR's Decisions before the real window is built. Reached only through the screenshot
/// contract (`-SealPopupMockup <variant>`); nothing in the running app shows it.
struct CallPopupMockup: View {
    enum Variant: String, CaseIterable {
        /// A: the window picks the call by itself; one button.
        case auto
        /// B: same, plus a two-way Call / Room switch.
        case sourceSwitch = "switch"
        /// The window before any call: waiting, nothing to read yet.
        case waiting
    }

    let variant: Variant
    let style: CaptionStyle

    private struct DemoLine: Identifiable {
        let id: Int
        let speaker: Int
        let name: String
        let text: String
        var volatile = false
    }

    private let lines = [
        DemoLine(id: 0, speaker: 0, name: "Dana", text: "Hi! Can you read me okay on the computer?"),
        DemoLine(id: 1, speaker: 1, name: "Sam", text: "We're all here, the kids want to say hello."),
        DemoLine(id: 2, speaker: 0, name: "Dana", text: "Sunday still works for dinner", volatile: true),
    ]

    private var speakerColors: [RGBA] { style.preset?.speakers ?? [style.text, style.text] }
    private var captionFont: Font { style.font(for: .large, scaled: 0.82) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if variant == .sourceSwitch { sourceSwitch.padding(.bottom, 6) }
            if variant == .waiting { waiting } else { captions }
            Button(action: {}) {
                Text(variant == .waiting ? "Start captions" : "Stop captions")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(GummyButtonStyle(style: style))
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .frame(width: 440, height: variant == .sourceSwitch ? 372 : 340)
        .background(style.background.color)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .environment(\.colorScheme, style.background.isDark ? .dark : .light)
    }

    private var topBar: some View {
        HStack {
            Image(systemName: "gearshape").font(.system(size: 17, weight: .regular)).foregroundStyle(style.gear.color)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(variant == .waiting ? style.text.color.opacity(0.35) : style.saved.color).frame(width: 7, height: 7)
                Text(variant == .waiting ? "Waiting for a FaceTime call" : "Captioning your FaceTime call")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(style.text.color.opacity(0.75))
            }
            Spacer()
            Image(systemName: "pin.fill").font(.system(size: 13)).foregroundStyle(style.gear.color.opacity(0.7))
                .help("Stays on top of other windows")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var sourceSwitch: some View {
        HStack(spacing: 0) {
            ForEach(["The call", "The room"], id: \.self) { label in
                let on = label == "The call"
                Text(label)
                    .font(.system(size: 14, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? style.background.color : style.text.color.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(on ? style.text.color : .clear))
            }
        }
        .padding(3)
        .background(Capsule().stroke(style.text.color.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 60)
    }

    private var captions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(speakerColors[line.speaker % speakerColors.count].color)
                    Text(line.text)
                        .font(captionFont)
                        .foregroundStyle(style.text.color.opacity(line.volatile ? style.volatileOpacity : 1))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var waiting: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "phone.bubble")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(style.gear.color)
            Text("Captions start when your call does.")
                .font(.system(size: 17))
                .foregroundStyle(style.text.color.opacity(0.85))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

import CaptionCore
import SwiftUI

/// Debug only (-ClarityDemoGummy): the Start button in style A on a light and a dark look, pressing and releasing by
/// itself so a screen recording can show the squish without a finger.
struct GummyDemoView: View {
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 0) {
            panel(CaptionStyle.standard.applying(CaptionPreset.all.first { $0.id == "paper" }!))
            panel(CaptionStyle.standard.applying(CaptionPreset.all.first { $0.id == "night" }!))
        }
        .ignoresSafeArea()
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                pressed.toggle()
            }
        }
    }

    private func panel(_ style: CaptionStyle) -> some View {
        VStack(spacing: 28) {
            Spacer()
            Button {} label: {
                Text("Start captions").font(.system(size: 21, weight: .heavy)).frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(GummyButtonStyle(style: style, forcePressed: pressed))
            Text(pressed ? "Pressed" : "Resting").font(.headline).foregroundStyle(style.text.color.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(style.background.color)
    }
}

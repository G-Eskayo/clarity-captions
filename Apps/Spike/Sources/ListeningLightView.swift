import CaptionCore
import SwiftUI

/// The Listening light (#180): an 8 pt red dot that breathes in colour, never in size. Reduce Motion: steady red.
struct ListeningLightView: View {
    let background: RGBA
    var pulse: ListeningLight.Pulse = DemoMode.pulse ?? .gentle
    var roomLevelDBFS: Double? = nil
    var size: CGFloat = 8
    /// DEBUG demos only: draw as if Reduce Motion were on.
    var forceReduceMotion = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var soft = false

    var body: some View {
        let red = ListeningLight.red(on: background).color
        let softRed = ListeningLight.soft(on: background, pulse: pulse).color
        let still = reduceMotion || forceReduceMotion
        Circle()
            .fill(fill(red: red, softRed: softRed, still: still))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .onAppear { breathe(still: still) }
            .onChange(of: still) { _, now in breathe(still: now) }
    }

    private func fill(red: Color, softRed: Color, still: Bool) -> Color {
        if still { return red }
        if pulse == .room {
            return softRed.mix(with: red, by: ListeningLight.brightness(roomLevelDBFS: roomLevelDBFS))
        }
        return soft ? softRed : red
    }

    private func breathe(still: Bool) {
        guard !still, let period = ListeningLight.period(pulse) else { soft = false; return }
        soft = false
        withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) { soft = true }
    }
}

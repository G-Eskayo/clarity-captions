import SwiftUI

struct LaunchAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isAnimating = false

    var body: some View {
        let compact = verticalSizeClass == .compact
        let size = compact ? 72.0 : 150.0

        Image("LaunchMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .scaleEffect(isAnimating ? 1.1 : 0.9)
            .opacity(isAnimating ? 1.0 : 0.7)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { if !reduceMotion { isAnimating = true } }
    }
}

#Preview {
    LaunchAnimationView()
}

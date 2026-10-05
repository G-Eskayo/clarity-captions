import CaptionCore
import SwiftUI

/// A calm, breathing brand mark animation for waiting moments (first-run setup, engine startup).
/// Reads system reduce-motion preference and presents accordingly: smooth breathing animation or static image.
struct BrandAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var presentation: BrandAnimationPresentation {
        BrandAnimationPresentation.for(reduceMotion: reduceMotion)
    }

    private var compact: Bool { verticalSizeClass == .compact }
    private var size: CGFloat { compact ? 72 : 150 }

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
                .modifier(BrandAnimationModifier(presentation: presentation))
        }
    }
}

private struct BrandAnimationModifier: ViewModifier {
    let presentation: BrandAnimationPresentation
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        switch presentation {
        case .animated:
            content
                .scaleEffect(isAnimating ? 1.0 : 0.95)
                .opacity(isAnimating ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isAnimating)
                .onAppear { isAnimating = true }
        case .calmStatic:
            content
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Animated")
        BrandAnimationView()
            .frame(height: 300)
    }
}

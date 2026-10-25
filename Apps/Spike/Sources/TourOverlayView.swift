import CaptionCore
import SwiftUI

/// A reference type for tracking where each tour target's control is on screen, by step.
/// Observable so view updates when frames change (e.g., after rotation or size-class change).
final class TourFrames: ObservableObject {
    @Published private var frames: [TourStep: CGRect] = [:]
    static let space = "tour-space"

    func set(_ frame: CGRect?, for step: TourStep) {
        if let frame {
            frames[step] = frame
        } else {
            frames.removeValue(forKey: step)
        }
    }

    func frame(for step: TourStep) -> CGRect? {
        frames[step]
    }
}

/// Track a control's on-screen frame in the tour frames registry.
/// Re-reads on every layout pass (rotation, size-class change, morphing) to keep the spotlight accurate.
extension View {
    func trackTourTarget(_ step: TourStep, in frames: TourFrames, space: CoordinateSpace = .named(TourFrames.space)) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: space) } action: { frame in
                        frames.set(frame, for: step)
                    }
                    .onDisappear {
                        frames.set(nil, for: step)
                    }
            }
        )
    }
}

/// A Shape that draws a full-screen scrim with an even-odd rounded-rect hole at the target.
/// When the target frame is nil, there is no hole (the control is off-screen).
struct SpotlightScrim: Shape {
    let targetFrame: CGRect?
    let cornerRadius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)

        if let target = targetFrame {
            let inset = target.insetBy(dx: -8, dy: -8)
            let rounded = RoundedRectangle(cornerRadius: cornerRadius)
            let hole = rounded.path(in: inset)
            path.addPath(hole)
        }

        return path
    }
}

/// The tour overlay: a scrim with a spotlight on the current target, a card with title/body/progress,
/// and always-visible Skip/Back/Next buttons. Callback-driven (read-only state) so ContentView owns
/// all state mutations and can guarantee `markSeen()` is called exactly once.
struct TourOverlayView: View {
    let state: TourState
    @ObservedObject var frames: TourFrames
    var onNext: () -> Void
    var onBack: () -> Void
    var onSkip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var step: TourStep { state.step }
    private var targetFrame: CGRect? { frames.frame(for: step) }

    private func scaled(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size), weight: weight)
    }

    var body: some View {
        ZStack {
            // Full-screen scrim with spotlight
            SpotlightScrim(targetFrame: targetFrame)
                .fill(Color.black.opacity(0.7), style: FillStyle(eoFill: true))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Card with narration
            VStack(spacing: 16) {
                // Progress dots
                HStack(spacing: 6) {
                    ForEach(TourStep.allCases, id: \.self) { s in
                        Circle()
                            .fill(s == step ? Color.white : Color.white.opacity(0.4))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 8)
                .accessibilityHidden(true)

                // Title and body
                let copy = TourCopy.for(step)
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.title)
                        .font(scaled(18, .bold))
                        .foregroundStyle(.black)
                    Text(copy.body)
                        .font(scaled(16))
                        .foregroundStyle(.black.opacity(0.8))
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .onAppear {
                    UIAccessibility.post(notification: .announcement, argument: "\(copy.title). \(copy.body)")
                }

                // Back, Next/Done buttons
                HStack(spacing: 12) {
                    if step != .start {
                        Button(action: onBack) {
                            Text(String(localized: "Back"))
                                .font(scaled(14, .semibold))
                                .frame(minHeight: 44)
                                .foregroundStyle(.white)
                        }
                    }

                    Spacer()

                    Button(action: onNext) {
                        Text(step == .gear ? String(localized: "Done ✓") : String(localized: "Next"))
                            .font(scaled(14, .semibold))
                            .frame(minHeight: 44)
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(20)
            .background(Color(red: 0.2, green: 0.2, blue: 0.2), in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: 320)
            .padding(20)

            // Top-right Skip button (always visible)
            VStack(alignment: .trailing) {
                Button(action: onSkip) {
                    Text(String(localized: "Skip tour"))
                        .font(scaled(13, .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 12)
                }
                .accessibilityLabel(String(localized: "Skip tour"))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(16)
        }
        .transition(.opacity)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: step)
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        VStack {
            Text(verbatim: "App content")
                .padding()
            Button(action: {}) {
                Text(verbatim: "Start")
            }
                .padding()
        }

        TourOverlayView(state: TourState(), frames: TourFrames(), onNext: {}, onBack: {}, onSkip: {})
    }
}

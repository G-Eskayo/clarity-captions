import CaptionCore
import SwiftUI

/// The real controls the tour can spotlight (#108). Each one marks itself with `.tourTarget(_:)`.
enum TourTarget: Hashable {
    case start, stop, save, new, captions, gear

    /// What a step spotlights. Save or New: [ Save ] if it's there, otherwise [ New ].
    static func candidates(for step: TourStep) -> [TourTarget] {
        switch step {
        case .start: [.start]
        case .captions, .copy: [.captions]
        case .pause: [.stop]
        case .saveOrNew: [.save, .new]
        case .gear: [.gear]
        }
    }
}

struct TourTargetKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks a real control so the tour can put its spotlight on it.
    func tourTarget(_ target: TourTarget) -> some View {
        anchorPreference(key: TourTargetKey.self, value: .bounds) { [target: $0] }
    }
}

/// Whether the launch animation still covers the main screen; the tour waits for it (#104, #108).
private struct LaunchCoveringKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var launchCovering: Bool {
        get { self[LaunchCoveringKey.self] }
        set { self[LaunchCoveringKey.self] = newValue }
    }
}

/// The tour on the real screen (mock-up 09): the screen dims, a spotlight sits on the real control, and a card says
/// what to do. The dim never takes touches, so she uses the real control itself; only the card and Skip tour do.
struct TourOverlay: View {
    let step: TourStep
    /// The real control to spotlight; nil when it isn't on screen (e.g. Next before Start, so there's no X yet).
    let holeAnchor: Anchor<CGRect>?
    let style: CaptionStyle
    let canGoBack: Bool
    let isLast: Bool
    let offersExample: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    let onExample: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var copy: TourCopy { TourCopy.for(step) }

    var body: some View {
        GeometryReader { geo in
            let spotlight = holeAnchor.map { geo[$0].insetBy(dx: -8, dy: -8) }
            ZStack(alignment: .topLeading) {
                dim(size: geo.size, spotlight: spotlight)
                if let spotlight {
                    RoundedRectangle(cornerRadius: corner(spotlight), style: .continuous)
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: spotlight.width, height: spotlight.height)
                        .offset(x: spotlight.minX, y: spotlight.minY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                skipButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, geo.safeAreaInsets.top + 4)
                    .padding(.trailing, 20)
                card
                    .frame(maxWidth: min(geo.size.width - 40, 440))
                    .frame(maxWidth: .infinity)
                    .alignmentGuide(.top) { _ in 0 }
                    .offset(y: cardY(in: geo, spotlight: spotlight))
                    .id(step)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.35), value: spotlight)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.35), value: step)
        }
        .ignoresSafeArea()
    }

    /// The dim with the spotlight cut out. It never takes touches.
    private func dim(size: CGSize, spotlight: CGRect?) -> some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
            if let spotlight { p.addRoundedRect(in: spotlight, cornerSize: CGSize(width: corner(spotlight), height: corner(spotlight))) }
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func corner(_ rect: CGRect) -> CGFloat { min(rect.height / 2, 22) }

    /// The card sits above a spotlight in the lower half of the screen and below one in the upper half.
    private func cardY(in geo: GeometryProxy, spotlight: CGRect?) -> CGFloat {
        let estimatedHeight: CGFloat = 190
        guard let spotlight else { return (geo.size.height - estimatedHeight) / 2 }
        if spotlight.midY > geo.size.height / 2 {
            return max(geo.safeAreaInsets.top + 52, spotlight.minY - 16 - estimatedHeight)
        }
        return min(spotlight.maxY + 16, geo.size.height - estimatedHeight - geo.safeAreaInsets.bottom)
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Text("Skip tour")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Ends the tour. You can take it again from Settings."))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.title)
                .font(.headline.weight(.heavy))
                .accessibilityAddTraits(.isHeader)
            Text(copy.message)
                .font(.subheadline)
                .opacity(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if offersExample {
                Button(action: onExample) {
                    Text("Too quiet? Show an example")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(style.gear.color)
                .transition(.opacity)
            }
            HStack(spacing: 4) {
                dots
                Spacer(minLength: 12)
                if canGoBack {
                    Button(action: onBack) { Text("‹ Back").frame(minHeight: 44).padding(.horizontal, 6) }
                        .accessibilityLabel(Text("Back"))
                }
                Button(action: onNext) {
                    Text(isLast ? "Done ✓" : "Next ›").frame(minHeight: 44).padding(.horizontal, 6)
                }
                .accessibilityLabel(isLast ? Text("Done") : Text("Next"))
            }
            .font(.subheadline.weight(.bold))
            .buttonStyle(.plain)
            .foregroundStyle(style.gear.color)
        }
        .foregroundStyle(style.text.color)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .background(style.background.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(10)
        .accessibilityAction(named: Text("Skip tour"), onSkip)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(TourStep.allCases, id: \.self) { s in
                Capsule()
                    .fill(style.gear.color.opacity(s == step ? 1 : 0.3))
                    .frame(width: s == step ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(TourStep.allCases.count)"))
    }
}

import CaptionCore
import SwiftUI

/// The real places the tour points at. Each one marks itself with `.tourTarget(_:)`.
struct TourTargetKey: PreferenceKey {
    static let defaultValue: [TourSpot: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourSpot: Anchor<CGRect>], nextValue: () -> [TourSpot: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks a real control or area so the tour can light it, or let touches through to it. It adds to the marks of
    /// anything inside it (the caption area holds [ Save ] and the dim), rather than replacing them.
    func tourTarget(_ spot: TourSpot) -> some View {
        transformAnchorPreference(key: TourTargetKey.self, value: .bounds) { marks, anchor in marks[spot] = anchor }
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

/// The tour v2 on the real screen (#121, round3/01-02): the words sit straight on the dim (no card), the lit control
/// gets a soft edge (no frame), and nothing but the lit control answers; touches anywhere else stop at the dim. Steps 5
/// and 6 use the pause dim and the captions themselves, so the tour lays no dim of its own there. Back and Skip tour are
/// on every step (no Back on the first); only the last step has [ Done ]. Everything only fades.
struct TourOverlay: View {
    let tour: HowToUseTour
    let anchors: [TourSpot: Anchor<CGRect>]
    let style: CaptionStyle
    let offersExample: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void
    let onExample: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focus: TourFocus { tour.focus }
    private var fade: Animation { .easeInOut(duration: reduceMotion ? 0.2 : 0.35) }

    var body: some View {
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            GeometryReader { geo in
                let lit = focus.lit.flatMap { anchors[$0] }.map { geo[$0].insetBy(dx: -8, dy: -8) }
                let hole = holeRect(in: geo)
                ZStack(alignment: .topLeading) {
                    if focus.dims { dim(size: geo.size, spotlight: lit) }
                    blocker(size: geo.size, hole: hole, stillBlocked: stillBlocked(in: geo))
                    if tour.showsWords {
                        words
                            .frame(maxWidth: min(geo.size.width - 48, 420))
                            .background { if !focus.dims || tour.step == .done { legibilityGlow } }
                            .position(x: geo.size.width / 2,
                                      y: wordsCenterY(height: geo.size.height, insets: insets, lit: lit,
                                                      newestWords: anchors[.captions].map { geo[$0] }))
                            .id(WordsID(step: tour.step, phase: tour.phase))
                            .transition(.opacity)
                    }
                    skipButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, insets.top + 4)
                        .padding(.trailing, 20)
                }
                .animation(fade, value: lit)
                .animation(fade, value: WordsID(step: tour.step, phase: tour.phase))
            }
            .ignoresSafeArea()
        }
    }

    private struct WordsID: Hashable {
        let step: TourStep?
        let phase: TourPhase
    }

    // MARK: the dim and what answers

    /// The theme's own background faded over the screen (like the pause dim), with the lit control cut out and a soft
    /// edge around it instead of a frame. Drawing only: touches are handled by the blocker.
    private func dim(size: CGSize, spotlight: CGRect?) -> some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
            if let spotlight { p.addRoundedRect(in: spotlight, cornerSize: CGSize(width: corner(spotlight), height: corner(spotlight))) }
        }
        // With nothing lit (the last step), the dim is deeper so the words never sit over faded buttons.
        .fill(style.background.color.opacity(spotlight == nil ? 0.95 : 0.86), style: FillStyle(eoFill: true))
        .overlay {
            if let spotlight {
                RoundedRectangle(cornerRadius: corner(spotlight), style: .continuous)
                    .fill(style.background.color.opacity(0.5))
                    .frame(width: spotlight.width + 12, height: spotlight.height + 12)
                    .position(x: spotlight.midX, y: spotlight.midY)
                    .blur(radius: 10)
                    .mask {
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: size))
                            p.addRoundedRect(in: spotlight, cornerSize: CGSize(width: corner(spotlight), height: corner(spotlight)))
                        }
                        .fill(style: FillStyle(eoFill: true))
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where touches get through: the answering control or area, or nowhere (waiting for a voice, the follow-ups, the
    /// last step), or everywhere (Settings, while step 7 waits for her to come back).
    private func holeRect(in geo: GeometryProxy) -> CGRect? {
        guard let answers = focus.answers, answers != .everything, let anchor = anchors[answers] else { return nil }
        return geo[anchor].insetBy(dx: -8, dy: -8)
    }

    /// Controls that sit inside a wide answering area but must not answer: Start floats over the captions' bottom, so
    /// on steps 5 and 6 (the dim, the empty space) a tap on it, on ✕ or on the gear still stops at the tour.
    private func stillBlocked(in geo: GeometryProxy) -> [CGRect] {
        guard focus.answers == .veil || focus.answers == .captionArea else { return [] }
        return [TourSpot.start, .stop, .gear, .save].compactMap { anchors[$0] }.map { geo[$0].insetBy(dx: -6, dy: -6) }
    }

    /// Stops every touch outside the hole, so only the lit control answers (round3/01: "Nothing else answers").
    @ViewBuilder
    private func blocker(size: CGSize, hole: CGRect?, stillBlocked: [CGRect]) -> some View {
        if focus.answers != .everything {
            Color.clear
                .contentShape(HoleShape(hole: hole, stillBlocked: stillBlocked), eoFill: true)
                .onTapGesture {}
                .onLongPressGesture(minimumDuration: 0.2) {}
                .accessibilityHidden(true)
        }
    }

    /// The whole screen, less the hole, plus the controls inside the hole that must still not answer (even-odd fill).
    private struct HoleShape: Shape {
        let hole: CGRect?
        let stillBlocked: [CGRect]
        func path(in rect: CGRect) -> Path {
            var p = Path(rect)
            if let hole {
                p.addRect(hole)
                for blocked in stillBlocked where blocked.intersects(hole) { p.addRect(blocked.intersection(hole)) }
            }
            return p
        }
    }

    /// A round control (✕, the gear) gets a round spotlight; a wide one gets rounded corners.
    private func corner(_ rect: CGRect) -> CGFloat {
        abs(rect.width - rect.height) < 6 ? rect.height / 2 : min(rect.height / 2, 22)
    }

    // MARK: the words

    private var words: some View {
        let w = tour.words
        return VStack(spacing: 10) {
            progressRow
            Text(w.title)
                .font(.title3.weight(.heavy))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(w.message)
                .font(.body)
                .multilineTextAlignment(.center)
                .opacity(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if offersExample && tour.step == .captions && tour.phase == .waiting {
                RetroWords(word: String(localized: "Show an example"), color: style.text.color,
                           background: style.background.color, size: .title3, label: String(localized: "Show an example"),
                           action: onExample)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
            if tour.hasDoneButton {
                RetroWords(word: String(localized: "Done"), color: style.text.color, background: style.background.color,
                           label: String(localized: "Done, end the tour"), action: onDone)
                    .padding(.top, 8)
            }
        }
        .foregroundStyle(style.text.color)
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(10)
        .accessibilityAction(named: Text("Skip tour"), onSkip)
    }

    /// "3 of 8 · ‹ Back" (no Back on the first step).
    private var progressRow: some View {
        HStack(spacing: 6) {
            Text(tour.progress)
            if tour.canGoBack {
                Text(verbatim: "·").accessibilityHidden(true)
                Button(action: onBack) {
                    Text("‹ Back").frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
            }
        }
        .font(.subheadline.weight(.bold))
        .opacity(0.7)
        .frame(minHeight: 44)
    }

    /// Where the tour lays no dim (steps 5, 6 and Settings), a soft wash of the theme's background behind the words
    /// keeps them readable over captions: no edge, no frame.
    private var legibilityGlow: some View {
        style.background.color
            .opacity(0.9)
            .padding(-34)
            .blur(radius: 30)
            .allowsHitTesting(false)
    }

    /// Next to the lit control (above it when it's low on the screen, as for Start and ✕), otherwise where the mock-up
    /// puts each step's words.
    private func wordsCenterY(height: CGFloat, insets: EdgeInsets, lit: CGRect?, newestWords: CGRect?) -> CGFloat {
        let half: CGFloat = tour.step == .done ? 150 : 75
        // "That's you.": just under her newest words (round3/01, "2, after").
        if tour.step == .captions, tour.phase == .followUp, let newestWords {
            return min(newestWords.maxY + 36 + half, height - insets.bottom - 110 - half)
        }
        // Start and ✕: right next to them. Elsewhere: where the mock-up puts the words.
        if let lit, tour.step == .start || tour.step == .pause {
            let below = lit.maxY + 20 + half
            if below + half <= height - insets.bottom - 110 { return below }
            return max(insets.top + 70 + half, lit.minY - 20 - half)
        }
        let fraction: CGFloat
        switch (tour.step, tour.phase) {
        case (.captions?, .followUp): fraction = 0.56   // just under her words (round3/01, "2, after")
        case (.captions?, _): fraction = 0.45
        case (.gear?, .inSettings): fraction = 0.92   // out of Settings' way, at the bottom
        case (.save?, _), (.clearDim?, _), (.gear?, _): fraction = 0.75   // below [ Save ] / [ New ]
        case (.holdBack?, _): fraction = 0.64
        case (.done?, _), (.start?, _), (.pause?, _), (nil, _): fraction = 0.52
        }
        // Settings has no Start pill at the bottom, so the words can sit right down there, clear of its rows.
        if tour.step == .gear, tour.phase == .inSettings { return height - insets.bottom - 16 - half }
        return min(height * fraction, height - insets.bottom - 110 - half)
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Text("Skip tour")
                .font(.headline)
                .foregroundStyle(style.text.color)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Ends the tour. You can take it again from Settings."))
    }
}

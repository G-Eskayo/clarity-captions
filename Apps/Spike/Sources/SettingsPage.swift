import CaptionCore
import SwiftUI

/// Settings as approved in design #96 (image 08), on the one screen since round 2 (#118, mock-up round2/01): no
/// sheet, no Done. Tapping the gear fades the captions out and Settings in on the same background; the gear, still
/// exactly where it was, takes her back. Its own pages (saved conversations, credits, the beta preview) fade in the
/// same way. No borders or boxes, one thin line between sections.
struct SettingsPage: View {
    @Binding var style: CaptionStyle
    @Binding var idleStop: IdleStopSetting
    let store: SavedConversationStoring?
    /// "Show how to use Seal" (#108): replays the tour back on the captions. Not while captioning: the tour walks her
    /// through starting.
    var canShowTour: Bool = true
    var onShowTour: (() -> Void)?
    /// The gear: back to the captions.
    let onGear: () -> Void
    /// Opens one of Settings' own pages.
    let onOpen: (AppScreen) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var savedCount: Int?
    /// Beta installs only (ADR 0023): the "Test version" section.
    @ObservedObject private var beta = BetaFeedbackCenter.shared

    private var showsTourReplay: Bool { onShowTour != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        preview
                        section("Colors", first: true) { colorsRow }
                        section("Size") { sizeRow }
                        section("Lettering", note: String(localized: "OpenDyslexic was made for people with dyslexia. Atkinson Hyperlegible was designed by the Braille Institute for low vision.")) { letteringRows }
                            .id("lettering")
                        section("Stop when it's quiet") { idleStopRow }.id("idleStop")
                        section("Saved", note: String(localized: "Saved conversations are deleted after 30 days.")) { savedRow }.id("saved")
                        if beta.isOn { testVersionSection.id("betaFeedback") }
                        if showsTourReplay { section("How to use Seal") { tourRow }.id("tour") }
                        section("About") { aboutRows }.id("about")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                    .foregroundStyle(style.text.color)
                }
                .onAppear { if let id = DemoMode.settingsSection { proxy.scrollTo(id, anchor: .top) } }
                // The Test version section appears once StoreKit has answered, after Settings may already be open.
                .onChange(of: beta.isOn) { if let id = DemoMode.settingsSection { proxy.scrollTo(id, anchor: .top) } }
                .task {
                    // Debug flow for the screen recording: scroll to Test version, then open the preview (ADR 0023).
                    guard DemoMode.flow == "feedback" else { return }
                    try? await Task.sleep(for: .seconds(1))
                    withAnimation { proxy.scrollTo("betaFeedback", anchor: .center) }
                    try? await Task.sleep(for: .seconds(2))
                    onOpen(.feedbackPreview)
                }
            }
        }
        .tint(style.gear.color)
        .task { savedCount = try? await store?.all().count }
    }

    // MARK: pieces

    /// A size from the mock-up (drawn at the default text size), scaled with the iPhone's text-size setting.
    private func scaled(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size), weight: weight)
    }

    private var muted: Color { (style.background.isDark ? RGBA(hex: "#B9B3A6") : RGBA(hex: "#56625F")).color }
    private var rule: Color { style.background.isDark ? Color(red: 236 / 255, green: 230 / 255, blue: 217 / 255).opacity(0.16) : Color(red: 20 / 255, green: 20 / 255, blue: 25 / 255).opacity(0.12) }
    private var softFill: Color { style.background.isDark ? Color(red: 236 / 255, green: 230 / 255, blue: 217 / 255).opacity(0.10) : Color(red: 20 / 255, green: 20 / 255, blue: 25 / 255).opacity(0.07) }

    /// Mock-up round2/01 frame 4: the gear stays exactly where it was (lightly highlighted) and "Settings" sits in the
    /// middle of the same row.
    private var header: some View {
        ZStack {
            Text("Settings")
                .font(scaled(20, .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onGear) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundStyle(style.gear.color)
                        .frame(width: 44, height: 44)
                        .background(softFill, in: Circle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Back to captions"))
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    private var preview: some View {
        Text("Preview: Let's book a table for seven.")
            .font(style.font(for: SystemTextSizeCategory(dynamicTypeSize)))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .accessibilityLabel("Preview of caption text")
    }

    private func section<C: View>(_ title: LocalizedStringKey, first: Bool = false, note: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(scaled(14, .heavy))
                .tracking(0.6)
                .foregroundStyle(muted)
                .accessibilityAddTraits(.isHeader)
            content()
            if let note {
                Text(note).font(scaled(13)).foregroundStyle(muted).lineSpacing(2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { if !first { Rectangle().fill(rule).frame(height: 1) } }
    }

    private var colorsRow: some View {
        HStack(alignment: .top) {
            ForEach(CaptionPreset.all) { preset in
                let selected = style.preset?.id == preset.id
                Button { style = style.applying(preset) } label: {
                    VStack(spacing: 5) {
                        Text("Aa")
                            .font(.system(size: 17, weight: .heavy))   // fixed: it sits in a fixed 46-pt swatch
                            .foregroundStyle(preset.text.color)
                            .frame(width: 46, height: 46)
                            .background(preset.background.color, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        Text(preset.name).font(scaled(11, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "checkmark")
                            .font(scaled(13, .heavy))
                            .foregroundStyle(style.gear.color)
                            .frame(height: 16)
                            .opacity(selected ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name + (selected ? String(localized: ", selected") : ""))
            }
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 16) {
            sizeButton("A−", points: 22, label: "Smaller text", disabled: style.size == .smallest) { style.size = style.size.smaller() }
            sizeButton("A+", points: 26, label: "Larger text", disabled: style.size == .largest) { style.size = style.size.larger() }
        }
    }

    private func sizeButton(_ title: String, points: CGFloat, label: LocalizedStringKey, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(scaled(points, .heavy))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(softFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(label)
    }

    private var letteringRows: some View {
        VStack(spacing: 0) {
            ForEach(CaptionFont.allCases, id: \.self) { f in
                let selected = style.font == f
                Button { style.font = f } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(f.label).font(f.sample(size: UIFontMetrics.default.scaledValue(for: 18)))
                        if f == .openDyslexic {
                            Text("· default").font(scaled(12, .bold)).foregroundStyle(muted)
                        }
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(scaled(18, .heavy))
                            .foregroundStyle(style.gear.color)
                            .opacity(selected ? 1 : 0)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(f.label + (f == .openDyslexic ? String(localized: ", default") : "") + (selected ? String(localized: ", selected") : ""))
            }
        }
    }

    /// ADR 0019: the one behavior setting. The screen stays on while captioning; this caps a forgotten session.
    private var idleStopRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { idleStopChoices }
            VStack(alignment: .leading, spacing: 8) { idleStopChoices }
        }
    }

    @ViewBuilder private var idleStopChoices: some View {
            ForEach(IdleStopSetting.allCases, id: \.self) { option in
                let selected = idleStop == option
                Button { idleStop = option } label: {
                    Text(option.shortTitle)
                        .font(scaled(15, .bold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.vertical, 9)
                        .padding(.horizontal, 14)
                        .foregroundStyle(selected ? style.background.color : style.text.color)
                        .background(selected ? style.text.color : softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title + (selected ? String(localized: ", selected") : ""))
            }
    }

    @ViewBuilder private var savedRow: some View {
        let row = HStack {
            Text("Saved conversations").fontWeight(.semibold)
            Spacer()
            Text(savedCount.map { "\($0) ›" } ?? "›").foregroundStyle(muted)
        }
        .contentShape(Rectangle())
        if store != nil {
            Button { onOpen(.saved) } label: { row }.buttonStyle(.plain)
        } else {
            row.opacity(0.5)
        }
    }

    /// Mock-up 03: TestFlight installs only, between Saved and How to use Seal.
    private var testVersionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Test version")
                    .font(scaled(14, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(muted)
                    .accessibilityAddTraits(.isHeader)
                Text("TestFlight only")
                    .font(scaled(12, .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background((style.background.isDark ? RGBA(hex: "#1F6F6B") : RGBA(hex: "#4FB3A9")).color, in: Capsule())
            }
            Button { onOpen(.feedbackPreview) } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Send feedback to Gil").font(scaled(18, .heavy)).foregroundStyle(style.gear.color)
                    Spacer()
                    Text(String(format: String(localized: "%lld conversations"), beta.unsentCount) + " ›")
                        .foregroundStyle(muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(beta.unsentCount == 0)
            Text("Your ratings and notes, plus measurements like lag and battery. Never what anyone said.")
                .font(scaled(13)).foregroundStyle(muted).lineSpacing(2)
        }
        .padding(.horizontal, 4)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(rule).frame(height: 1) }
    }

    private var tourRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { onShowTour?() } label: {
                Text("Show how to use Seal")
                    .font(scaled(17, .heavy))
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(GummyButtonStyle(style: style))
            .disabled(!canShowTour)
            .opacity(canShowTour ? 1 : 0.5)
            if !canShowTour {
                Text("Pause captions first, then come back here.")
                    .font(scaled(13))
                    .foregroundStyle(muted)
            }
        }
    }

    private var aboutRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Guideline 5.1.1(i): the privacy policy must be reachable from inside the app. Both open in Safari.
            Link("Privacy policy", destination: SupportLinks.privacyPolicy)
                .accessibilityHint(Text("Opens in Safari"))
                .padding(.vertical, 7)
            Link("Help and contact", destination: SupportLinks.support)
                .accessibilityHint(Text("Opens in Safari"))
                .padding(.vertical, 7)
            Button("Credits") { onOpen(.credits) }
                .buttonStyle(.plain)
                .padding(.vertical, 7)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(style.gear.color)
    }
}

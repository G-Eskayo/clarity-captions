import CaptionCore
import SwiftUI

/// Settings as approved in design #96 (image 08): no borders or boxes, one thin line between sections, everything on
/// the look's own background so it feels like the same screen. Colors, size, lettering, quiet stop, saved
/// conversations and About; a live preview on top.
struct SettingsSheet: View {
    @Binding var style: CaptionStyle
    @Binding var idleStop: IdleStopSetting
    // Kept so the call site in ContentView doesn't change while #102 reworks it; the Conversation section that used
    // them is gone (#103: highlight-and-copy covers it).
    let stream: CaptionStream
    let speakerNames: SpeakerNames
    let store: SavedConversationStoring?
    /// "Show how to use Seal" (#108): replays the tour once Settings closes. Not while captioning: the tour walks her
    /// through starting.
    var canShowTour: Bool = true
    var onShowTour: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var savedCount: Int?

    private var showsTourReplay: Bool { onShowTour != nil }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        preview
                        section("Colors", first: true) { colorsRow }
                        section("Size") { sizeRow }
                        section("Lettering", note: String(localized: "OpenDyslexic was made for people with dyslexia. Atkinson Hyperlegible was designed by the Braille Institute for low vision.")) { letteringRows }
                            .id("lettering")
                        section("Stop when it's quiet") { idleStopRow }.id("idleStop")
                        section("Saved", note: String(localized: "Saved conversations are deleted after 30 days.")) { savedRow }.id("saved")
                        if showsTourReplay { section("How to use Seal") { tourRow }.id("tour") }
                        section("About") { aboutRows }.id("about")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                    .foregroundStyle(style.text.color)
                }
                .onAppear { if let id = DemoMode.settingsSection { proxy.scrollTo(id, anchor: .top) } }
            }
            .containerBackground(style.background.color, for: .navigation)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(style.gear.color)
        .preferredColorScheme(style.background.isDark ? .dark : .light)
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

    private var header: some View {
        HStack {
            Text("Settings").font(scaled(24, .heavy)).lineLimit(1).minimumScaleFactor(0.5)
            Spacer()
            Button("Done") { dismiss() }
                .font(.body.weight(.bold))
                .foregroundStyle(style.gear.color)
        }
        .padding(.top, 26)
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
        if let store {
            NavigationLink(destination: SavedConversationsView(store: store)) { row }.buttonStyle(.plain)
        } else {
            row.opacity(0.5)
        }
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
            NavigationLink("Credits", destination: AboutCreditsView())
                .padding(.vertical, 7)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(style.gear.color)
    }
}

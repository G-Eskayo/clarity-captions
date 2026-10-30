import CaptionCore
import CaptionUI
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
    /// #37 / #53: caption language and translation, at the bottom of Settings just above About (owner, PR #171 decisions).
    var language: LanguageSettingsState = .current()
    var onChooseCaptionLanguage: (() -> Void)?
    var onTranslation: ((Bool) -> Void)?
    var onChooseTranslationTarget: (() -> Void)?
    /// #213, the Mac: the calls' From row.
    var onChooseCallLanguage: (() -> Void)?
    /// The translation purchase (#53): StoreKit is wired with the feature; the mock-up only shows the two states.
    var onBuyTranslation: (() -> Void)?
    var onRestorePurchases: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Beta installs only (ADR 0023): the "Test version" section.
    @ObservedObject private var beta = BetaFeedbackCenter.shared

    private var showsTourReplay: Bool { onShowTour != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // No Saved section: saved conversations live at the top right of the captions, one tap away, and
                        // two ways in felt redundant (owner, 2026-10-20, #139).
                        // Translation is a one-time purchase (owner, #171): bought or not, it keeps this one place at the
                        // top, with the same shape, so buying it changes what's in the space, never the layout. It sits
                        // above the sample so the sample and the buttons that change it stay together (owner, #171).
                        section("Translate captions", first: true, note: language.translationOwned ? translationNote : translationOfferNote) { translationRows }
                            .id("translation")
                        preview
                            .overlay(alignment: .top) { Rectangle().fill(rule).frame(height: 1) }
                        section("Colors", first: true) { colorsRow }
                        section("Size") { sizeRow }
                        section("Lettering", note: String(localized: "OpenDyslexic was made for people with dyslexia. Atkinson Hyperlegible was designed by the Braille Institute for low vision.")) { letteringRows }
                            .id("lettering")
                        section("Stop when it's quiet") { idleStopRow }.id("idleStop")
                        if beta.isOn { testVersionSection.id("betaFeedback") }
                        if showsTourReplay { section("How to use Seal") { tourRow }.id("tour") }
                        section("Caption language", note: String(localized: "Seal captions the language people are speaking. Change it when you're somewhere they speak another language.")) {
                            captionLanguageRow
                            CaptionLanguageDownloadLine(style: style, phase: language.captionDownload)
                        }
                        .id("language")
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
                        // Icon only, in the theme's gear color, never a background (owner's rule, #96); the title says
                        // this is Settings.
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableIconStyle(tint: style.gear.color))
                .accessibilityLabel(String(localized: "Back to captions"))
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    /// A live sample drawn exactly as a caption looks on the main screen (#137: "displays exactly as it will when it
    /// closes out of Settings"): a heading saying what it is, then a speaker label and words. No border or box.
    private var preview: some View {
        let palette = SpeakerPalette.colors(on: style.background, text: style.text).map(\.color)
        return VStack(alignment: .leading, spacing: 8) {
            Text("How your captions will look")
                .font(.footnote.weight(.heavy))
                .textCase(.uppercase)
                .opacity(0.7)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Speaker 1"))
                    .font(.headline)
                    .foregroundStyle(palette[0])
                let original = LanguageSettingsState.sample(language.captions) ?? String(localized: "Let's book a table for seven.")
                if language.translationOn, let target = language.target, let line = LanguageSettingsState.sample(target) {
                    translatedLine(line)
                    originalUnderTranslation(original)
                } else {
                    Text(original)
                        .font(style.font(for: SystemTextSizeCategory(dynamicTypeSize)))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Sample caption: Speaker 1, Let's book a table for seven."))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    /// #53 (owner, PR #171 decisions): the translation is the line that gets read, so it sits on top at caption size,
    /// behind a translate mark so nobody takes it for what was said. The original stays, smaller, underneath.
    private func translatedLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "translate").font(scaled(15, .bold)).foregroundStyle(muted)
            Text(text).font(style.font(for: SystemTextSizeCategory(dynamicTypeSize)))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Translated: ") + text)
    }

    private func originalUnderTranslation(_ text: String) -> some View {
        Text(text)
            .font(scaled(17))
            .foregroundStyle(muted)
            .padding(.top, 2)
            .accessibilityLabel(String(localized: "Said: ") + text)
    }

    private var captionLanguageRow: some View {
        Button { onChooseCaptionLanguage?() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(LanguageSettingsState.name(language.captions)).font(scaled(18, .heavy))
                if language.followsDevice {
                    Text(String(format: String(localized: "· matches this %@"), LanguageSettingsState.deviceWord))
                        .font(scaled(12, .bold)).foregroundStyle(muted)
                }
                Spacer()
                Text(verbatim: "›").font(scaled(20, .heavy)).foregroundStyle(muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Caption language, ") + LanguageSettingsState.name(language.captions))
    }

    @ViewBuilder private var translationRows: some View {
        if language.translationOwned { ownedTranslationRows } else { translationOfferRows }
        if let message = language.purchaseMessage {
            Text(verbatim: message).font(scaled(13, .semibold)).foregroundStyle(muted)
        }
    }

    /// Not bought yet: the same pill row the bought section starts with, so the section keeps its size.
    private var translationOfferRows: some View {
        HStack(spacing: 8) {
            offerPill(language.translationPrice.map { String(format: String(localized: "Unlock · %@"), $0) } ?? String(localized: "Unlock"),
                      filled: true) { onBuyTranslation?() }
            offerPill(String(localized: "Restore purchase"), filled: false) { onRestorePurchases?() }
        }
        .disabled(language.purchaseBusy)
        .opacity(language.purchaseBusy ? 0.6 : 1)
    }

    private func offerPill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(scaled(15, .bold))
                .padding(.vertical, 9)
                .padding(.horizontal, 18)
                .foregroundStyle(filled ? style.background.color : style.text.color)
                .background(filled ? style.text.color : softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var ownedTranslationRows: some View {
        HStack(spacing: 8) {
            ForEach([false, true], id: \.self) { on in
                let selected = language.translationOn == on
                Button { onTranslation?(on) } label: {
                    Text(on ? String(localized: "On") : String(localized: "Off"))
                        .font(scaled(15, .bold))
                        .padding(.vertical, 9)
                        .padding(.horizontal, 18)
                        .foregroundStyle(selected ? style.background.color : style.text.color)
                        .background(selected ? style.text.color : softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel((on ? String(localized: "Translation on") : String(localized: "Translation off")) + (selected ? String(localized: ", selected") : ""))
            }
        }
        if language.translationOn {
            // From is the caption language: the same setting as "Caption language" below, opening the same list. Apple's
            // speech engine needs it named before it starts (it doesn't detect it), so it's chosen, right next to Into.
            if let call = language.callCaptions {
                // #213, the Mac: the room and the calls each have their own From, since Apple's engine can't tell
                // which language it hears (E27). Only the other people's words on a call are translated (owner, #213).
                languagePairRow(String(localized: "Room"), LanguageSettingsState.name(language.captions),
                                label: String(localized: "Translate the room from, ")) { onChooseCaptionLanguage?() }
                languagePairRow(String(localized: "Calls"), LanguageSettingsState.name(call),
                                label: String(localized: "Translate calls from, ")) { onChooseCallLanguage?() }
            } else {
                languagePairRow(String(localized: "From"), LanguageSettingsState.name(language.captions),
                                label: String(localized: "Translate from, ")) { onChooseCaptionLanguage?() }
            }
            languagePairRow(String(localized: "Into"), language.target.map(LanguageSettingsState.name) ?? String(localized: "Choose a language"),
                            label: String(localized: "Translate into, ")) { onChooseTranslationTarget?() }
            if let p = language.downloadProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: p).tint(style.gear.color)
                    Text(String(format: String(localized: "Downloading the language pack · %lld%%"), Int(p * 100)))
                        .font(scaled(13, .semibold)).foregroundStyle(muted)
                }
            } else if language.translationPreparing {
                // Apple's own download sheet runs this one and reports no progress (#159).
                HStack(spacing: 8) {
                    ProgressView().tint(style.gear.color)
                    Text(String(localized: "Getting the language pack ready…")).font(scaled(13, .semibold)).foregroundStyle(muted)
                }
            }
            if language.unsupportedPair {
                Text(String(format: String(localized: "%@ can't be translated into %@ yet. Captions still show what was said."),
                            LanguageSettingsState.name(language.captions), language.target.map(LanguageSettingsState.name) ?? ""))
                    .font(scaled(13, .semibold)).foregroundStyle(muted)
            }
        }
    }

    /// "From  Spanish (Spain)  ›" and "Into  English (US)  ›": the words line up so the pair reads as one sentence.
    private func languagePairRow(_ word: String, _ value: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: word).font(scaled(15, .bold)).foregroundStyle(muted)
                    .frame(minWidth: UIFontMetrics.default.scaledValue(for: 44), alignment: .leading)
                Text(verbatim: value).font(scaled(18, .heavy))
                Spacer()
                Text(verbatim: "›").font(scaled(20, .heavy)).foregroundStyle(muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label + value)
    }

    private var translationOfferNote: String {
        String(format: String(localized: "Read what people say in your own language, translated on this %@ with no internet. Each caption shows its translation on top, with what was said underneath. One-time purchase."), LanguageSettingsState.deviceWord)
    }

    private var translationNote: String {
        if language.callCaptions != nil {
            return String(localized: "Room is the language people near your Mac speak; Calls is what the other people on your calls speak. On a call only their words are translated, not yours. Each caption shows its translation on top, with what was said in smaller text underneath.")
        }
        return String(localized: "From is the language people around you speak. Each caption shows its translation on top, with what was said in smaller text underneath. The first time, the language pack downloads once (about 200 MB); after that it works with no internet.")
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

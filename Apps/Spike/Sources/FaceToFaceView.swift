import CaptionCore
import Speech
import SwiftUI
import Translation

/// #60: the face-to-face split on iPad and the unfolded iPhone Duo. The owner's half is at the bottom, facing
/// her; the other person's half is at the top, turned 180° to face them. A short line across the middle, well short
/// of both edges, divides them (owner, 2026-10-29). Each half shows its own speaker's words as said and the other
/// person's words translated, translation on top behind the translate mark, what was said smaller underneath (#171).
struct FaceToFaceView<Control: View>: View {
    let style: CaptionStyle
    let device: CaptionDeviceClass
    let owner: [FaceToFaceEntry]
    let partner: [FaceToFaceEntry]
    /// Each half's language, named in that language: the one its list picked (#208).
    let ownerLanguage: String
    let partnerLanguage: String
    /// #208: a half that hasn't picked its language (or is picking again) shows the stacked, dimmed list of downloaded
    /// languages instead of its lines; nil once it has picked. Tapping one starts that half.
    var ownerChoices: [String]? = nil
    var partnerChoices: [String]? = nil
    var choose: (FaceToFaceHalf, Int) -> Void = { _, _ in }
    /// The language name at the middle line, tapped: that half's list again (the owner's `change-language`).
    var pickAgain: (FaceToFaceHalf) -> Void = { _ in }
    /// Start / Stop, in the owner's half only. Stop is the only way out of the split (owner, 2026-10-29).
    @ViewBuilder let control: () -> Control

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Each half follows its newest line. The default bottom anchor alone stopped following in her half after Start in
    /// the paused split (#208, seen on the iPad simulator).
    @State private var ownerScroll = ScrollPosition(edge: .bottom)
    @State private var partnerScroll = ScrollPosition(edge: .bottom)

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                half(partner, language: partnerLanguage, choices: partnerChoices, isOwner: false)
                    .rotationEffect(.degrees(180))
                    .accessibilityLabel(String(localized: "The other person's half"))
                Capsule()
                    .fill(mutedColor(style).opacity(0.6))
                    .frame(width: geo.size.width * 0.4, height: 3)
                    .padding(.vertical, 10)
                    .accessibilityHidden(true)
                half(owner, language: ownerLanguage, choices: ownerChoices, isOwner: true)
                    .overlay(alignment: .bottom) { control().frame(height: 72) }
            }
        }
    }

    @ViewBuilder
    private func half(_ entries: [FaceToFaceEntry], language: String, choices: [String]?, isOwner: Bool) -> some View {
        if let choices { picker(choices, isOwner: isOwner) }
        else { lines(entries, language: language, isOwner: isOwner, position: isOwner ? $ownerScroll : $partnerScroll) }
    }

    /// #208: the half's languages stacked in the middle of the half, dimmed until one is tapped. Above Stop in her half.
    private func picker(_ choices: [String], isOwner: Bool) -> some View {
        VStack(spacing: 18) {
            ForEach(Array(choices.enumerated()), id: \.offset) { i, name in
                RetroWords(word: name, color: mutedColor(style), background: style.background.color, size: .title,
                           label: name) { choose(isOwner ? .owner : .partner, i) }
            }
        }
        .padding(.bottom, isOwner ? 72 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Choose your language"))
    }

    private func lines(_ entries: [FaceToFaceEntry], language: String, isOwner: Bool, position: Binding<ScrollPosition>) -> some View {
        VStack(spacing: 4) {
            // From each reader's own side, the top of their half is the middle of the screen. Tap it to pick again.
            Button { pickAgain(isOwner ? .owner : .partner) } label: {
                Text(language).font(.subheadline.weight(.semibold)).foregroundStyle(mutedColor(style))
                    .frame(minWidth: 88, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "Pick another language"))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(entries) { entry in line(entry) }
                }
                .padding(.horizontal, 8)
            }
            .scrollPosition(position)
            .defaultScrollAnchor(.bottom)
            .onChange(of: entries) { _, _ in position.wrappedValue.scrollTo(edge: .bottom) }
            .contentMargins(.bottom, isOwner ? 72 + 12 : 12, for: .scrollContent)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 24)
                    Rectangle()
                }
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func line(_ entry: FaceToFaceEntry) -> some View {
        let font = style.font(for: SystemTextSizeCategory(dynamicTypeSize), device: device)
        VStack(alignment: .leading, spacing: 2) {
            if let said = entry.said {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "translate").font(.subheadline.bold()).foregroundStyle(mutedColor(style))
                    Text(entry.text).font(font)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Translated: ") + entry.text)
                Text(said).font(.body).foregroundStyle(mutedColor(style))
                    .accessibilityLabel(String(localized: "Said: ") + said)
            } else {
                Text(entry.text).font(entry.isSoundLabel ? font.italic() : font)
                    .opacity(entry.isFinal ? 1 : style.volatileOpacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// #208: the languages each half's list offers on this device (`FaceToFace.offered`). Debug demos use stand-ins: the
/// simulator has no Translation languages.
enum FaceToFaceLanguageList {
    @MainActor static func load() async -> [Locale] {
        #if DEBUG
        if DemoMode.isOn { return DemoMode.faceToFaceDownloaded }
        #endif
        let installed = Array(await SpeechTranscriber.installedLocales)
        let translatable = Set(await LanguageAvailability().supportedLanguages.compactMap { $0.languageCode?.identifier })
        return FaceToFace.offered(captionLanguage: CaptionLanguageCenter.engineLocale, into: TranslationCenter.shared.target,
                                        speechInstalled: installed, translatable: translatable)
    }
}

extension Locale {
    /// A language's name in that language ("Español", "English"), for the split's halves.
    var nameInItself: String {
        let id = identifier
        let name = Locale(identifier: id).localizedString(forLanguageCode: language.languageCode?.identifier ?? id) ?? id
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

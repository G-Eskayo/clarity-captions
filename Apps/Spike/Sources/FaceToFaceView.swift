import CaptionCore
import SwiftUI

/// #60: the face-to-face split on iPad and the unfolded iPhone Duo. The owner's half is at the bottom, facing
/// her; the other person's half is at the top, turned 180° to face them. A short line across the middle, well short
/// of both edges, divides them (owner, 2026-10-29). Each half shows its own speaker's words as said and the other
/// person's words translated, translation on top behind the translate mark, what was said smaller underneath (#171).
struct FaceToFaceView<Control: View>: View {
    let style: CaptionStyle
    let device: CaptionDeviceClass
    let owner: [FaceToFaceEntry]
    let partner: [FaceToFaceEntry]
    /// Each half's language, named in that language (the owner's Into, the other person's From).
    let ownerLanguage: String
    let partnerLanguage: String
    /// Start / Stop, in the owner's half only. Stop is the only way out of the split (owner, 2026-10-29).
    @ViewBuilder let control: () -> Control

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                half(partner, language: partnerLanguage, isOwner: false)
                    .rotationEffect(.degrees(180))
                    .accessibilityLabel(String(localized: "The other person's half"))
                Capsule()
                    .fill(mutedColor(style).opacity(0.6))
                    .frame(width: geo.size.width * 0.4, height: 3)
                    .padding(.vertical, 10)
                    .accessibilityHidden(true)
                half(owner, language: ownerLanguage, isOwner: true)
                    .overlay(alignment: .bottom) { control().frame(height: 72) }
            }
        }
    }

    private func half(_ entries: [FaceToFaceEntry], language: String, isOwner: Bool) -> some View {
        VStack(spacing: 4) {
            // From each reader's own side, the top of their half is the middle of the screen.
            Text(language).font(.subheadline.weight(.semibold)).foregroundStyle(mutedColor(style))
                .frame(minHeight: 44)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(entries) { entry in line(entry) }
                }
                .padding(.horizontal, 8)
            }
            .defaultScrollAnchor(.bottom)
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

extension Locale {
    /// A language's name in that language ("Español", "English"), for the split's halves.
    var nameInItself: String {
        let id = identifier
        let name = Locale(identifier: id).localizedString(forLanguageCode: language.languageCode?.identifier ?? id) ?? id
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

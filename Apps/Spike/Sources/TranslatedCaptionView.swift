import CaptionCore
import SwiftUI

/// #246 mock-up: one translated caption in one of the options (`TranslatedCaptionLook`), the same view on the iPhone,
/// in the face-to-face split and on the Mac, so each option is compared as it would really draw. Reached only through
/// debug demo flags (`-ClarityDemoTranslatedLook`, the Mac's `-SealTranslatedLook`) until the owner picks one.
struct TranslatedCaptionView: View {
    let look: TranslatedCaptionLook
    let translated: String
    let said: String
    /// The language of what was said, as an identifier ("es-ES"), for option B's tag.
    let saidLanguage: String?
    /// While the voice says this line (#233): how many of the translation's words it has said. Nil otherwise.
    var speakingFirm: Int? = nil
    let font: Font
    var saidFont: Font = .body
    let text: Color
    let muted: Color
    /// The gear's colour: the speaker mark's colour today (#238).
    let mark: Color
    let volatileOpacity: Double
    /// Option C: what was said starts opened (the screenshot shows one opened line).
    var startsOpen = false

    @State private var opened: Bool?

    private var isOpen: Bool { opened ?? startsOpen }
    private var speaking: Bool { speakingFirm != nil }

    var body: some View {
        Group {
            switch look {
            case .today: today
            case .bar: bar
            case .tag: tag
            case .folded: folded
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityWords)
    }

    // MARK: today (#171, #238)

    private var today: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: speaking ? "speaker.wave.2.fill" : "translate").font(.subheadline.bold())
                    .foregroundStyle(speaking ? mark : muted)
                translation.font(font)
            }
            saidText
        }
    }

    // MARK: A, the bar

    private var bar: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule().fill(speaking ? mark : muted.opacity(0.45)).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                translation.font(font)
                saidText
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: B, the language tag

    private var tag: some View {
        VStack(alignment: .leading, spacing: 4) {
            translation.font(font)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HStack(spacing: 3) {
                    if speaking { Image(systemName: "speaker.wave.2.fill") }
                    Text(verbatim: saidLanguage.flatMap(TranslatedCaptionLook.languageTag) ?? "")
                }
                .font(.caption.weight(.heavy))
                .foregroundStyle(speaking ? mark : muted)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background((speaking ? mark : muted).opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                saidText
            }
        }
    }

    // MARK: C, folded

    private var folded: some View {
        VStack(alignment: .leading, spacing: 2) {
            let glyph = Text(Image(systemName: speaking ? "speaker.wave.2.fill" : "translate"))
                .font(.footnote.bold()).foregroundColor(speaking ? mark : muted)
            Text("\(translation)  \(glyph)").font(font)
            if look.showsSaid(opened: isOpen) { saidText.transition(.opacity) }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { opened = !isOpen } }
    }

    // MARK: parts

    /// The translation, its said words at full strength and the rest at the volatile strength while the voice says it.
    private var translation: Text {
        guard let firm = speakingFirm else { return Text(verbatim: translated) }
        let words = translated.split(separator: " ").map(String.init)
        let said = Text(verbatim: words.prefix(firm).joined(separator: " ") + (firm > 0 ? " " : ""))
        let rest = Text(verbatim: words.dropFirst(firm).joined(separator: " ")).foregroundColor(text.opacity(volatileOpacity))
        return Text("\(said)\(rest)")
    }

    private var saidText: some View {
        Text(verbatim: said).font(saidFont).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
    }

    private var accessibilityWords: String {
        let lead = speaking ? String(localized: "Speaking in your ear: ") : String(localized: "Translated: ")
        return lead + translated + (look.showsSaid(opened: isOpen) ? ". " + String(localized: "Said: ") + said : "")
    }
}

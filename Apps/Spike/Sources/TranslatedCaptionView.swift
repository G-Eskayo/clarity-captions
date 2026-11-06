import CaptionCore
import SwiftUI

/// #246: translated caption, the owner's chosen option C (folded), with the translation text and a trailing speaker/translate glyph
/// at caption size. "What was said" shows only when tapped, toggling between opened and closed states.
struct TranslatedCaptionView: View {
    let translated: String
    let said: String
    /// While the voice says this line (#233): how many of the translation's words it has said. Nil otherwise.
    var speakingFirm: Int? = nil
    let font: Font
    var saidFont: Font = .body
    let text: Color
    let muted: Color
    /// The gear's colour: the speaker mark's colour when speaking (#238).
    let mark: Color
    let volatileOpacity: Double
    /// What was said starts opened (the screenshot shows one opened line).
    var startsOpen = false

    @State private var opened: Bool?

    private var isOpen: Bool { opened ?? startsOpen }
    private var speaking: Bool { speakingFirm != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let glyph = Text(Image(systemName: speaking ? "speaker.wave.2.fill" : "translate"))
                .font(.footnote.bold()).foregroundStyle(speaking ? mark : muted)
            HStack(spacing: 2) {
                translation
                glyph
            }
            .font(font)
            if isOpen { saidText.transition(.opacity) }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { opened = !isOpen } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityWords)
    }

    /// The translation, its said words at full strength and the rest at the volatile strength while the voice says it.
    private var translation: Text {
        guard let firm = speakingFirm else { return Text(verbatim: translated) }
        let words = translated.split(separator: " ").map(String.init)
        let said = Text(verbatim: words.prefix(firm).joined(separator: " ") + (firm > 0 ? " " : ""))
        let rest = Text(verbatim: words.dropFirst(firm).joined(separator: " ")).foregroundStyle(text.opacity(volatileOpacity))
        return Text("\(said)\(rest)")
    }

    private var saidText: some View {
        Text(verbatim: said).font(saidFont).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
    }

    private var accessibilityWords: String {
        let lead = speaking ? String(localized: "Speaking in your ear: ") : String(localized: "Translated: ")
        return lead + translated + (isOpen ? ". " + String(localized: "Said: ") + said : "")
    }
}

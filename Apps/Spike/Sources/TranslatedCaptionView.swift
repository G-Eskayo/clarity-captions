import CaptionCore
import SwiftUI

/// #246 (owner, PR #255: look C, "Folded"): one translated caption, the same view on the iPhone, in the face-to-face
/// split and on the Mac. Just the translation, with a small mark after its last word: the translate mark, or the
/// speaker mark in the gear's colour while the voice says the line (#233). A tap on the line shows what was said
/// underneath; another tap hides it. Which lines are open lives with the list (`SaidFold`), so it survives scrolling.
struct TranslatedCaptionView<Said: View>: View {
    let translated: String
    /// While the voice says this line (#233): how many of the translation's words it has said. Nil otherwise.
    var speakingFirm: Int? = nil
    let font: Font
    let text: Color
    let muted: Color
    /// The gear's colour: the speaker mark's colour (#238).
    let mark: Color
    let volatileOpacity: Double
    /// Whether what was said shows underneath.
    let isOpen: Bool
    let onTap: () -> Void
    /// What was said, drawn by the caller (the iPhone's carries its selection renderer, #107).
    @ViewBuilder let said: () -> Said

    private var speaking: Bool { speakingFirm != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let glyph = Text(Image(systemName: speaking ? "speaker.wave.2.fill" : "translate"))
                .font(.footnote.bold()).foregroundColor(speaking ? mark : muted)
            Text("\(translation)  \(glyph)").font(font)
                .accessibilityLabel((speaking ? String(localized: "Speaking in your ear: ") : String(localized: "Translated: ")) + translated)
                .accessibilityHint(isOpen ? String(localized: "Hides what was said") : String(localized: "Shows what was said"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggle() }
            if isOpen { said().transition(.opacity) }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
    }

    private func toggle() { withAnimation(.easeOut(duration: 0.2)) { onTap() } }

    /// The translation, its said words at full strength and the rest at the volatile strength while the voice says it.
    private var translation: Text {
        guard let firm = speakingFirm else { return Text(verbatim: translated) }
        let words = translated.split(separator: " ").map(String.init)
        let said = Text(verbatim: words.prefix(firm).joined(separator: " ") + (firm > 0 ? " " : ""))
        let rest = Text(verbatim: words.dropFirst(firm).joined(separator: " ")).foregroundColor(text.opacity(volatileOpacity))
        return Text("\(said)\(rest)")
    }
}

extension TranslatedCaptionView where Said == SaidText {
    /// What was said as plain smaller text in the muted colour (the split, the Mac).
    init(translated: String, said: String, speakingFirm: Int? = nil, font: Font, saidFont: Font = .body, text: Color,
         muted: Color, mark: Color, volatileOpacity: Double, isOpen: Bool, onTap: @escaping () -> Void) {
        self.init(translated: translated, speakingFirm: speakingFirm, font: font, text: text, muted: muted, mark: mark,
                  volatileOpacity: volatileOpacity, isOpen: isOpen, onTap: onTap) {
            SaidText(said: said, font: saidFont, color: muted)
        }
    }
}

/// What was said under an opened translated line.
struct SaidText: View {
    let said: String
    let font: Font
    let color: Color

    var body: some View {
        Text(verbatim: said).font(font).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(String(localized: "Said: ") + said)
    }
}

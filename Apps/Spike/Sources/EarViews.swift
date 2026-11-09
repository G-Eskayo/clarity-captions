import CaptionCore
import SwiftUI

/// The translated line the voice is saying (#233, "screen" A on #238): a speaker mark in the gear's colour in place of
/// the translate mark, the words already said at full strength and the rest at the caption's volatile strength, so the
/// eye can follow the voice.
struct EarSpeakingLine: View {
    let translated: String
    /// How many of the shown words the voice has said (EarProgress).
    let firm: Int
    let font: Font
    let mark: Color
    let text: Color
    let volatileOpacity: Double

    var body: some View {
        let words = translated.split(separator: " ").map(String.init)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "speaker.wave.2.fill").font(.subheadline.bold()).foregroundStyle(mark)
            let said = Text(verbatim: words.prefix(firm).joined(separator: " ") + (firm > 0 ? " " : ""))
            let rest = Text(verbatim: words.dropFirst(firm).joined(separator: " ")).foregroundColor(text.opacity(volatileOpacity))
            Text("\(said)\(rest)").font(font)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Speaking in your ear: ") + translated)
    }
}

/// Settings, under Into ("turnon" A): Speak it in my ear, Off or On, in the same pills as Translate captions, and a
/// note that says what it's doing: no headphones (it never uses the iPhone's speaker), or no voice for the language.
/// Under it, once it's on and has a voice, Sound like the speaker (#247, PR #254 "setting" B), the same way.
struct EarSettingsRows: View {
    let style: CaptionStyle
    let state: EarState
    var match: EarMatchState = .off
    let target: String
    let font: (CGFloat, Font.Weight) -> Font
    let muted: Color
    let softFill: Color
    let onChange: (Bool) -> Void
    var onMatch: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Speak it in my ear")).font(font(15, .bold)).foregroundStyle(muted)
            HStack(spacing: 8) {
                pill(false)
                pill(true)
            }
            Text(note).font(font(13, .semibold)).foregroundStyle(muted)
            if state != .off && state != .noVoice {
                Text(String(localized: "Sound like the speaker")).font(font(15, .bold)).foregroundStyle(muted)
                    .padding(.top, 8)
                HStack(spacing: 8) {
                    matchPill(false)
                    matchPill(true)
                }
                Text(matchNote).font(font(13, .semibold)).foregroundStyle(muted)
            }
        }
    }

    private var matchNote: String {
        switch match {
        case .oneVoice:
            String(format: String(localized: "Into %1$@, everyone gets the same voice on this %2$@ for now."), target,
                   LanguageSettingsState.deviceWord)
        case .off, .matching:
            String(localized: "Each person gets their own voice, near their pitch and pace. Someone new starts in the usual voice for a moment.")
        }
    }

    private func matchPill(_ on: Bool) -> some View {
        let selected = (match != .off) == on
        return pillLabel(on, selected: selected) { onMatch(on) }
            .accessibilityLabel((on ? String(localized: "Sound like the speaker on") : String(localized: "Sound like the speaker off"))
                                + (selected ? String(localized: ", selected") : ""))
    }

    private func pillLabel(_ on: Bool, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(on ? String(localized: "On") : String(localized: "Off"))
                .font(font(15, .bold))
                .padding(.vertical, 9)
                .padding(.horizontal, 18)
                .foregroundStyle(selected ? style.background.color : style.text.color)
                .background(selected ? style.text.color : softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var note: String {
        switch state {
        case .noHeadphones:
            String(format: String(localized: "Connect headphones to hear it. Seal never speaks through the %@'s speaker; captions carry on."),
                   LanguageSettingsState.deviceWord)
        case .noVoice:
            String(format: String(localized: "%1$@ has no voice on this %2$@ yet: captions only."), target, LanguageSettingsState.deviceWord)
        case .off, .speaking:
            String(format: String(localized: "The translation is spoken into your headphones as people talk, any kind. The %@'s own mic keeps listening."),
                   LanguageSettingsState.deviceWord)
        }
    }

    private func pill(_ on: Bool) -> some View {
        let selected = (state != .off) == on
        return pillLabel(on, selected: selected) { onChange(on) }
        .accessibilityLabel((on ? String(localized: "Speak it in my ear on") : String(localized: "Speak it in my ear off"))
                            + (selected ? String(localized: ", selected") : ""))
    }
}

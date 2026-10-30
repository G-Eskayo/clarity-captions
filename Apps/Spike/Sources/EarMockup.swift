#if DEBUG
import CaptionCore
import SwiftUI

/// Live Translation in your ear, mock-up only (#233): debug builds, `-ClarityDemoEar <variant>`, nothing wired to audio.
/// Each variant is one option in the PR's Decisions; none ships until the owner picks.
///   mark        the line being spoken: a speaker mark in place of the translate mark, its words firming up as they're said
///   pill        the line keeps its translate mark; a small "Speaking in your AirPods" pill sits under Listening
///   button      an ear button on the caption screen (the other way to turn it on), shown on
///   settings    Settings: a "Speak it in my ear" On/Off row under Into
///   noheadphones  Settings, on, with no headphones connected
///   novoice     Settings, on, into a language with no voice on this iPhone (Serbian)
enum EarMockup: String {
    case mark, pill, button, settings, noheadphones, novoice

    static var current: EarMockup? { DemoMode.ear.flatMap(EarMockup.init(rawValue:)) }
    static var showsSettingsRow: Bool { [.settings, .noheadphones, .novoice].contains(current) }
    /// The share of the spoken line already said, for the `mark` still.
    static let spokenShare = 0.55
}

/// The translated line the app is speaking: a speaker mark in the gear's colour, the words already said at full
/// strength and the rest at the caption's volatile strength, so the eye can follow the voice.
struct EarSpeakingLine: View {
    let translated: String
    let font: Font
    let mark: Color
    let text: Color
    let volatileOpacity: Double

    var body: some View {
        let words = translated.split(separator: " ").map(String.init)
        let said = Int((Double(words.count) * EarMockup.spokenShare).rounded())
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "speaker.wave.2.fill").font(.subheadline.bold()).foregroundStyle(mark)
            (Text(words.prefix(said).joined(separator: " ") + " ")
                + Text(words.dropFirst(said).joined(separator: " ")).foregroundColor(text.opacity(volatileOpacity)))
                .font(font)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Speaking in your ear: ") + translated)
    }
}

/// Under the status word: where the voice is going.
struct EarStatusPill: View {
    let style: CaptionStyle

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "airpods").font(.footnote.bold())
            Text(String(localized: "Speaking in your AirPods")).font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .foregroundStyle(style.background.color)
        .background(style.gear.color, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// The caption screen's own switch: an ear, filled while it speaks.
struct EarButton: View {
    let style: CaptionStyle
    let on: Bool

    var body: some View {
        Image(systemName: on ? "ear.fill" : "ear")
            .font(.system(size: 26, weight: .bold))
            .frame(width: 64, height: 64)
            .foregroundStyle(on ? style.background.color : style.gear.color)
            .background(on ? style.gear.color : style.gear.color.opacity(0.14), in: Circle())
            .accessibilityLabel(on ? String(localized: "Speaking in your ear, on") : String(localized: "Speak in your ear"))
    }
}

/// Settings, under Into: the On/Off row and its note, in the same pills as Translate captions.
struct EarSettingsRows: View {
    let style: CaptionStyle
    let target: String
    let font: (CGFloat, Font.Weight) -> Font
    let muted: Color
    let softFill: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Speak it in my ear")).font(font(15, .bold)).foregroundStyle(muted)
            HStack(spacing: 8) {
                pill(String(localized: "Off"), selected: false)
                pill(String(localized: "On"), selected: true)
            }
            Text(note).font(font(13, .semibold)).foregroundStyle(muted)
        }
    }

    private var note: String {
        switch EarMockup.current {
        case .noheadphones:
            String(localized: "Connect headphones to hear it. Seal never speaks through the iPhone's speaker; captions carry on.")
        case .novoice:
            String(format: String(localized: "%@ has no voice on this iPhone yet: captions only."), target)
        default:
            String(localized: "Each finished line is spoken into your headphones, any kind. The iPhone's own mic keeps listening.")
        }
    }

    private func pill(_ title: String, selected: Bool) -> some View {
        Text(verbatim: title)
            .font(font(15, .bold))
            .padding(.vertical, 9)
            .padding(.horizontal, 18)
            .foregroundStyle(selected ? style.background.color : style.text.color)
            .background(selected ? style.text.color : softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
#endif

import CaptionCore
import SwiftUI

// Round 2 (#118, design #117): pieces shared by every page of the one screen. No boxes, no borders, fades only.

/// How long each half of a page change takes: the current page fades out, then the next fades in (spec "Round 2").
enum PageFade {
    static func half(reduceMotion: Bool) -> Double { reduceMotion ? 0.15 : 0.25 }
}

/// The retro, literal-text words: [ Save ], [ New ], [ Start new ], [ Keep it ], [ Delete all ]. A nil action shows
/// the state only, as plain text: a disabled button is dimmed, and [ Saved ] must stay solid green. Each sits on a
/// plain patch of the theme's own background so faded words never show through the letters (no outline).
struct RetroWords: View {
    let word: String
    let color: Color
    let background: Color
    var size: Font.TextStyle = .title
    let label: String
    let action: (() -> Void)?

    var body: some View {
        // The brackets are the retro frame, not words; the word inside is already localized.
        let text = Text(verbatim: "[ \(word) ]")
            .font(.system(size, design: .monospaced).bold())
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(background)
            .contentShape(Rectangle())
            .contentTransition(.opacity)
        if let action {
            Button(action: action) { text }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
        } else {
            text.accessibilityLabel(label)
        }
    }
}

/// The red of a destructive answer ([ Delete all ] in mock-up round2/02), readable on light and dark themes.
enum DestructiveRed {
    static func color(on background: RGBA) -> Color {
        (background.isDark ? RGBA(hex: "#FF8A80") : RGBA(hex: "#A8261B")).color
    }
}

/// A page's top row (mock-up round2/02): "‹ Settings" on the left in the gear's color, the title centered. No bar,
/// no background.
struct PageHeader: View {
    let style: CaptionStyle
    let title: String
    let backTitle: String
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.title3.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 96)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onBack) {
                    Text(verbatim: "‹ \(backTitle)")
                        .font(.body.weight(.bold))
                        .foregroundStyle(style.gear.color)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(format: String(localized: "Back to %@"), backTitle)))
                Spacer()
            }
        }
        .frame(minHeight: 44)
    }
}

/// A question asked in place in retro words (mock-up round2/02 frame 2, round2/03): a bold line, a plain line, and
/// the two answers. Everything sits on the theme's background; nothing is boxed.
struct InPlaceQuestionView: View {
    let style: CaptionStyle
    let title: String
    let message: String
    let yes: String
    let yesIsDestructive: Bool
    let no: String
    var stacked: Bool = false
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.title3.weight(.heavy))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .background(style.background.color)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .opacity(0.8)
                .padding(.horizontal, 6)
                .background(style.background.color)
            let answers = Group {
                RetroWords(word: yes, color: yesIsDestructive ? DestructiveRed.color(on: style.background) : style.text.color,
                           background: style.background.color, size: stacked ? .title : .title2, label: yes, action: onYes)
                RetroWords(word: no, color: style.text.color, background: style.background.color,
                           size: stacked ? .title : .title2, label: no, action: onNo)
            }
            if stacked {
                VStack(spacing: 18) { answers }.padding(.top, 8)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { answers }
                    VStack(spacing: 12) { answers }
                }
                .padding(.top, 4)
            }
        }
        .foregroundStyle(style.text.color)
        .accessibilityElement(children: .contain)
    }
}

/// One thin line between rows or sections (the only separator round 2 allows).
struct ThinRule: View {
    let style: CaptionStyle
    var body: some View {
        Rectangle()
            .fill(style.background.isDark ? Color(red: 236 / 255, green: 230 / 255, blue: 217 / 255).opacity(0.16)
                                          : Color(red: 20 / 255, green: 20 / 255, blue: 25 / 255).opacity(0.12))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Muted secondary text, readable on every theme (the Settings mock-up's grey).
func mutedColor(_ style: CaptionStyle) -> Color {
    (style.background.isDark ? RGBA(hex: "#B9B3A6") : RGBA(hex: "#56625F")).color
}

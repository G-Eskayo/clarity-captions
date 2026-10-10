import CaptionCore
import SwiftUI

/// Third-party credits on the one screen, as approved in #120 (mock-up round3/04): a short intro, then a name and one
/// line per entry with one thin line between them, and the full license texts one tap further. No boxes, no links per
/// entry; every bundled work is credited in full on the license page (CreditsEntry, tested).
struct CreditsPage: View {
    let style: CaptionStyle
    let onBack: () -> Void
    let onLicenseText: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(style: style, title: String(localized: "Credits"), backTitle: String(localized: "Settings"), onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(CreditsEntry.intro)
                        .font(.body)
                        .foregroundStyle(mutedColor(style))
                        .padding(.top, 18)
                        .padding(.bottom, 10)
                    ForEach(Array(CreditsEntry.all.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { ThinRule(style: style) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: entry.name).font(.headline.weight(.heavy))
                            Text(entry.line).font(.subheadline).foregroundStyle(mutedColor(style))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                    }
                    ThinRule(style: style)
                    // The complete license texts ship inside the app, so they can be read with no network.
                    Button(action: onLicenseText) {
                        Text(verbatim: String(localized: "Full license texts") + " ›")
                            .font(.body.weight(.bold))
                            .foregroundStyle(style.gear.color)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 40)
            }
        }
        .foregroundStyle(style.text.color)
    }
}

/// The repository's NOTICE.md, bundled into the app as a resource.
struct LicenseTextPage: View {
    let style: CaptionStyle
    let onBack: () -> Void
    private let text: String = {
        guard let url = Bundle.main.url(forResource: "NOTICE", withExtension: "md"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "The license text could not be loaded from this build."
        }
        return contents
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(style: style, title: String(localized: "License text"), backTitle: String(localized: "Credits"), onBack: onBack)
            ScrollView {
                Text(text)
                    .font(.footnote.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 18)
                    .textSelection(.enabled)
            }
        }
        .foregroundStyle(style.text.color)
    }
}

import CaptionCore
import SwiftUI

/// Third-party credits, on the one screen (#118; #117 "credits": the same borderless style as the saved list, fading
/// in on the same screen). Plain blocks with one thin line between them; no grey boxes, no system bar.
struct CreditsPage: View {
    let style: CaptionStyle
    let onBack: () -> Void
    let onLicenseText: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(style: style, title: String(localized: "Credits"), backTitle: String(localized: "Settings"), onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("This app uses the following third-party libraries and models.")
                        .font(.body)
                        .foregroundStyle(mutedColor(style))
                        .padding(.top, 18)
                        .padding(.bottom, 14)
                    ForEach(ThirdPartyNotice.all) { notice in
                        ThinRule(style: style)
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(notice.name).font(.headline.weight(.heavy))
                                Text(notice.licenseName).font(.footnote).foregroundStyle(mutedColor(style))
                            }
                            Text(notice.note).font(.subheadline).foregroundStyle(mutedColor(style))
                            HStack(spacing: 20) {
                                Link("View license", destination: notice.licenseURL)
                                if let source = notice.sourceURL { Link("View source", destination: source) }
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(style.gear.color)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                    }
                    ThinRule(style: style)
                    // The complete license text ships inside the app, so it can be read with no network.
                    Button(action: onLicenseText) {
                        Text(verbatim: String(localized: "Full license text") + " ›")
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

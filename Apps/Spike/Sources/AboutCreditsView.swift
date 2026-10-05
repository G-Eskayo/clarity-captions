import CaptionCore
import SwiftUI

/// Third-party credits. Reached from Settings (pushed onto its navigation stack, so it has none of its own).
struct AboutCreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("This app uses the following third-party libraries and models.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                ForEach(ThirdPartyNotice.all) { notice in
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notice.name).font(.headline)
                            Text(notice.licenseName).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(notice.note).font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing: 20) {
                            Link("View license", destination: notice.licenseURL)
                            if let source = notice.sourceURL { Link("View source", destination: source) }
                        }
                        .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }

                // The complete license text ships inside the app, so it can be read with no network.
                NavigationLink {
                    FullLicenseTextView()
                } label: {
                    Label("Full license text", systemImage: "doc.text")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The repository's NOTICE.md, bundled into the app as a resource.
struct FullLicenseTextView: View {
    private let text: String = {
        guard let url = Bundle.main.url(forResource: "NOTICE", withExtension: "md"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "The license text could not be loaded from this build."
        }
        return contents
    }()

    var body: some View {
        ScrollView {
            Text(text)
                .font(.footnote.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle("License text")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AboutCreditsView() }
}

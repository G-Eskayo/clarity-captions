import CaptionCore
import SwiftUI

struct AboutCreditsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This app uses the following third-party libraries and models.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ThirdPartyNotice.all) { notice in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(notice.name)
                                            .font(.headline)
                                        Text(notice.licenseName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.forward")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(notice.note)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Link("View license", destination: notice.licenseURL)
                                    .font(.subheadline)
                                    .foregroundStyle(.tint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AboutCreditsView()
}

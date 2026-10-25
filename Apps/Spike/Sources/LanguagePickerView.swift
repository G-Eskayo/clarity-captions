import CaptionCore
import SwiftUI

struct LanguagePickerView: View {
    @State private var languages: [(identifier: String, displayName: String, tier: LanguageTier)] = []
    @State private var downloadSizes: [String: Int64?] = [:]
    @State private var isLoading = true
    @State private var problem: String?
    @State private var installingLocale: String?
    @State private var installProgress = 0.0
    let onLanguageSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let problem {
                VStack(spacing: 16) {
                    Text(problem).font(.headline).foregroundStyle(.red).multilineTextAlignment(.center)
                    Button("Try again") { load() }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                List {
                    ForEach(languages, id: \.identifier) { lang in
                        LanguageRow(
                            identifier: lang.identifier,
                            displayName: lang.displayName,
                            tier: lang.tier,
                            downloadSize: downloadSizes[lang.identifier] ?? nil,
                            isInstalling: installingLocale == lang.identifier,
                            installProgress: installProgress,
                            onSelect: selectLanguage
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await load() }
    }

    private func load() {
        Task {
            isLoading = true
            problem = nil
            do {
                let locales = await SpeechModelInstaller.supportedLocaleIdentifiers()
                languages = locales.map { id in
                    let displayName = Locale(identifier: id).localizedString(forIdentifier: id) ?? id
                    let tier = AppLocalizationTier.tier(for: id)
                    return (id, displayName, tier)
                }.sorted { $0.displayName < $1.displayName }

                for lang in languages {
                    downloadSizes[lang.identifier] = try await SpeechModelInstaller.pendingDownloadSize(locale: Locale(identifier: lang.identifier))
                }
            } catch {
                problem = "Couldn't load languages. Check your connection and try again."
            }
            isLoading = false
        }
    }

    private func selectLanguage(_ identifier: String) {
        Task {
            installingLocale = identifier
            installProgress = 0
            problem = nil
            do {
                try await SpeechModelInstaller.install(locale: Locale(identifier: identifier)) { progress in
                    Task { @MainActor in installProgress = progress }
                }
                LanguageStore().selectedLocaleIdentifier = identifier
                onLanguageSelected(identifier)
            } catch {
                problem = "Download failed. Check Wi-Fi and try again."
                installingLocale = nil
            }
        }
    }
}

private struct LanguageRow: View {
    let identifier: String
    let displayName: String
    let tier: LanguageTier
    let downloadSize: Int64?
    let isInstalling: Bool
    let installProgress: Double
    let onSelect: (String) -> Void

    var body: some View {
        Button(action: { if !isInstalling { onSelect(identifier) } }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(displayName).font(.body).foregroundStyle(.primary)
                        tierBadge
                    }
                    if isInstalling {
                        ProgressView(value: installProgress).frame(maxHeight: 4)
                    } else if downloadSize != nil {
                        Text(BytesFormatter.format(downloadSize)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .disabled(isInstalling)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var tierBadge: some View {
        switch tier {
        case .full:
            EmptyView()
        case .beta:
            Text("Beta").font(.caption).foregroundStyle(.orange).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange.opacity(0.2), in: Capsule())
        case .untranslated:
            Text("App menus stay in English").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.gray.opacity(0.1), in: Capsule())
        }
    }
}

import CaptionCore
import SwiftUI

struct LanguagePickerView: View {
    @State private var supportedLocales: [String] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedLocale: String?
    @State private var isInstalling = false
    @State private var installProgress = 0.0
    @State private var installError: String?
    @State private var downloadSizes: [String: Int64?] = [:]
    @Environment(\.dismiss) private var dismiss
    var onLanguageSelected: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if supportedLocales.isEmpty {
                    Text("No languages available").foregroundStyle(.secondary)
                } else {
                    searchableList
                }
            }
            .navigationTitle("Choose Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.font(.headline) } }
            if let error = installError {
                VStack(spacing: 12) {
                    Text(error).font(.headline).foregroundStyle(.red).multilineTextAlignment(.center)
                    Button(action: { installError = nil; isInstalling = false }) {
                        Text("Try again").frame(maxWidth: .infinity).padding(12).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white)
                    }
                }
                .padding()
            }
        }
        .task { await loadSupportedLocales() }
    }

    private var searchableList: some View {
        List {
            ForEach(filteredLocales, id: \.self) { locale in
                languageRow(for: locale)
            }
        }
        .searchable(text: $searchText, prompt: "Search languages")
    }

    private func languageRow(for localeIdentifier: String) -> some View {
        let displayName = Locale.current.localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier
        let isTranslated = AppLocalizationCatalog.isTranslated(localeIdentifier: localeIdentifier)
        let isSelected = selectedLocale == localeIdentifier
        let downloadSize = downloadSizes[localeIdentifier]

        return Button(action: { handleLanguageSelection(localeIdentifier) }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(displayName).font(.body)
                        if !isTranslated {
                            Text("Not fully translated").font(.caption).foregroundStyle(.secondary)
                        }
                        if let size = downloadSize {
                            Text(BytesFormatter.format(bytes: size)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if isInstalling && selectedLocale == localeIdentifier {
                        ProgressView(value: installProgress)
                            .frame(height: 4)
                    }
                }
                Spacer()
                if isSelected && !isInstalling {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(.accentColor)
        .task { await loadDownloadSize(for: localeIdentifier) }
    }

    private func handleLanguageSelection(_ localeIdentifier: String) {
        selectedLocale = localeIdentifier
        Task {
            isInstalling = true
            installError = nil
            do {
                let locale = Locale(identifier: localeIdentifier)
                try await SpeechModelInstaller.install(locale: locale) { progress in
                    Task { @MainActor in installProgress = progress }
                }
                await MainActor.run {
                    onLanguageSelected(localeIdentifier)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    installError = "Could not download the language model. Check your connection and try again."
                    isInstalling = false
                }
            }
        }
    }

    private var filteredLocales: [String] {
        if searchText.isEmpty {
            return supportedLocales
        }
        return supportedLocales.filter { localeID in
            let displayName = Locale.current.localizedString(forIdentifier: localeID) ?? localeID
            return displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func loadSupportedLocales() async {
        supportedLocales = await SpeechModelInstaller.supportedLocaleIdentifiers()
        isLoading = false
    }

    private func loadDownloadSize(for localeIdentifier: String) async {
        guard downloadSizes[localeIdentifier] == nil else { return }
        let locale = Locale(identifier: localeIdentifier)
        do {
            let size = try await SpeechModelInstaller.pendingDownloadSize(locale: locale)
            await MainActor.run { downloadSizes[localeIdentifier] = size }
        } catch {
            await MainActor.run { downloadSizes[localeIdentifier] = nil }
        }
    }
}

#Preview {
    LanguagePickerView { _ in }
}

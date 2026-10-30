import Foundation
import Speech

/// Apple's English speech model: provisioned by the system, one-time download (CONTEXT.md, On-device only).
public enum SpeechModelInstaller {
    private static func transcriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    }

    public static func isInstalled(locale: Locale = Locale(identifier: "en-US")) async -> Bool {
        await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    /// Downloads and installs if needed, reporting 0...1 progress. Safe to call when already installed.
    public static func install(locale: Locale = Locale(identifier: "en-US"),
                               onProgress: @escaping @Sendable (Double) -> Void) async throws {
        if await isInstalled(locale: locale) { onProgress(1); return }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber(locale)]) else {
            onProgress(1); return
        }
        let poll = Task {
            while !Task.isCancelled {
                onProgress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { poll.cancel() }
        try await request.downloadAndInstall()
        onProgress(1)
    }
}

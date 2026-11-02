@preconcurrency import AVFoundation
import Foundation
import Speech

/// Apple's SpeechTranscriber on an audio file, final results only, the same options as the app's engine and the
/// engine test (#145). Used to check what the caption engine makes of the app's own voice (echo) and of band-limited
/// headset audio.
public enum Transcribe {
    public static func ensureInstalled(_ locale: Locale) async throws {
        let t = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.fastResults],
                                  attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
            try await request.downloadAndInstall()
        }
    }

    public static func file(_ url: URL, locale: Locale) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.fastResults],
                                            attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collect = Task { () throws -> String in
            var parts: [String] = []
            for try await result in transcriber.results where result.isFinal {
                parts.append(String(result.text.characters))
            }
            return parts.joined(separator: " ")
        }
        let file = try AVAudioFile(forReading: url)
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collect.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Caption-style English lines, the kind of finished line #171 hands to the translator.
public enum SampleLines {
    public static let english = [
        "Where is the train station?",
        "Can we get the bill, please?",
        "I'm sorry, I didn't catch your name.",
        "The museum opens at nine tomorrow morning.",
        "My daughter is coming to visit next week.",
        "Is this seat taken?",
        "We booked a table for four at eight o'clock.",
        "How long does it take to walk there?",
        "Do you have anything without nuts in it?",
        "Thank you so much, that was really helpful.",
    ]
}

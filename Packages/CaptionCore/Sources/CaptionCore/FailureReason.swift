import Foundation

/// Plain-language failure reasons for users.
public enum FailureReason {
    /// Maps errors to sentences plain-language users can act on.
    public static func plainLanguage(for error: Error) -> String {
        if let te = error as? TranscriptionError {
            return plainLanguage(for: te)
        }
        if let se = error as? SpeakerModelError {
            return plainLanguage(for: se)
        }
        return String(localized: "Something went wrong — tap to try again")
    }

    private static func plainLanguage(for error: TranscriptionError) -> String {
        switch error {
        case .noCompatibleAudioFormat:
            return String(localized: "The microphone format isn't compatible — try a different mic mode in Settings")
        case .converterUnavailable:
            return String(localized: "Audio processing isn't available right now — tap to try again")
        case .interruptionTimedOut:
            return String(localized: "The microphone didn't come back — tap to try again")
        }
    }

    private static func plainLanguage(for error: SpeakerModelError) -> String {
        switch error {
        case .modelMissing:
            return String(localized: "The speaker model didn't install — tap to try again")
        }
    }
}

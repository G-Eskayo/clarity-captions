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
        #if os(macOS)
        if let ce = error as? CallAudioError {
            return plainLanguage(for: ce)
        }
        #endif
        return String(localized: "Something went wrong — tap to try again")
    }

    #if os(macOS)
    private static func plainLanguage(for error: CallAudioError) -> String {
        switch error {
        case .appNotPlayingSound:
            return String(localized: "No call sound to caption yet — start the call, then try again")
        case .coreAudio:
            return String(localized: "Can't hear the call — check System Audio Recording in Privacy & Security, then try again")
        }
    }
    #endif

    private static func plainLanguage(for error: TranscriptionError) -> String {
        switch error {
        case .noCompatibleAudioFormat:
            return String(localized: "The microphone format isn't compatible — try a different mic mode in Settings")
        case .converterUnavailable:
            return String(localized: "Audio processing isn't available right now — tap to try again")
        case .speechModelNotOnDevice:
            return String(localized: "This language isn't set up on this device. Set it up in Settings")
        }
    }

    private static func plainLanguage(for error: SpeakerModelError) -> String {
        switch error {
        case .modelMissing:
            return String(localized: "The speaker model didn't install — tap to try again")
        }
    }
}

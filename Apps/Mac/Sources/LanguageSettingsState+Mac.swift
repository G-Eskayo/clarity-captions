import CaptionCore
import Foundation

// #209: the Mac shares the iPhone's Settings, so it shows the caption language and translation rows too (owner,
// 2026-10-29: the Mac purchase covers room and calls). The iPhone reads its language and translation centers; the Mac
// captions in its engine's one language and has no translation yet, so this says exactly that. #213 wires the rest.
extension LanguageSettingsState {
    /// The Mac's engine is made with `TranscriptionEngine`'s default language, US English, and translation isn't
    /// bought on the Mac until #213 adds its own purchase (ADR 0028, #176).
    @MainActor
    static func current() -> LanguageSettingsState {
        LanguageSettingsState(captions: Locale(identifier: "en-US"), followsDevice: false, translationOn: false, target: nil, callCaptions: nil)
    }
}

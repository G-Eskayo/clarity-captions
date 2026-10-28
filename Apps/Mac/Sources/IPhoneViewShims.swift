import AppKit
import SwiftUI

// The Mac shares the iPhone app's Settings, Saved and credits views instead of redrawing them (#172, owner ~10:10).
// These stand-ins give those shared files the few iPhone-only names they use, with the Mac's meaning.

/// The iPhone scales Settings' fixed sizes with its text-size setting; the Mac has no such setting, so sizes stay put.
struct UIFontMetrics {
    static let `default` = UIFontMetrics()
    func scaledValue(for value: CGFloat) -> CGFloat { value }
}

/// Copy goes to the Mac's clipboard.
enum UIPasteboard {
    static let general = MacPasteboard()

    final class MacPasteboard {
        var string: String? {
            get { NSPasteboard.general.string(forType: .string) }
            set {
                NSPasteboard.general.clearContents()
                if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
            }
        }
    }
}

/// Macs have no taptic feedback for these: they do nothing.
struct UISelectionFeedbackGenerator {
    func selectionChanged() {}
}

struct UINotificationFeedbackGenerator {
    enum FeedbackType { case success, warning, error }
    func notificationOccurred(_ type: FeedbackType) {}
}

/// The iPhone's debug demo flags (screenshots of set-up screens). None of them apply on the Mac.
enum DemoMode {
    static let isOn = false
    static let flow: String? = nil
    static let select = false
    static let veilCleared = false
    static let settingsPush: String? = nil
    static let settingsSection: String? = nil
}

/// Beta feedback (ADR 0023) is iPhone-only for now, so Settings' "Test version" section never shows on the Mac.
final class BetaFeedbackCenter: ObservableObject {
    static let shared = BetaFeedbackCenter()
    let isOn = false
    let unsentCount = 0
}

/// The Mac doesn't capitalize as you type, so there's nothing to turn off.
enum MacAutocapitalization { case never, words, sentences, characters }

extension View {
    func textInputAutocapitalization(_ style: MacAutocapitalization?) -> some View { self }
}

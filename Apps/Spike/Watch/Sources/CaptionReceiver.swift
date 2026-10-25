import Foundation
import WatchConnectivity
import WatchKit

@MainActor
final class CaptionReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published var line = "Waiting for captions…"
    @Published var speakerLabel = ""
    private let session = WCSession.default

    override init() {
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
            // Restore initial state from the last update, if available.
            if let context = session.receivedApplicationContext as? [String: String] {
                if let line = context["line"] { self.line = line }
                if let speaker = context["speakerLabel"] { self.speakerLabel = speaker }
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let incomingLine = applicationContext["line"] as? String else { return }
        let incomingSpeaker = applicationContext["speakerLabel"] as? String ?? ""

        // Fire a haptic only when the speaker label changes (not on clear events) and we already have a speaker displayed.
        // This is more robust than trusting a boolean computed earlier: deduplication on the phone may coalesce multiple updates.
        if !incomingLine.isEmpty && !speakerLabel.isEmpty && incomingSpeaker != speakerLabel {
            WKInterfaceDevice.current().play(.notification)
        }

        self.line = incomingLine.isEmpty ? "Waiting for captions…" : incomingLine
        self.speakerLabel = incomingSpeaker
    }

    // MARK: - WCSessionDelegate (required stubs)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // No-op.
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // No-op.
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // No-op.
    }
}

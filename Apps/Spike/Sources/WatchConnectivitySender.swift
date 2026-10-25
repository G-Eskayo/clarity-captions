import Foundation
import WatchConnectivity
import CaptionCore

@MainActor
final class WatchConnectivitySender: NSObject, WCSessionDelegate {
    private var bridge = WatchCompanionBridge()
    private let session = WCSession.default

    func activate() {
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    func report(line: String, speakerLabel: String, isFinal: Bool) {
        guard WCSession.isSupported() else { return }
        guard session.activationState == .activated else { return }

        if let payload = bridge.update(line: line, speakerLabel: speakerLabel, isFinal: isFinal, now: Date()) {
            do {
                try session.updateApplicationContext(["line": payload.line, "speakerLabel": payload.speakerLabel])
            } catch {
                // Silently ignore Watch Connectivity errors; they're transient and non-critical.
            }
        }
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

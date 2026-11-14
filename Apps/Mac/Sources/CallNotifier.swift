import AppKit
import UserNotifications

/// The macOS notification for a call arriving (#178, owner 2026-10-28 ~21:05 UTC: Seal Speak always offers to caption a
/// call). Shown when the window isn't in front or is hidden, with the banner's own words and choices. It can only come
/// while Seal Speak is running (window or menu bar): macOS doesn't start an app for another app's call.
@MainActor
final class CallNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let category = "seal.call"
    static let captionAction = "seal.call.caption"
    static let notNowAction = "seal.call.notnow"
    static let requestID = "seal.call.ringing"

    static let secondCallCategory = "seal.call.second"
    static let holdAndAcceptAction = "seal.call.hold"
    static let endAndAcceptAction = "seal.call.end"
    static let secondCallRequestID = "seal.call.second.ringing"

    var onCaption: () -> Void = {}
    var onNotNow: () -> Void = {}
    var onHoldAndAccept: (String) -> Void = { _ in }
    var onEndAndAccept: () -> Void = {}

    private var center: UNUserNotificationCenter { .current() }

    /// Once, at start: the choices, and macOS's "allow notifications" question the first time.
    func setUp() {
        center.delegate = self
        let caption = UNNotificationAction(identifier: Self.captionAction, title: String(localized: "Caption call"), options: [.foreground])
        let notNow = UNNotificationAction(identifier: Self.notNowAction, title: String(localized: "Not now"), options: [])
        let holdAccept = UNNotificationAction(identifier: Self.holdAndAcceptAction, title: String(localized: "Hold & Accept"), options: [.foreground])
        let endAccept = UNNotificationAction(identifier: Self.endAndAcceptAction, title: String(localized: "End & Accept"), options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [caption, notNow], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.secondCallCategory, actions: [holdAccept, endAccept, notNow], intentIdentifiers: [])
        ])
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            NSLog("[calls] notifications %@%@", granted ? "allowed" : "not allowed", error.map { " (\($0))" } ?? "")
        }
    }

    /// Whether the window is where she'd see the banner: the app in front, not hidden, the window on screen.
    static var windowInFront: Bool {
        NSApp.isActive && !NSApp.isHidden
            && NSApp.windows.contains { $0.title == CaptionMacApp.windowTitle && $0.isVisible && $0.isOnActiveSpace }
    }

    func show(detail: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "You're getting a call")
        content.body = detail
        content.categoryIdentifier = Self.category
        content.sound = .default
        center.add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil)) { error in
            NSLog("[calls] notification %@", error.map { "failed: \($0)" } ?? "posted")
        }
    }

    func showSecondCall(app: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Another call is ringing")
        content.body = String(localized: "From \(app)")
        content.categoryIdentifier = Self.secondCallCategory
        content.sound = .default
        // Store the app name in user info so the action handler can access it
        content.userInfo = ["app": app]
        center.add(UNNotificationRequest(identifier: Self.secondCallRequestID, content: content, trigger: nil)) { error in
            NSLog("[calls] second call notification %@", error.map { "failed: \($0)" } ?? "posted")
        }
    }

    func remove() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.requestID])
    }

    func removeSecondCall() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.secondCallRequestID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.secondCallRequestID])
    }

    /// Brings the window forward, unhiding the app (⌘H) if need be, so the call's captions are in view.
    static func bringWindowForward() {
        NSApp.unhide(nil)
        NSApp.activate()
        NSApp.windows.first { $0.title == CaptionMacApp.windowTitle }?.makeKeyAndOrderFront(nil)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let app = userInfo["app"] as? String ?? "Unknown"
        Task { @MainActor in
            switch action {
            case Self.captionAction:
                Self.bringWindowForward()
                self.onCaption()
            case Self.notNowAction:
                self.onNotNow()
            case Self.holdAndAcceptAction:
                Self.bringWindowForward()
                self.onHoldAndAccept(app)
            case Self.endAndAcceptAction:
                Self.bringWindowForward()
                self.onEndAndAccept()
            default:
                // A click on the notification itself: show the window with the banner, choice still open.
                Self.bringWindowForward()
            }
            completionHandler()
        }
    }
}

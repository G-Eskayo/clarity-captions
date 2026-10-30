import Foundation

/// Live translation is a one-time in-app purchase (#53, owner on PR #171). Pure: the app's StoreKit code reports what
/// happened, this decides what Settings shows. Until it's owned, Settings shows Unlock and Restore purchase in the
/// translation section; once owned, Off/On and Into in the same place.
public struct TranslationPurchase: Equatable, Sendable {
    /// The product in App Store Connect and in the StoreKit test file.
    public static let productID = "com.gileskayo.captions.translation"
    /// The Mac's own product (#213): the Mac app is its own App Store record with its own price (ADR 0028, #176).
    public static let macProductID = "com.gileskayo.captions.mac.translation"

    public enum Activity: Equatable, Sendable { case idle, buying, restoring, waitingForApproval }
    public enum BuyResult: Equatable, Sendable { case bought, cancelled, pending, failed }

    public private(set) var isOwned = false
    public private(set) var activity: Activity = .idle
    /// A plain line under the buttons, or nil.
    public private(set) var message: String?

    public init() {}

    public var showsOffer: Bool { !isOwned }
    private var busy: Bool { activity == .buying || activity == .restoring }

    /// True when a purchase sheet should open.
    public mutating func unlockTapped() -> Bool {
        guard !isOwned, !busy else { return false }
        activity = .buying
        message = nil
        return true
    }

    /// True when a restore should run.
    public mutating func restoreTapped() -> Bool {
        guard !isOwned, !busy else { return false }
        activity = .restoring
        message = nil
        return true
    }

    public mutating func buyFinished(_ result: BuyResult) {
        guard !isOwned else { activity = .idle; message = nil; return }
        switch result {
        case .bought: own()
        case .cancelled: activity = .idle
        case .pending:
            activity = .waitingForApproval
            message = String(localized: "Waiting for approval. Translation turns on here once it's approved.")
        case .failed:
            activity = .idle
            message = String(localized: "The purchase didn't go through. Nothing was charged. Please try again.")
        }
    }

    public mutating func restoreFinished(found: Bool) {
        if found || isOwned { own(); return }
        activity = .idle
        message = String(localized: "There's no earlier purchase on this Apple Account.")
    }

    public mutating func restoreFailed() {
        activity = .idle
        message = String(localized: "Seal couldn't reach the App Store. Check that Wi-Fi is on and try again.")
    }

    /// What the App Store says she owns, at launch and whenever it changes (an approval, a refund, another device).
    public mutating func entitlementChanged(owned: Bool) {
        if owned { own() } else {
            isOwned = false
            if activity != .waitingForApproval && !busy { activity = .idle }
        }
    }

    private mutating func own() {
        isOwned = true
        activity = .idle
        message = nil
    }
}

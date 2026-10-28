import CaptionCore
import XCTest

/// #53: translation is a one-time purchase (owner, PR #171): Unlock and Restore purchase until it's owned, then Off/On
/// and Into in the same place. These try to break it with double taps, a cancelled sheet, Ask to Buy, a restore with
/// nothing to restore, and a refund.
final class TranslationPurchaseTests: XCTestCase {
    func testItStartsUnknownAndShowsTheOfferUntilTheStoreSaysOtherwise() {
        let p = TranslationPurchase()
        XCTAssertFalse(p.isOwned)
        XCTAssertTrue(p.showsOffer)
    }

    func testOwningItHidesTheOffer() {
        var p = TranslationPurchase()
        p.entitlementChanged(owned: true)
        XCTAssertTrue(p.isOwned)
        XCTAssertFalse(p.showsOffer)
    }

    func testUnlockStartsOneBuyAndASecondTapDoesNothing() {
        var p = TranslationPurchase()
        XCTAssertTrue(p.unlockTapped())
        XCTAssertEqual(p.activity, .buying)
        XCTAssertFalse(p.unlockTapped())
        XCTAssertFalse(p.restoreTapped(), "no restore while a buy is open")
    }

    func testABoughtPurchaseOwnsIt() {
        var p = TranslationPurchase()
        _ = p.unlockTapped()
        p.buyFinished(.bought)
        XCTAssertTrue(p.isOwned)
        XCTAssertEqual(p.activity, .idle)
    }

    func testCancellingTheSheetIsNotAProblem() {
        var p = TranslationPurchase()
        _ = p.unlockTapped()
        p.buyFinished(.cancelled)
        XCTAssertFalse(p.isOwned)
        XCTAssertEqual(p.activity, .idle)
        XCTAssertNil(p.message)
    }

    func testAskToBuySaysItsWaitingAndApprovalLaterOwnsIt() {
        var p = TranslationPurchase()
        _ = p.unlockTapped()
        p.buyFinished(.pending)
        XCTAssertEqual(p.activity, .waitingForApproval)
        XCTAssertNotNil(p.message)
        p.entitlementChanged(owned: true)
        XCTAssertTrue(p.isOwned)
        XCTAssertNil(p.message)
    }

    func testAFailedBuySaysWhatToDoInPlainWords() {
        var p = TranslationPurchase()
        _ = p.unlockTapped()
        p.buyFinished(.failed)
        XCTAssertFalse(p.isOwned)
        let m = p.message?.lowercased() ?? ""
        XCTAssertTrue(m.contains("try again"))
        for word in ["error", "storekit", "transaction", "sku"] { XCTAssertFalse(m.contains(word)) }
        XCTAssertTrue(p.unlockTapped(), "she can try again")
    }

    func testRestoreFindsAnEarlierPurchase() {
        var p = TranslationPurchase()
        XCTAssertTrue(p.restoreTapped())
        XCTAssertEqual(p.activity, .restoring)
        p.restoreFinished(found: true)
        XCTAssertTrue(p.isOwned)
        XCTAssertNil(p.message)
    }

    func testRestoreWithNothingToRestoreSaysSoAndKeepsTheOffer() {
        var p = TranslationPurchase()
        _ = p.restoreTapped()
        p.restoreFinished(found: false)
        XCTAssertFalse(p.isOwned)
        XCTAssertTrue(p.showsOffer)
        XCTAssertNotNil(p.message)
    }

    func testARestoreThatCantReachTheStoreSaysTryAgain() {
        var p = TranslationPurchase()
        _ = p.restoreTapped()
        p.restoreFailed()
        XCTAssertTrue(p.message?.lowercased().contains("try again") ?? false)
        XCTAssertEqual(p.activity, .idle)
    }

    func testARefundTakesItAwayAgain() {
        var p = TranslationPurchase()
        p.entitlementChanged(owned: true)
        p.entitlementChanged(owned: false)
        XCTAssertFalse(p.isOwned)
        XCTAssertTrue(p.showsOffer)
    }

    func testAnOwnedPurchaseIgnoresALateCancelledSheet() {
        var p = TranslationPurchase()
        _ = p.unlockTapped()
        p.entitlementChanged(owned: true)   // Transaction.updates got there first
        p.buyFinished(.cancelled)
        XCTAssertTrue(p.isOwned)
    }

    func testTappingUnlockWhenAlreadyOwnedDoesNothing() {
        var p = TranslationPurchase()
        p.entitlementChanged(owned: true)
        XCTAssertFalse(p.unlockTapped())
        XCTAssertFalse(p.restoreTapped())
    }
}

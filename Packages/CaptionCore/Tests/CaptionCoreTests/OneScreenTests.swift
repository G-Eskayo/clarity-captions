import XCTest
@testable import CaptionCore

/// Round 2 (#118, design #117): the app is one screen. Settings, saved conversations and credits replace the captions
/// on the same background with fades; questions are asked in place; nothing pops up.
final class OneScreenTests: XCTestCase {

    // MARK: where the app is

    func testStartsOnTheCaptions() {
        let nav = ScreenNavigator()
        XCTAssertEqual(nav.current, .captions)
        XCTAssertTrue(nav.showsCaptions)
        XCTAssertTrue(nav.showsGear)
    }

    func testTheGearOpensSettingsAndTheGearAgainGoesBack() {
        var nav = ScreenNavigator()
        nav.gearTapped()
        XCTAssertEqual(nav.current, .settings)
        XCTAssertTrue(nav.showsGear, "mock-up 01: the gear stays exactly where it was and takes her back")
        XCTAssertFalse(nav.showsCaptions)
        nav.gearTapped()
        XCTAssertEqual(nav.current, .captions)
    }

    func testSettingsOpensItsOwnPagesAndEachGoesBackOneStep() {
        var nav = ScreenNavigator(.settings)
        nav.open(.saved)
        XCTAssertEqual(nav.current, .saved)
        XCTAssertFalse(nav.showsGear, "mock-up 02: '‹ Settings' replaces the gear on the saved list")
        let id = UUID()
        nav.open(.savedConversation(id))
        XCTAssertEqual(nav.current, .savedConversation(id))
        nav.back()
        XCTAssertEqual(nav.current, .saved)
        nav.back()
        XCTAssertEqual(nav.current, .settings)
        nav.open(.credits)
        nav.open(.licenseText)
        nav.back()
        XCTAssertEqual(nav.current, .credits)
        nav.back()
        nav.open(.feedbackPreview)
        nav.back()
        XCTAssertEqual(nav.current, .settings)
    }

    func testAPageOnlyOpensFromWhereItLives() {
        var nav = ScreenNavigator()
        nav.open(.saved)                         // not from the captions: the saved list lives in Settings
        XCTAssertEqual(nav.current, .captions)
        nav.open(.savedConversation(UUID()))
        XCTAssertEqual(nav.current, .captions)
        nav = ScreenNavigator(.settings)
        nav.open(.licenseText)                   // the license text lives under Credits
        XCTAssertEqual(nav.current, .settings)
    }

    func testBackOnTheCaptionsDoesNothingAndTheGearDoesNothingDeeper() {
        var nav = ScreenNavigator()
        nav.back()
        XCTAssertEqual(nav.current, .captions)
        nav = ScreenNavigator(.saved)
        nav.gearTapped()
        XCTAssertEqual(nav.current, .saved, "there's no gear on the saved list; a stray call must not jump")
    }

    func testCloseGoesStraightBackToTheCaptionsFromAnywhere() {
        for screen: AppScreen in [.settings, .saved, .savedConversation(UUID()), .credits, .licenseText, .feedbackPreview] {
            var nav = ScreenNavigator(screen)
            nav.close()
            XCTAssertEqual(nav.current, .captions, "\(screen)")
        }
    }

    func testEveryPageKnowsWhereBackGoes() {
        XCTAssertNil(AppScreen.captions.parent)
        XCTAssertEqual(AppScreen.settings.parent, .captions)
        XCTAssertEqual(AppScreen.saved.parent, .settings)
        XCTAssertEqual(AppScreen.credits.parent, .settings)
        XCTAssertEqual(AppScreen.feedbackPreview.parent, .settings)
        XCTAssertEqual(AppScreen.savedConversation(UUID()).parent, .saved)
        XCTAssertEqual(AppScreen.licenseText.parent, .credits)
    }

    // MARK: questions asked in place

    func testAQuestionIsAskedThenAnsweredOnce() {
        var q = InPlaceQuestion<SavedListQuestion>()
        XCTAssertFalse(q.isAsking)
        q.ask(.deleteAll)
        XCTAssertTrue(q.isAsking)
        XCTAssertEqual(q.asking, .deleteAll)
        XCTAssertEqual(q.confirm(), .deleteAll)
        XCTAssertFalse(q.isAsking)
        XCTAssertNil(q.confirm(), "a second tap on the same answer must not act twice")
    }

    func testKeepAnswersNoAndActsOnNothing() {
        var q = InPlaceQuestion<SavedListQuestion>()
        let id = UUID()
        q.ask(.delete(id))
        q.keep()
        XCTAssertFalse(q.isAsking)
        XCTAssertNil(q.confirm())
    }

    func testAskingAgainReplacesTheQuestion() {
        var q = InPlaceQuestion<SavedListQuestion>()
        q.ask(.deleteAll)
        let id = UUID()
        q.ask(.delete(id))
        XCTAssertEqual(q.confirm(), .delete(id))
    }

    func testNewOnlyAsksWhenTheConversationIsntSaved() {
        var q = InPlaceQuestion<NewConversationQuestion>()
        XCTAssertEqual(NewConversationQuestion.request(hasUnsavedChanges: true, question: &q), .ask)
        XCTAssertTrue(q.isAsking)
        q.keep()
        XCTAssertEqual(NewConversationQuestion.request(hasUnsavedChanges: false, question: &q), .startNow)
        XCTAssertFalse(q.isAsking, "nothing to lose: no question")
    }

    // MARK: getting ready (no cover)

    func testGettingReadyIsSaidInTheStatusRowThenListening() {
        XCTAssertEqual(StatusWords.headline(for: .preparing), String(localized: "Getting ready…"))
        XCTAssertEqual(StatusWords.headline(for: .listening), String(localized: "Listening"))
        XCTAssertEqual(PrimaryControl.for(.preparing).title, String(localized: "Getting ready…"),
                       "mock-up 05 A: the pill says it too while it morphs")
    }
}

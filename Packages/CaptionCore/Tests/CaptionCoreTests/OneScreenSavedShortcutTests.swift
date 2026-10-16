import XCTest
@testable import CaptionCore

/// #137, option A (approved 2026-10-15): Saved conversations open straight from the captions screen (the list icon at the
/// top right), and going back from there returns to the captions, not to Settings.
final class OneScreenSavedShortcutTests: XCTestCase {
    func testTheListIconOpensSavedFromTheCaptionsAndBackReturnsThere() {
        var nav = ScreenNavigator()
        nav.openSavedFromCaptions()
        XCTAssertEqual(nav.current, .saved)
        nav.back()
        XCTAssertEqual(nav.current, .captions)
    }

    func testFromSettingsSavedStillGoesBackToSettings() {
        var nav = ScreenNavigator()
        nav.gearTapped()
        nav.open(.saved)
        nav.back()
        XCTAssertEqual(nav.current, .settings)
    }

    func testAConversationOpenedFromTheShortcutGoesBackToTheListThenTheCaptions() {
        let id = UUID()
        var nav = ScreenNavigator()
        nav.openSavedFromCaptions()
        nav.open(.savedConversation(id))
        nav.back()
        XCTAssertEqual(nav.current, .saved)
        nav.back()
        XCTAssertEqual(nav.current, .captions)
    }

    func testTheShortcutOnlyWorksFromTheCaptions() {
        var nav = ScreenNavigator()
        nav.gearTapped()
        nav.openSavedFromCaptions()
        XCTAssertEqual(nav.current, .settings, "a stray call must not jump around")
    }

    func testTheShortcutDoesNotLeakIntoALaterVisitFromSettings() {
        var nav = ScreenNavigator()
        nav.openSavedFromCaptions()
        nav.back()
        nav.gearTapped()
        nav.open(.saved)
        nav.back()
        XCTAssertEqual(nav.current, .settings)
    }

    func testCloseFromTheShortcutGoesToTheCaptions() {
        var nav = ScreenNavigator()
        nav.openSavedFromCaptions()
        nav.close()
        XCTAssertEqual(nav.current, .captions)
        nav.back()
        XCTAssertEqual(nav.current, .captions)
    }
}

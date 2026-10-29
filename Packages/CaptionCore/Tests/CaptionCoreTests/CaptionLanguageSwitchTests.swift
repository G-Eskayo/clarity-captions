import CaptionCore
import XCTest

/// #37: switching the caption language in Settings. Captions stay in the old language until the new one's speech files
/// are on the device; a failed download says what to do and changes nothing; the newest choice is the one that counts.
final class CaptionLanguageSwitchTests: XCTestCase {
    private let english = Locale(identifier: "en-US")
    private let spanish = Locale(identifier: "es-ES")
    private let french = Locale(identifier: "fr-FR")

    func testAnInstalledLanguageSwitchesAtOnceWithNoDownload() {
        var s = CaptionLanguageSwitch(current: english)
        XCTAssertNil(s.choose(spanish, installed: true))
        XCTAssertEqual(s.current, spanish)
        XCTAssertEqual(s.phase, .ready)
    }

    func testANewLanguageDownloadsFirstAndCaptionsKeepTheOldOneMeanwhile() {
        var s = CaptionLanguageSwitch(current: english)
        XCTAssertEqual(s.choose(spanish, installed: false), spanish, "asks for the download")
        XCTAssertEqual(s.current, english)
        XCTAssertEqual(s.phase, .downloading(spanish, progress: 0))
        s.progress(0.4, for: spanish)
        XCTAssertEqual(s.phase, .downloading(spanish, progress: 0.4))
        s.finished(.installed, for: spanish)
        XCTAssertEqual(s.current, spanish)
        XCTAssertEqual(s.phase, .ready)
    }

    func testAFailedDownloadChangesNothingAndSaysWhy() {
        var s = CaptionLanguageSwitch(current: english)
        _ = s.choose(spanish, installed: false)
        s.finished(.failed(.offline), for: spanish)
        XCTAssertEqual(s.current, english)
        XCTAssertEqual(s.phase, .failed(spanish, .offline))
        XCTAssertEqual(s.choose(spanish, installed: false), spanish, "Try again is choosing it again")
    }

    func testChoosingTheCurrentLanguageDoesNothing() {
        var s = CaptionLanguageSwitch(current: english)
        XCTAssertNil(s.choose(Locale(identifier: "en_US"), installed: false))
        XCTAssertEqual(s.phase, .ready)
    }

    func testChoosingTheCurrentLanguageMidDownloadCancelsTheSwitch() {
        var s = CaptionLanguageSwitch(current: english)
        _ = s.choose(spanish, installed: false)
        XCTAssertNil(s.choose(english, installed: true))
        XCTAssertEqual(s.phase, .ready)
        s.finished(.installed, for: spanish)
        XCTAssertEqual(s.current, english, "a download she walked away from doesn't switch her captions")
    }

    func testOnlyTheNewestChoiceCounts() {
        var s = CaptionLanguageSwitch(current: english)
        _ = s.choose(spanish, installed: false)
        _ = s.choose(french, installed: false)
        s.progress(0.9, for: spanish)
        XCTAssertEqual(s.phase, .downloading(french, progress: 0), "old progress doesn't show under the new language")
        s.finished(.installed, for: spanish)
        XCTAssertEqual(s.current, english)
        s.finished(.installed, for: french)
        XCTAssertEqual(s.current, french)
    }

    func testAnotherDownloadStillRunningLeavesTheChoiceWaiting() {
        var s = CaptionLanguageSwitch(current: english)
        _ = s.choose(spanish, installed: false)
        s.finished(.alreadyRunning, for: spanish)
        XCTAssertEqual(s.phase, .downloading(spanish, progress: 0))
    }

    func testProgressNeverGoesBackwardsOnScreen() {
        var s = CaptionLanguageSwitch(current: english)
        _ = s.choose(spanish, installed: false)
        s.progress(0.6, for: spanish)
        s.progress(0.2, for: spanish)
        XCTAssertEqual(s.phase, .downloading(spanish, progress: 0.6))
    }
}

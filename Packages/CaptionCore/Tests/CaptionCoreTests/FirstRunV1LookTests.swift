import XCTest
@testable import CaptionCore

/// #122: the first-run words, Credits and Jump to latest exactly as approved in #120 (mock-ups round3/03 and 04),
/// and the honest-claims rows that belong to first run (docs/design/honest-claims-2026-10-10.md).
final class FirstRunV1LookTests: XCTestCase {

    // MARK: first-run words, exactly as mocked

    func testWelcomeWordsAreTheApprovedOnes() {
        let c = FirstRunCopy.for(.welcome)
        XCTAssertEqual(c.title, "Seal shows what people around you are saying.")
        XCTAssertEqual(c.message, "It all happens on this phone. Setup takes about a minute.")
        XCTAssertEqual(c.button, "Set up")
    }

    func testMicrophoneWordsAreTheApprovedOnes() {
        let c = FirstRunCopy.for(.microphone)
        XCTAssertEqual(c.title, "Seal needs the microphone.")
        XCTAssertEqual(c.message, "Tap Allow on the next screen. What it hears stays on this phone.")
        XCTAssertEqual(c.button, "Continue")
    }

    func testMicrophoneOffWordsAreTheApprovedOnes() {
        let c = FirstRunCopy.for(.microphoneDenied)
        XCTAssertEqual(c.title, "The microphone is off.")
        XCTAssertEqual(c.message, "Captions need it. Open Settings and turn on Microphone for Seal.")
        XCTAssertEqual(c.button, "Open Settings")
    }

    func testCantRunWordsMatchTheStoreListingAndHaveNoButton() {
        let c = FirstRunCopy.for(.unsupported)
        XCTAssertEqual(c.title, "This phone can't run Seal.")
        XCTAssertEqual(c.message, "It needs an iPhone 12 or newer, or an iPad with an A14 chip or newer.")
        XCTAssertNil(c.button, "there's nothing she can do on that phone")
    }

    func testDownloadStoppedIsOneScreenWithTheReasonOnTheSecondLine() {
        for problem in [DownloadProblem.offline, .stalled, .failed] {
            let c = FirstRunCopy.downloadStopped(problem)
            XCTAssertEqual(c.title, "The download didn't finish.")
            XCTAssertEqual(c.message, problem.message)
            XCTAssertEqual(c.button, "Try again")
        }
        XCTAssertEqual(DownloadProblem.offline.message,
                       "Seal needs the internet once, for Apple's English speech files. Turn on Wi-Fi and try again.")
    }

    // MARK: honest claims (rows assigned to first run)

    func testFirstRunNeverOverclaimsOrSpeaksAsI() {
        let screens = [FirstRunStep.unsupported, .welcome, .microphone, .microphoneDenied, .speechModel, .speakerModel]
        var words = screens.map { s -> String in
            let c = FirstRunCopy.for(s)
            return [c.title, c.message, c.button ?? ""].joined(separator: " ")
        }
        words += [DownloadProblem.offline, .stalled, .failed].map(\.message)
        for text in words {
            XCTAssertFalse(text.contains("voices apart"), "overclaims telling voices apart: \(text)")
            XCTAssertFalse(text.lowercased().contains("never wait"), "promises no waiting: \(text)")
            XCTAssertFalse(text.contains("!"), "no exclamations: \(text)")
            for i in ["I'll ", "I need", "I can't", "I couldn't", "I'm "] {
                XCTAssertFalse(text.contains(i), "speaks as \"I\": \(text)")
            }
        }
    }

    // MARK: Credits, as mocked

    func testCreditsListTheMockedEntriesInOrder() {
        XCTAssertEqual(CreditsEntry.intro, "Seal is built on free, open work by these people.")
        XCTAssertEqual(CreditsEntry.all.map(\.name),
                       ["Apple Speech", "FluidAudio", "Sortformer (NVIDIA)", "OpenDyslexic", "Atkinson Hyperlegible"])
        XCTAssertEqual(CreditsEntry.all.map(\.line), [
            "Speech to text, on this phone.",
            "Telling voices apart. Apache 2.0.",
            "The voice model. CC BY 4.0.",
            "Abbie Gonzalez. Bitstream Vera license.",
            "Braille Institute. SIL Open Font License.",
        ])
    }

    func testEveryBundledThirdPartyWorkIsCreditedOnTheCreditsPageOrInTheFullLicenseTexts() {
        // The full license texts (NOTICE.md, one tap further) carry every notice; the page lists the mocked ones.
        let onPage = Set(CreditsEntry.all.compactMap(\.noticeID))
        for notice in ThirdPartyNotice.all where !onPage.contains(notice.id) {
            XCTAssertTrue(CreditsEntry.coveredByFullLicenseTexts.contains(notice.id),
                          "\(notice.name) is bundled but neither on the Credits page nor in the full license texts")
        }
    }

    // MARK: Jump to latest

    func testJumpToLatestShowsOnlyAfterScrollingBackAndGoesAtTheNewestLine() {
        XCTAssertFalse(AutoScroll.showsJumpToLatest(following: true))
        XCTAssertTrue(AutoScroll.showsJumpToLatest(following: false))
        XCTAssertEqual(AutoScroll.jumpToLatestWord, "↓ Latest")
    }
}

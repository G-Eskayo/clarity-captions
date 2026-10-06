import XCTest
@testable import CaptionCore

/// ADR 0013: a first-time user is never left looking at an unexplained wait, and every screen has one
/// obvious next step. The flow is a pure function of what is true right now, so an interrupted first run
/// resumes in the right place and a later mic revocation brings back the right screen.
final class FirstRunTests: XCTestCase {
    private func facts(welcome: Bool = true, mic: MicrophoneAccess = .granted,
                       language: Bool = true, speech: Bool = true, speaker: Bool = true) -> FirstRunFacts {
        FirstRunFacts(hasSeenWelcome: welcome, microphone: mic, languageChosen: language, speechModelInstalled: speech, speakerModelWarm: speaker)
    }

    func testFreshInstallStartsWithWelcome() {
        XCTAssertEqual(FirstRun.step(for: facts(welcome: false, mic: .undetermined, speech: false, speaker: false)), .welcome)
    }

    func testThenAsksForTheMicrophone() {
        XCTAssertEqual(FirstRun.step(for: facts(mic: .undetermined, language: false, speech: false, speaker: false)), .microphone)
    }

    func testDeniedMicrophoneExplainsHowToFixItBeforeAnythingElse() {
        XCTAssertEqual(FirstRun.step(for: facts(mic: .denied, language: false, speech: false, speaker: false)), .microphoneDenied)
    }

    func testThenAsksForTheLanguage() {
        XCTAssertEqual(FirstRun.step(for: facts(language: false, speech: false, speaker: false)), .language)
    }

    func testThenFetchesTheSpeechModel() {
        XCTAssertEqual(FirstRun.step(for: facts(speech: false, speaker: false)), .speechModel)
    }

    func testThenWarmsUpTheSpeakerModel() {
        XCTAssertEqual(FirstRun.step(for: facts(speaker: false)), .speakerModel)
    }

    func testEverythingReadyIsDone() {
        XCTAssertEqual(FirstRun.step(for: facts()), .done)
    }

    func testMicrophoneRevokedLaterBringsBackTheRightScreenEvenWhenEverythingElseIsDone() {
        XCTAssertEqual(FirstRun.step(for: facts(mic: .denied)), .microphoneDenied)
    }

    func testFixingTheMicrophoneInSettingsMovesOn() {
        XCTAssertEqual(FirstRun.step(for: facts(mic: .granted, speech: false, speaker: false)), .speechModel)
    }

    func testEveryStepSpeaksPlainWordsWithoutJargon() {
        let jargon = ["model", "diariz", "neural", "core ml", "mlmodel", "analyzer", "asset", "bundle", "network"]
        for step in FirstRunStep.allCases {
            let c = FirstRunCopy.for(step)
            XCTAssertFalse(c.title.isEmpty, "\(step) needs a title")
            XCTAssertFalse(c.message.isEmpty, "\(step) needs a message")
            for word in jargon {
                XCTAssertFalse((c.title + " " + c.message + " " + (c.button ?? "")).lowercased().contains(word), "\(step) uses jargon: \(word)")
            }
        }
    }

    func testStepsThatNeedATapHaveOneButtonAndAutomaticStepsHaveNone() {
        for step in [FirstRunStep.welcome, .microphone, .microphoneDenied, .done] {
            XCTAssertNotNil(FirstRunCopy.for(step).button, "\(step) needs one button")
        }
        for step in [FirstRunStep.language, .speechModel, .speakerModel] {
            XCTAssertNil(FirstRunCopy.for(step).button, "\(step) runs by itself")
        }
    }

    func testStoreRemembersTheWelcomeAndWarmUpForThisBuild() {
        let d = UserDefaults(suiteName: "first-run-test-\(UUID())")!
        let store = FirstRunStore(defaults: d)
        XCTAssertFalse(store.hasSeenWelcome)
        XCTAssertFalse(store.isSpeakerModelWarm(forBuild: "iOS 27.0 / 1"))
        store.markWelcomeSeen()
        store.markSpeakerModelWarm(forBuild: "iOS 27.0 / 1")
        XCTAssertTrue(store.hasSeenWelcome)
        XCTAssertTrue(store.isSpeakerModelWarm(forBuild: "iOS 27.0 / 1"))
    }

    func testWarmUpIsForgottenAfterAnOSOrAppUpdate() {
        let store = FirstRunStore(defaults: UserDefaults(suiteName: "first-run-test-\(UUID())")!)
        store.markSpeakerModelWarm(forBuild: "iOS 27.0 / 1")
        XCTAssertFalse(store.isSpeakerModelWarm(forBuild: "iOS 27.1 / 1"), "OS update may drop the Neural Engine cache")
        XCTAssertFalse(store.isSpeakerModelWarm(forBuild: "iOS 27.0 / 2"), "app update may too")
    }
}

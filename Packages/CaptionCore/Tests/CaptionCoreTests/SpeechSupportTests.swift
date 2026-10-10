import XCTest
@testable import CaptionCore

/// #80: a device that can't run Apple's speech engine (older iPhones and iPads that still take iOS 26) must say so
/// plainly, instead of a first run or Start button that never shows captions (Guideline 2.1; a reviewer's older iPad).
final class SpeechSupportTests: XCTestCase {
    private let english = Locale(identifier: "en-US")

    func testEngineAvailableAndLanguageSupportedIsSupported() async {
        let result = await SpeechSupport.check(locale: english, isAvailable: { true }, supportedLocale: { $0 })
        XCTAssertEqual(result, .supported)
    }

    func testEngineUnavailableIsUnsupportedDevice() async {
        let result = await SpeechSupport.check(locale: english, isAvailable: { false }, supportedLocale: { $0 })
        XCTAssertEqual(result, .unsupportedDevice)
    }

    func testEngineUnavailableNeverAsksForTheLanguage() async {
        let asked = Flag()
        _ = await SpeechSupport.check(locale: english, isAvailable: { false }, supportedLocale: { asked.set(); return $0 })
        XCTAssertFalse(asked.value, "no point asking about English on a device that can't run the engine")
    }

    func testLanguageNotSupportedIsItsOwnState() async {
        let result = await SpeechSupport.check(locale: english, isAvailable: { true }, supportedLocale: { _ in nil })
        XCTAssertEqual(result, .languageUnsupported)
    }

    /// "Supported but not installed yet" is the normal first run: it must lead to the download, not the dead end.
    /// `supportedLocale(equivalentTo:)` answers for supported locales whether or not the files are installed.
    func testSupportedButNotInstalledIsSupported() async {
        let result = await SpeechSupport.check(locale: english, isAvailable: { true }, supportedLocale: { _ in Locale(identifier: "en_US") })
        XCTAssertEqual(result, .supported)
    }

    /// A language lookup that never answers must not leave a blank screen. Not knowing is not the same as
    /// unsupported: carry on, and the download step has its own visible failure.
    func testLanguageLookupThatHangsFallsThroughToSupported() async {
        let start = ContinuousClock.now
        let result = await SpeechSupport.check(locale: english, isAvailable: { true },
                                               supportedLocale: { _ in try? await Task.sleep(for: .seconds(60)); return nil },
                                               timeout: .milliseconds(50))
        XCTAssertEqual(result, .supported)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5), "must not wait for the hung lookup")
    }

    func testOnlyTheUnsupportedStatesBlockCaptioning() {
        XCTAssertTrue(SpeechSupport.supported.canCaption)
        XCTAssertFalse(SpeechSupport.unsupportedDevice.canCaption)
        XCTAssertFalse(SpeechSupport.languageUnsupported.canCaption)
    }

    // MARK: First run

    private func facts(welcome: Bool = false, mic: MicrophoneAccess = .undetermined, speech: Bool = false,
                       speaker: Bool = false, support: SpeechSupport) -> FirstRunFacts {
        FirstRunFacts(hasSeenWelcome: welcome, microphone: mic, speechModelInstalled: speech,
                      speakerModelWarm: speaker, speechSupport: support)
    }

    func testUnsupportedDeviceShowsTheDeadEndBeforeAnythingElse() {
        XCTAssertEqual(FirstRun.step(for: facts(support: .unsupportedDevice)), .unsupported)
        XCTAssertEqual(FirstRun.step(for: facts(support: .languageUnsupported)), .unsupported)
    }

    /// Re-checked every launch, never cached: an iPad set up before an OS change still lands on the right screen.
    func testUnsupportedWinsEvenWhenSetupWasFinishedBefore() {
        XCTAssertEqual(FirstRun.step(for: facts(welcome: true, mic: .granted, speech: true, speaker: true, support: .unsupportedDevice)), .unsupported)
    }

    func testSupportedDeviceFlowIsUnchanged() {
        XCTAssertEqual(FirstRun.step(for: facts(support: .supported)), .welcome)
        XCTAssertEqual(FirstRun.step(for: facts(welcome: true, mic: .granted, speech: true, speaker: true, support: .supported)), .done)
    }

    func testFactsDefaultToSupportedSoExistingCallersAreUnchanged() {
        let f = FirstRunFacts(hasSeenWelcome: true, microphone: .granted, speechModelInstalled: true, speakerModelWarm: true)
        XCTAssertEqual(f.speechSupport, .supported)
    }

    func testTheDeadEndHasNoButtonAndPlainWords() {
        let copy = FirstRunCopy.for(.unsupported)
        XCTAssertNil(copy.button, "nothing to tap: there is no fix on this device")
        // Approved wording (#120): says plainly that this phone can't run it, and which ones can.
        XCTAssertTrue(copy.title.lowercased().contains("can't run"))
        XCTAssertTrue(copy.message.contains("iPhone 12"))
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    func set() { lock.withLock { raised = true } }
    var value: Bool { lock.withLock { raised } }
}

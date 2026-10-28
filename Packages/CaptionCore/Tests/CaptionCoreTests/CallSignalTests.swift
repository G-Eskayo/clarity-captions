import XCTest
@testable import CaptionCore

/// #178: which apps' sound means "a call is live". Rule: a call app (FaceTime or its call services) is using the
/// microphone. Its sound alone isn't enough: FaceTime plays ringtones and the join chime without a call being up.
final class CallSignalTests: XCTestCase {
    private func p(_ id: String, input: Bool = false, output: Bool = false) -> CallAudioActivity {
        CallAudioActivity(name: id, isRunningInput: input, isRunningOutput: output)
    }

    func testNothingRunningIsNoCall() {
        XCTAssertFalse(CallSignal.isCallLive([]))
    }

    func testFaceTimeUsingTheMicIsACall() {
        XCTAssertTrue(CallSignal.isCallLive([p("com.apple.FaceTime", input: true, output: true)]))
    }

    func testTheConferencingDaemonUsingTheMicIsACall() {
        XCTAssertTrue(CallSignal.isCallLive([p("avconferenced", input: true)]))
    }

    func testACallAppOnlyPlayingSoundIsNotACall() {
        XCTAssertFalse(CallSignal.isCallLive([p("com.apple.FaceTime", output: true)]), "a ringtone or a chime, not a call")
    }

    func testOtherAppsUsingTheMicAreNotACall() {
        XCTAssertFalse(CallSignal.isCallLive([p("com.apple.CoreSpeech", input: true, output: true),
                                              p("com.gileskayo.captions", input: true),
                                              p("com.gileskayo.marvin-voice", input: true)]))
    }

    func testOurOwnMicDoesNotHideARealCall() {
        XCTAssertTrue(CallSignal.isCallLive([p("com.gileskayo.captions", input: true), p("com.apple.FaceTime", input: true)]))
    }

    func testNamesAreMatchedExactlyNotByPrefix() {
        XCTAssertFalse(CallSignal.isCallLive([p("com.apple.FaceTimeWidget", input: true), p("avconferenced-helper", input: true)]))
    }
}

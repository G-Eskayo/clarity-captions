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

/// The owner's rule (2026-10-28): the top bar names a call app only while that app is really in a call, by the name of
/// the app that is in it ("Captioning your Zoom call"), and otherwise says no app at all.
final class CallAppNameTests: XCTestCase {
    private func p(_ id: String, input: Bool = true, output: Bool = true) -> CallAudioActivity {
        CallAudioActivity(name: id, isRunningInput: input, isRunningOutput: output)
    }

    func testNoCallNamesNoApp() {
        XCTAssertNil(CallSignal.liveCallApp([]))
        XCTAssertNil(CallSignal.liveCallApp([p("com.apple.CoreSpeech"), p("com.gileskayo.captions")]))
    }

    func testFaceTimeAndItsServicesAreAllFaceTime() {
        for id in ["com.apple.FaceTime", "avconferenced", "callservicesd", "com.apple.TelephonyUtilities"] {
            XCTAssertEqual(CallSignal.liveCallApp([p(id, output: false)]), "FaceTime", id)
        }
    }

    func testOtherCallAppsAreNamedForThemselves() {
        XCTAssertEqual(CallSignal.liveCallApp([p("us.zoom.xos")]), "Zoom")
        XCTAssertEqual(CallSignal.liveCallApp([p("com.microsoft.teams2")]), "Teams")
        XCTAssertEqual(CallSignal.liveCallApp([p("net.whatsapp.WhatsApp")]), "WhatsApp")
    }

    func testAZoomMeetingIsACallToo() {
        XCTAssertTrue(CallSignal.isCallLive([p("us.zoom.xos", output: false)]))
    }

    func testACallAppOnlyPlayingSoundIsNotNamed() {
        // Zoom's test tone, FaceTime's ringtone: sound, but no call.
        XCTAssertNil(CallSignal.liveCallApp([p("us.zoom.xos", input: false), p("com.apple.FaceTime", input: false)]))
    }

    func testTwoCallAppsAtOnceGiveOneStableName() {
        let both = [p("us.zoom.xos"), p("com.apple.FaceTime")]
        XCTAssertEqual(CallSignal.liveCallApp(both), CallSignal.liveCallApp(both.reversed()), "the name must not flicker with list order")
        XCTAssertEqual(CallSignal.liveCallApp(both), "FaceTime")
    }

    func testWordsForTheTopBar() {
        XCTAssertEqual(CallSignal.captioningWords(app: "Zoom"), "Captioning your Zoom call")
    }
}

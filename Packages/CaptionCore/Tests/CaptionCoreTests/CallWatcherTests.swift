import XCTest
@testable import CaptionCore

/// #178 second-call detection on macOS: core audio activity classification used by CallWatcher.
///
/// This test file documents how CallSignal.isCallLive and CallSignal.liveCallApp classify
/// audio activity into call/non-call states. These are the rules that CallWatcher uses
/// to decide when to publish a call state change; the watcher itself uses Core Audio
/// listeners and timers to gather the snapshot being classified here.
///
/// Many scenarios here are synthetic/pretend because a real second concurrent FaceTime call
/// on macOS has not been recorded (only one object E24 with input/output was seen), so we
/// test the classification logic for what would happen if that input appeared.
final class CallWatcherTests: XCTestCase {
    private func p(_ id: String, input: Bool = false, output: Bool = false) -> CallAudioActivity {
        CallAudioActivity(name: id, isRunningInput: input, isRunningOutput: output)
    }

    func testDifferentFaceTimeProcessesStillClassifyAsOneCallApp() {
        // FaceTime audio can come from multiple processes (com.apple.FaceTime, avconferenced, callservicesd).
        // When route changes (headphones in/out), the reporting process may switch but the call continues.
        // CallSignal classifies both as "FaceTime" so CallWatcher sees it as the same call, not ended-and-started.
        let facetime = p("com.apple.FaceTime", input: true, output: true)
        let avconferenced = p("com.apple.avconferenced", input: true, output: true)
        XCTAssertTrue(CallSignal.isCallLive([facetime]), "FaceTime process is a call")
        XCTAssertTrue(CallSignal.isCallLive([avconferenced]), "avconferenced process is also a call")
        XCTAssertEqual(CallSignal.liveCallApp([facetime]), "FaceTime")
        XCTAssertEqual(CallSignal.liveCallApp([avconferenced]), "FaceTime")
    }

    func testNoRecordingProcessMeansNoCallIsLive() {
        // When no process has input (microphone open), no call is live, even if processes have output.
        // This is how the Mac distinguishes a call (both input and output) from just playing audio.
        let no_activity: [CallAudioActivity] = []
        XCTAssertFalse(CallSignal.isCallLive(no_activity), "no processes: no call")
        let output_only = p("com.apple.FaceTime", output: true)
        XCTAssertFalse(CallSignal.isCallLive([output_only]), "output only: not a live call")
    }

    func testMultipleFaceTimeProcessesWithInputStayClassifiedAsOneFaceTimeCall() {
        // SYNTHETIC: if two FaceTime processes both had input simultaneously (unobserved on macOS so far),
        // they would still classify as one "FaceTime" app per CallSignal.liveCallApp (always returns the first match).
        // This test documents the classification rule; detecting *two* concurrent calls from the same app
        // would require counting recording objects, which CallWatcher does internally but CallSignal doesn't expose.
        let first_object = p("com.apple.FaceTime", input: true, output: true)
        let second_object = p("com.apple.avconferenced", input: true, output: true)
        XCTAssertEqual(CallSignal.liveCallApp([first_object, second_object]), "FaceTime", "returns first matching app")
        XCTAssertTrue(CallSignal.isCallLive([first_object, second_object]), "both FaceTime processes: call is live")
    }
}

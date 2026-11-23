import XCTest
@testable import CaptionCore

final class MacSourceRulesTests: XCTestCase {
    func testLaunchArgumentsReplacesUserDefaultsInMacSources() {
        // Verify that CallAudioSelfTest reads arguments correctly
        let args = LaunchArguments(["app", "-CallAudioSelfTest", "process", "-MarvinRouteWatch"])
        XCTAssertEqual(args.value(after: "CallAudioSelfTest"), "process")
        XCTAssertTrue(args.flag("MarvinRouteWatch"))
    }

    func testLaunchArgumentsHandlesMarvinScreenshotMode() {
        // Verify that MarvinScreenshot can read its scene arguments
        let args = LaunchArguments(["app", "-MarvinScreenshot", "/tmp/test.png", "-SealPopupMockup", "waiting", "-MarvinAppearance", "dark"])
        XCTAssertEqual(args.value(after: "MarvinScreenshot"), "/tmp/test.png")
        XCTAssertEqual(args.value(after: "SealPopupMockup"), "waiting")
        XCTAssertEqual(args.value(after: "MarvinAppearance"), "dark")
    }

    func testLaunchArgumentsHandlesFakeCallTiming() {
        // Verify that CallFlow can read fake call timing arguments
        let args = LaunchArguments(["app", "-SealFakeCall", "5.0,15.0", "-SealFakeChoice", "caption", "-SealFakeSave", "yes"])
        XCTAssertEqual(args.value(after: "SealFakeCall"), "5.0,15.0")
        XCTAssertEqual(args.value(after: "SealFakeChoice"), "caption")
        XCTAssertEqual(args.value(after: "SealFakeSave"), "yes")
    }
}

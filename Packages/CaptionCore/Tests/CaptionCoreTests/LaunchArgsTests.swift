import XCTest
@testable import CaptionCore

final class LaunchArgsTests: XCTestCase {
    override func tearDown() {
        LaunchArgs.arguments = ProcessInfo.processInfo.arguments
        super.tearDown()
    }

    func testFlagPresent() {
        LaunchArgs.arguments = ["/bin/app", "-MarvinHideCheck", "other"]
        XCTAssertTrue(LaunchArgs.flag("MarvinHideCheck"))
    }

    func testFlagAbsent() {
        LaunchArgs.arguments = ["/bin/app", "other"]
        XCTAssertFalse(LaunchArgs.flag("MarvinHideCheck"))
    }

    func testFlagWithCustomArgs() {
        let args = ["/bin/app", "-TestFlag"]
        XCTAssertTrue(LaunchArgs.flag("TestFlag", in: args))
    }

    func testValueAfterPresent() {
        LaunchArgs.arguments = ["/bin/app", "-CallAudioSelfTest", "mic", "other"]
        XCTAssertEqual(LaunchArgs.value(after: "CallAudioSelfTest"), "mic")
    }

    func testValueAfterAbsent() {
        LaunchArgs.arguments = ["/bin/app", "other"]
        XCTAssertNil(LaunchArgs.value(after: "CallAudioSelfTest"))
    }

    func testValueAfterAtEnd() {
        LaunchArgs.arguments = ["/bin/app", "-CallAudioSelfTest"]
        XCTAssertNil(LaunchArgs.value(after: "CallAudioSelfTest"))
    }

    func testValueAfterWithCustomArgs() {
        let args = ["/bin/app", "-MarvinScreenshot", "/tmp/test.png"]
        XCTAssertEqual(LaunchArgs.value(after: "MarvinScreenshot", in: args), "/tmp/test.png")
    }

    func testMultipleValues() {
        LaunchArgs.arguments = ["/bin/app", "-MarvinAppearance", "dark", "-CallAudioSelfTest", "both"]
        XCTAssertEqual(LaunchArgs.value(after: "MarvinAppearance"), "dark")
        XCTAssertEqual(LaunchArgs.value(after: "CallAudioSelfTest"), "both")
    }
}

import XCTest
@testable import CaptionCore

final class LaunchArgumentsTests: XCTestCase {
    func testFlagPresent() {
        let args = LaunchArguments(["app", "-debug", "-verbose"])
        XCTAssertTrue(args.flag("debug"))
        XCTAssertTrue(args.flag("verbose"))
        XCTAssertFalse(args.flag("missing"))
    }

    func testValueAfterFlag() {
        let args = LaunchArguments(["app", "-mode", "test", "-level", "5"])
        XCTAssertEqual(args.value(after: "mode"), "test")
        XCTAssertEqual(args.value(after: "level"), "5")
        XCTAssertNil(args.value(after: "missing"))
    }

    func testValueAfterFlagAtEndOfArgs() {
        let args = LaunchArguments(["app", "-mode"])
        XCTAssertNil(args.value(after: "mode"))
    }

    func testDoubleAfterFlag() {
        let args = LaunchArguments(["app", "-delay", "2.5", "-count", "10"])
        XCTAssertEqual(args.double(after: "delay"), 2.5)
        XCTAssertEqual(args.double(after: "count"), 10.0)
        XCTAssertNil(args.double(after: "missing"))
    }

    func testDoubleAfterFlagWithInvalidValue() {
        let args = LaunchArguments(["app", "-value", "notanumber"])
        XCTAssertNil(args.double(after: "value"))
    }

    func testEmptyArguments() {
        let args = LaunchArguments([])
        XCTAssertFalse(args.flag("debug"))
        XCTAssertNil(args.value(after: "mode"))
        XCTAssertNil(args.double(after: "delay"))
    }

    func testDefaultCommandLineArguments() {
        let args = LaunchArguments()
        // Just verify it doesn't crash with real CommandLine.arguments
        _ = args.flag("test")
    }

    func testMultipleFlagsAndValues() {
        let args = LaunchArguments(["app", "-a", "1", "-b", "-c", "2.5", "-d"])
        XCTAssertTrue(args.flag("a"))
        XCTAssertEqual(args.value(after: "a"), "1")
        XCTAssertTrue(args.flag("b"))
        XCTAssertNil(args.value(after: "b"))
        XCTAssertTrue(args.flag("c"))
        XCTAssertEqual(args.double(after: "c"), 2.5)
        XCTAssertTrue(args.flag("d"))
    }

    func testValueWithFlagLikeContent() {
        let args = LaunchArguments(["app", "-path", "/some/-weird/path", "-done"])
        XCTAssertEqual(args.value(after: "path"), "/some/-weird/path")
    }
}

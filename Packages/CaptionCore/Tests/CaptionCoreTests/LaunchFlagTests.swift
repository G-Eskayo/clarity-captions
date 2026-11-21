import XCTest
@testable import CaptionCore

final class LaunchFlagTests: XCTestCase {
    func testIsSetReturnsTrueWhenFlagIsPresent() {
        let args = ["/path/to/app", "-flag"]
        XCTAssertTrue(LaunchFlag.isSet("-flag", in: args))
    }

    func testIsSetReturnsFalseWhenFlagIsAbsent() {
        let args = ["/path/to/app", "-other"]
        XCTAssertFalse(LaunchFlag.isSet("-flag", in: args))
    }

    func testIsSetIsCaseSensitive() {
        let args = ["/path/to/app", "-Flag"]
        XCTAssertFalse(LaunchFlag.isSet("-flag", in: args))
    }

    func testValueAfterReturnStringValueAfterFlag() {
        let args = ["/path/to/app", "-output", "/tmp/file.png"]
        XCTAssertEqual(LaunchFlag.value(after: "-output", in: args), "/tmp/file.png")
    }

    func testValueAfterReturnsNilWhenFlagAbsent() {
        let args = ["/path/to/app", "-other", "value"]
        XCTAssertNil(LaunchFlag.value(after: "-output", in: args))
    }

    func testValueAfterReturnsNilWhenFlagIsLast() {
        let args = ["/path/to/app", "-output"]
        XCTAssertNil(LaunchFlag.value(after: "-output", in: args))
    }

    func testValueAfterHandlesMultipleFlags() {
        let args = ["/path/to/app", "-input", "in.txt", "-output", "out.txt"]
        XCTAssertEqual(LaunchFlag.value(after: "-input", in: args), "in.txt")
        XCTAssertEqual(LaunchFlag.value(after: "-output", in: args), "out.txt")
    }

    func testValueAfterHandlesEmptyStringValue() {
        let args = ["/path/to/app", "-flag", ""]
        XCTAssertEqual(LaunchFlag.value(after: "-flag", in: args), "")
    }

    func testDoubleAfterReturnsDoubleValue() {
        let args = ["/path/to/app", "-delay", "2.5"]
        XCTAssertEqual(LaunchFlag.double(after: "-delay", in: args), 2.5)
    }

    func testDoubleAfterReturnsIntegerAsDouble() {
        let args = ["/path/to/app", "-count", "42"]
        XCTAssertEqual(LaunchFlag.double(after: "-count", in: args), 42.0)
    }

    func testDoubleAfterReturnsNilWhenFlagAbsent() {
        let args = ["/path/to/app", "-other", "value"]
        XCTAssertNil(LaunchFlag.double(after: "-delay", in: args))
    }

    func testDoubleAfterReturnsNilWhenValueNotADouble() {
        let args = ["/path/to/app", "-delay", "not-a-number"]
        XCTAssertNil(LaunchFlag.double(after: "-delay", in: args))
    }

    func testDoubleAfterReturnsNilWhenFlagIsLast() {
        let args = ["/path/to/app", "-delay"]
        XCTAssertNil(LaunchFlag.double(after: "-delay", in: args))
    }

    func testDoubleAfterHandlesNegativeValues() {
        let args = ["/path/to/app", "-offset", "-1.5"]
        XCTAssertEqual(LaunchFlag.double(after: "-offset", in: args), -1.5)
    }

    func testDefaultArgumentsUseProcessInfo() {
        // This test verifies the default parameter works (can't easily test the actual value without modifying ProcessInfo)
        // but we ensure the function signature accepts no arguments
        let result1: Double? = LaunchFlag.double(after: "-nonexistent")
        let result2: String? = LaunchFlag.value(after: "-nonexistent")
        let result3: Bool = LaunchFlag.isSet("-nonexistent")
        // Just verify these calls work (the actual values depend on the process arguments)
        _ = (result1, result2, result3)
    }

    func testValueAfterWithFlagThatLooksLikeAValue() {
        // Flags starting with - should be found correctly even if previous values look similar
        let args = ["/path/to/app", "-flag1", "-flag2", "-flag3"]
        XCTAssertEqual(LaunchFlag.value(after: "-flag1", in: args), "-flag2")
    }

    func testLaunchFlagIgnoresUserDefaultsLeftoverValues() {
        // The critical test: even if UserDefaults holds a stale value, LaunchFlag checks argv only.
        // This proves LaunchFlag doesn't fall back to defaults, closing the leftover-default bug.
        let testKey = "LaunchFlagTestKey"
        let previousValue = UserDefaults.standard.string(forKey: testKey)
        defer {
            if let previous = previousValue {
                UserDefaults.standard.set(previous, forKey: testKey)
            } else {
                UserDefaults.standard.removeObject(forKey: testKey)
            }
        }

        // Set a value in UserDefaults (simulating a stale value from a prior run)
        UserDefaults.standard.set("staleLaunchValue", forKey: "-TestMarvinFlag")

        // The test process's argv never contains this flag
        let args = ["/path/to/app", "-OtherFlag"]

        // Even though UserDefaults has the value, LaunchFlag sees nothing
        XCTAssertNil(LaunchFlag.value(after: "-TestMarvinFlag", in: args))
        XCTAssertFalse(LaunchFlag.isSet("-TestMarvinFlag", in: args))
    }
}

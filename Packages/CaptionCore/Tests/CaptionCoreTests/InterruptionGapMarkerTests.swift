import XCTest
@testable import CaptionCore

final class InterruptionGapMarkerTests: XCTestCase {
    func testInterruptionGapMarkerText() {
        let text = InterruptionGapMarker.text
        XCTAssertFalse(text.isEmpty, "marker text should not be empty")
        XCTAssertTrue(text.contains("pause"), "marker should mention pausing")
    }
}

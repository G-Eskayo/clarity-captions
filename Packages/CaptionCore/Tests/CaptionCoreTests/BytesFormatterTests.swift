import XCTest
@testable import CaptionCore

final class BytesFormatterTests: XCTestCase {
    func testZeroIsAlreadyDownloaded() {
        XCTAssertEqual(BytesFormatter.format(0), "Already downloaded")
    }

    func testNilIsUnknown() {
        XCTAssertEqual(BytesFormatter.format(nil), "Size unknown")
    }

    func testBytesForSmallValues() {
        XCTAssertEqual(BytesFormatter.format(512), "512 B")
        XCTAssertEqual(BytesFormatter.format(1023), "1023 B")
    }

    func testKilobytes() {
        XCTAssertEqual(BytesFormatter.format(1024), "1.0 KB")
        XCTAssertEqual(BytesFormatter.format(5 * 1024), "5.0 KB")
    }

    func testMegabytes() {
        XCTAssertEqual(BytesFormatter.format(1024 * 1024), "1.0 MB")
        XCTAssertEqual(BytesFormatter.format(50 * 1024 * 1024), "50 MB")
    }

    func testGigabytes() {
        XCTAssertEqual(BytesFormatter.format(1024 * 1024 * 1024), "1.0 GB")
        XCTAssertEqual(BytesFormatter.format(4 * 1024 * 1024 * 1024), "4.0 GB")
    }

    func testDecimalPlacesForSmallNumbers() {
        XCTAssertEqual(BytesFormatter.format(Int64(1.5 * Double(1024 * 1024))), "1.5 MB")
    }

    func testNoDecimalPlacesForLargeNumbers() {
        XCTAssertEqual(BytesFormatter.format(Int64(15.7 * Double(1024 * 1024))), "16 MB")
    }
}

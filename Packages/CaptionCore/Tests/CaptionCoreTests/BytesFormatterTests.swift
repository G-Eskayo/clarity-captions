import XCTest
@testable import CaptionCore

final class BytesFormatterTests: XCTestCase {
    func testAlreadyDownloaded() {
        XCTAssertEqual(BytesFormatter.format(bytes: 0), "Already downloaded")
    }

    func testNilBytes() {
        XCTAssertEqual(BytesFormatter.format(bytes: nil), "Size unknown")
    }

    func testBytes() {
        XCTAssertEqual(BytesFormatter.format(bytes: 512), "512 B")
    }

    func testKilobytes() {
        XCTAssertEqual(BytesFormatter.format(bytes: 2048), "2.0 KB")
    }

    func testMegabytes() {
        XCTAssertEqual(BytesFormatter.format(bytes: 52_428_800), "50 MB")
    }

    func testMegabytesRounded() {
        XCTAssertEqual(BytesFormatter.format(bytes: 104_857_600), "100 MB")
    }

    func testGigabytes() {
        XCTAssertEqual(BytesFormatter.format(bytes: 1_073_741_824), "1.0 GB")
    }
}

import XCTest
@testable import CaptionCore

final class CaptionStreamTests: XCTestCase {
    func testVolatileUpdatesReviseTheLastLineInPlace() {
        var s = CaptionStream()
        s.apply(text: "hel", isFinal: false)
        s.apply(text: "hello wor", isFinal: false)
        XCTAssertEqual(s.lines.map(\.text), ["hello wor"])
        XCTAssertFalse(s.lines[0].isFinal)
    }

    func testFinalResultClosesTheLineAndNextResultStartsANewOne() {
        var s = CaptionStream()
        s.apply(text: "hello world", isFinal: true)
        s.apply(text: "how are", isFinal: false)
        XCTAssertEqual(s.lines.map(\.text), ["hello world", "how are"])
        XCTAssertEqual(s.lines.map(\.isFinal), [true, false])
    }

    func testBlankTextIsIgnored() {
        var s = CaptionStream()
        s.apply(text: "   ", isFinal: false)
        XCTAssertTrue(s.lines.isEmpty)
    }

    func testLineIDsAreStableAcrossRevisions() {
        var s = CaptionStream()
        s.apply(text: "a", isFinal: false)
        let id = s.lines[0].id
        s.apply(text: "ab", isFinal: false)
        XCTAssertEqual(s.lines[0].id, id)
    }
}

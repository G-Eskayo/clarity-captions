import XCTest
@testable import CaptionCore

final class MenuBarPresentationTests: XCTestCase {
    func testEachCaptionStateHasADistinctSymbolName() {
        let idle = MenuBarPresentation.symbolName(for: .idle)
        let preparing = MenuBarPresentation.symbolName(for: .preparing)
        let listening = MenuBarPresentation.symbolName(for: .listening)
        let failed = MenuBarPresentation.symbolName(for: .failed(""))

        XCTAssertFalse(idle.isEmpty, "idle must have a symbol")
        XCTAssertFalse(preparing.isEmpty, "preparing must have a symbol")
        XCTAssertFalse(listening.isEmpty, "listening must have a symbol")
        XCTAssertFalse(failed.isEmpty, "failed must have a symbol")

        XCTAssertNotEqual(idle, preparing)
        XCTAssertNotEqual(idle, listening)
        XCTAssertNotEqual(idle, failed)
        XCTAssertNotEqual(preparing, listening)
        XCTAssertNotEqual(preparing, failed)
        XCTAssertNotEqual(listening, failed)
    }

    func testEmptyFailureReasonStillReturnsFailedSymbol() {
        let symbolForEmpty = MenuBarPresentation.symbolName(for: .failed(""))
        let symbolForNonEmpty = MenuBarPresentation.symbolName(for: .failed("mic was denied"))
        XCTAssertEqual(symbolForEmpty, symbolForNonEmpty, "symbol should not depend on failure reason")
    }

    func testHugeFailureReasonDoesNotCrash() {
        let huge = String(repeating: "x", count: 10_000)
        let symbol = MenuBarPresentation.symbolName(for: .failed(huge))
        XCTAssertFalse(symbol.isEmpty, "huge reason should still return a symbol")
    }

    func testMalformedFailureReasonDoesNotCrash() {
        let malformed = "line1\nline2\u{0000}emoji🎤"
        let symbol = MenuBarPresentation.symbolName(for: .failed(malformed))
        XCTAssertFalse(symbol.isEmpty, "malformed reason should still return a symbol")
    }

    func testSymbolNameIsPure() {
        let state = CaptionState.listening
        let first = MenuBarPresentation.symbolName(for: state)
        let second = MenuBarPresentation.symbolName(for: state)
        XCTAssertEqual(first, second, "same state should always return the same symbol")
    }

    func testAllCaptionStatesGetMapped() {
        let states: [CaptionState] = [.idle, .preparing, .listening, .failed("error")]
        for state in states {
            let symbol = MenuBarPresentation.symbolName(for: state)
            XCTAssertFalse(symbol.isEmpty, "\(state) must have a symbol mapping")
        }
    }
}

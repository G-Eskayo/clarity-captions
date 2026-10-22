import Foundation
import XCTest
@testable import EngineEvalKit

final class EngineSpecTests: XCTestCase {
    func testParsesBuiltinAndLocal() {
        XCTAssertEqual(EngineSpec.parse("apple"), .builtin("apple"))
        XCTAssertEqual(EngineSpec.parse(" local:ultra-pal4 "), .local("ultra-pal4"))
    }

    func testRejectsEmptyAndPathEscapes() {
        XCTAssertNil(EngineSpec.parse(""))
        XCTAssertNil(EngineSpec.parse("local:"))
        XCTAssertNil(EngineSpec.parse("local:../etc"))
        XCTAssertNil(EngineSpec.parse("local:a/b"))
        XCTAssertNil(EngineSpec.parseList("apple,,local:x"))
        XCTAssertEqual(EngineSpec.parseList("apple,local:x"), [.builtin("apple"), .local("x")])
    }

    func testVariantInfoRoundTripAndMissing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("variant-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try VariantInfo.load(dir))
        try Data(#"{"asr_version":"ultra","method":"4-bit palettization"}"#.utf8).write(to: dir.appendingPathComponent("variant.json"))
        XCTAssertEqual(try VariantInfo.load(dir), VariantInfo(asrVersion: "ultra", method: "4-bit palettization"))
    }

    func testFootprintIsPositiveAndGrowsWithAllocation() {
        guard let before = MemoryFootprint.current() else { return XCTFail("no footprint") }
        XCTAssertGreaterThan(before, 0)
        var big = [UInt8](repeating: 1, count: 64 << 20)
        big[big.count - 1] = 2
        let after = MemoryFootprint.current() ?? 0
        XCTAssertGreaterThan(after, before + (32 << 20))
        XCTAssertEqual(big.last, 2)
    }
}

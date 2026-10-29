import XCTest

/// The Mac app is sold separately from the iPhone/iPad app (ADR 0028, #176). App Store Connect joins platforms into one
/// Universal Purchase by bundle ID, so the two apps' IDs are what keeps the purchases apart.
final class AppStoreRecordTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Every PRODUCT_BUNDLE_IDENTIFIER an XcodeGen spec sets, in any target or configuration.
    private func bundleIDs(_ app: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String] {
        let spec = repoRoot.appendingPathComponent("Apps/\(app)/project.yml")
        let text = try String(contentsOf: spec, encoding: .utf8)
        let ids = text.split(separator: "\n").compactMap { raw -> String? in
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            guard let range = line.range(of: "PRODUCT_BUNDLE_IDENTIFIER:") else { return nil }
            return line[range.upperBound...].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'")))
        }
        XCTAssertFalse(ids.isEmpty, "Apps/\(app)/project.yml sets no PRODUCT_BUNDLE_IDENTIFIER", file: file, line: line)
        return ids
    }

    func testIPhoneAndIPadKeepTheLiveRecordsBundleID() throws {
        // 1.0 is live on the App Store under this ID. Changing it would orphan every buyer's purchase.
        XCTAssertEqual(Set(try bundleIDs("Spike")), ["com.gileskayo.captions"])
    }

    func testMacHasItsOwnBundleIDInEveryConfiguration() throws {
        // A Debug or Release override back to the iPhone ID would put the Mac build on the iPhone record again.
        XCTAssertEqual(Set(try bundleIDs("Mac")), ["com.gileskayo.captions.mac"])
    }

    func testNoBundleIDIsSharedBetweenMacAndIPhone() throws {
        XCTAssertTrue(Set(try bundleIDs("Mac")).isDisjoint(with: try bundleIDs("Spike")),
                      "a shared bundle ID makes the Mac a free Universal Purchase for iPhone buyers")
    }
}

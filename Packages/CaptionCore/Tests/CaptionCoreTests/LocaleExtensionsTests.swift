import XCTest
@testable import CaptionCore

final class LocaleExtensionsTests: XCTestCase {
    func testLocalizedDisplayName() {
        let locale = Locale(identifier: "es-ES")
        let name = locale.localizedDisplayName
        XCTAssertFalse(name.isEmpty)
        XCTAssertNotEqual(name, "es-ES")
    }

    func testLocalizedDisplayNameEnglish() {
        let locale = Locale(identifier: "en-US")
        let name = locale.localizedDisplayName
        XCTAssertFalse(name.isEmpty)
    }

    func testLocalizedDisplayNameFrench() {
        let locale = Locale(identifier: "fr-FR")
        let name = locale.localizedDisplayName
        XCTAssertFalse(name.isEmpty)
    }
}

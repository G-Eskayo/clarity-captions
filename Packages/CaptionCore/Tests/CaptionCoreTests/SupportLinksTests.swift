import XCTest
@testable import CaptionCore

final class SupportLinksTests: XCTestCase {
    func testLinksAreHTTPSAndPointAtThePages() {
        for (url, page) in [(SupportLinks.privacyPolicy, "privacy.html"), (SupportLinks.support, "support.html")] {
            XCTAssertEqual(url.scheme, "https", "\(url) must be https (App Store Connect and ATS both expect it)")
            XCTAssertNotNil(url.host, "\(url) must have a host")
            XCTAssertEqual(url.lastPathComponent, page)
            XCTAssertNil(url.query, "\(url) must not carry a query string (no tracking parameters)")
            XCTAssertNil(url.fragment)
        }
    }

    func testBothLinksShareOneBase() {
        // A later custom domain (#46) is a one-line change only if both pages hang off the same base.
        XCTAssertEqual(SupportLinks.privacyPolicy.deletingLastPathComponent(), SupportLinks.base)
        XCTAssertEqual(SupportLinks.support.deletingLastPathComponent(), SupportLinks.base)
    }

    func testBaseIsADirectorySoPagesResolveUnderIt() {
        // Without the trailing slash, appending "privacy.html" would replace the last path segment instead.
        XCTAssertTrue(SupportLinks.base.absoluteString.hasSuffix("/"))
    }

    func testEveryLinkedPageExistsInSite() {
        // The app links to pages the Pages workflow publishes from site/. A renamed or deleted page would ship a dead link.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for url in [SupportLinks.privacyPolicy, SupportLinks.support] {
            let page = repoRoot.appendingPathComponent("site").appendingPathComponent(url.lastPathComponent)
            XCTAssertTrue(FileManager.default.fileExists(atPath: page.path), "site/\(url.lastPathComponent) is missing")
        }
    }
}

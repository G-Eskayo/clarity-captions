import XCTest
@testable import CaptionCore

final class ThirdPartyNoticeTests: XCTestCase {
    func testThirdPartyNoticesAreComplete() {
        let notices = ThirdPartyNotice.all
        XCTAssertGreaterThanOrEqual(notices.count, 2, "Must include at least Sortformer and FluidAudio")

        for notice in notices {
            XCTAssertFalse(notice.id.isEmpty, "Each notice must have a non-empty id")
            XCTAssertFalse(notice.name.isEmpty, "Each notice must have a non-empty name")
            XCTAssertFalse(notice.licenseName.isEmpty, "Each notice must have a non-empty licenseName")
            XCTAssertFalse(notice.note.isEmpty, "Each notice must have a non-empty note")
        }
    }

    func testSortformerNoticeExists() {
        let sortformer = ThirdPartyNotice.all.first { $0.id == "sortformer" }
        XCTAssertNotNil(sortformer, "Sortformer notice must be present")
        XCTAssertEqual(sortformer?.licenseName, "CC BY 4.0")
        XCTAssertEqual(sortformer?.licenseURL.absoluteString, "https://creativecommons.org/licenses/by/4.0/")
    }

    func testFluidAudioNoticeExists() {
        let fluidAudio = ThirdPartyNotice.all.first { $0.id == "fluidaudio" }
        XCTAssertNotNil(fluidAudio, "FluidAudio notice must be present")
        XCTAssertEqual(fluidAudio?.licenseName, "Apache 2.0")
        XCTAssertEqual(fluidAudio?.licenseURL.absoluteString, "https://www.apache.org/licenses/LICENSE-2.0")
    }
}

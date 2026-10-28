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

    func testBundledFontsAreCreditedUnderTheirOwnLicenses() {
        // Classic OpenDyslexic (2.020, the face the approved mock-ups use) ships under the Bitstream Vera license;
        // Atkinson Hyperlegible under the SIL Open Font License.
        let expected = ["opendyslexic": "Bitstream Vera License", "atkinsonhyperlegible": "SIL OFL 1.1"]
        for (id, license) in expected {
            let notice = ThirdPartyNotice.all.first { $0.id == id }
            XCTAssertNotNil(notice, "\(id) is bundled in the app, so it must be credited")
            XCTAssertEqual(notice?.licenseName, license, id)
        }
        XCTAssertEqual(ThirdPartyNotice.all.first { $0.id == "atkinsonhyperlegible" }?.licenseURL.absoluteString, "https://openfontlicense.org")
    }

    func testEveryNoticeLinksToItsSource() {
        for notice in ThirdPartyNotice.all {
            XCTAssertNotNil(notice.sourceURL, "\(notice.name) should link to its source")
        }
        XCTAssertEqual(ThirdPartyNotice.all.first { $0.id == "sortformer" }?.sourceURL?.host, "huggingface.co")
    }

    func testParakeetUltraIsCreditedWithTheChangeNoted() throws {
        // CC BY 4.0: credit, a link to the license, and a note of changes (ADR 0025, design section 6).
        let notice = try XCTUnwrap(ThirdPartyNotice.all.first { $0.id == "parakeetultra" })
        XCTAssertEqual(notice.licenseName, "CC BY 4.0")
        XCTAssertEqual(notice.licenseURL.absoluteString, "https://creativecommons.org/licenses/by/4.0/")
        XCTAssertEqual(notice.sourceURL?.absoluteString, "https://huggingface.co/moondream/parakeet-ultra")
        for credit in ["Moondream", "NVIDIA", "FluidInference", "6 bits"] {
            XCTAssertTrue(notice.note.contains(credit), credit)
        }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let notices = try String(contentsOf: repo.appendingPathComponent("NOTICE.md"), encoding: .utf8)
        XCTAssertTrue(notices.contains("## Parakeet Ultra"))
        XCTAssertTrue(notices.contains("compressed to 6 bits"), "NOTICE.md notes the change")
    }
}

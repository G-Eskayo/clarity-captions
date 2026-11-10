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
        // NVIDIA's model card licenses Sortformer v2.1 under the NVIDIA Open Model License, not CC BY 4.0 (#271).
        let sortformer = ThirdPartyNotice.all.first { $0.id == "sortformer" }
        XCTAssertNotNil(sortformer, "Sortformer notice must be present")
        XCTAssertEqual(sortformer?.licenseName, "NVIDIA Open Model License")
        XCTAssertEqual(sortformer?.licenseURL.absoluteString,
                       "https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/")
        XCTAssertTrue(sortformer?.note.contains(Self.nvidiaNotice) ?? false, "the Notice line the license requires")
    }

    /// The attribution the NVIDIA Open Model License (section 3.1) requires in a "Notice" text file, word for word.
    static let nvidiaNotice = "Licensed by NVIDIA Corporation under the NVIDIA Open Model License"

    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testSortformerShipsTheAgreementAndANoticeFile() throws {
        // Redistributing the model: recipients get a copy of the agreement (NOTICE.md, shown in the app) and the
        // Notice line in a "Notice" text file, bundled in both apps beside the model.
        let notices = try String(contentsOf: repo.appendingPathComponent("NOTICE.md"), encoding: .utf8)
        let start = try XCTUnwrap(notices.range(of: "## Sortformer\n"), "NOTICE.md has a Sortformer section")
        let rest = notices[start.upperBound...]
        let section = rest.range(of: "\n## ").map { rest[..<$0.lowerBound] } ?? rest
        XCTAssertTrue(section.contains(Self.nvidiaNotice))
        XCTAssertTrue(section.contains("NVIDIA Open Model License Agreement"), "the agreement's own text")
        XCTAssertTrue(section.contains("Version Release Date: October 24, 2025"), "the whole agreement, to its end")
        XCTAssertFalse(section.contains("Creative Commons"), "the old CC BY 4.0 text is gone from this section")

        let file = try String(contentsOf: repo.appendingPathComponent("Licenses/Sortformer/NOTICE.txt"), encoding: .utf8)
        XCTAssertTrue(file.contains(Self.nvidiaNotice))
        for app in ["Spike", "Mac"] {
            let spec = try String(contentsOf: repo.appendingPathComponent("Apps/\(app)/project.yml"), encoding: .utf8)
            XCTAssertTrue(spec.contains("path: ../../Licenses/Sortformer"), "\(app) bundles the Notice file")
        }
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

    func testTheHebrewEngineIsCreditedWithTheChangeNoted() throws {
        // CC BY 4.0 (#220): credit the author and ivrit.ai, link the licence, and say what Seal changed.
        let notice = try XCTUnwrap(ThirdPartyNotice.all.first { $0.id == "hebrewzipformer" })
        XCTAssertEqual(notice.licenseName, "CC BY 4.0")
        XCTAssertEqual(notice.licenseURL.absoluteString, "https://creativecommons.org/licenses/by/4.0/")
        XCTAssertEqual(notice.sourceURL?.absoluteString, "https://huggingface.co/ivrit-ai/zipformer2-66m-streaming-he")
        for credit in ["Yakov Kolani", "ivrit.ai", "Core ML", "4 bits"] {
            XCTAssertTrue(notice.note.contains(credit), credit)
        }
        XCTAssertTrue(CreditsEntry.coveredByFullLicenseTexts.contains("hebrewzipformer"))
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let notices = try String(contentsOf: repo.appendingPathComponent("NOTICE.md"), encoding: .utf8)
        XCTAssertTrue(notices.contains("## Hebrew speech model (ivrit.ai zipformer)"))
        XCTAssertTrue(notices.contains("compressed to 4 bits"), "NOTICE.md notes the change")
    }
}

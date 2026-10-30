import XCTest
@testable import CaptionCore

/// The Mac has no caption-language setting yet and captions in US English (#220): Hebrew, on Seal's own engine, is
/// used only when the Mac's first language is Hebrew and the engine is in the app. Everything else stays as it was.
final class MacCaptionLanguageTests: XCTestCase {
    func testAHebrewMacWithTheEngineCaptionsHebrew() {
        XCTAssertEqual(MacCaptionLanguage.locale(preferred: ["he-IL", "en-US"], hebrewBundled: true).identifier(.bcp47), "he-IL")
        XCTAssertEqual(MacCaptionLanguage.locale(preferred: ["he"], hebrewBundled: true).identifier(.bcp47), "he-IL")
    }

    func testWithoutTheEngineOrWithAnotherFirstLanguageItStaysUSEnglish() {
        XCTAssertEqual(MacCaptionLanguage.locale(preferred: ["he-IL"], hebrewBundled: false).identifier(.bcp47), "en-US")
        XCTAssertEqual(MacCaptionLanguage.locale(preferred: ["en-GB", "he-IL"], hebrewBundled: true).identifier(.bcp47), "en-US")
        XCTAssertEqual(MacCaptionLanguage.locale(preferred: ["fr-FR"], hebrewBundled: true).identifier(.bcp47), "en-US")
        XCTAssertEqual(MacCaptionLanguage.locale(preferred: [], hebrewBundled: true).identifier(.bcp47), "en-US")
    }
}

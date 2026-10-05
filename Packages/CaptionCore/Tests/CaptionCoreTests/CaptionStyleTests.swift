import XCTest
@testable import CaptionCore

/// CONTEXT.md "Caption display settings": background color, text size, text color and font, independently
/// adjustable, offered simply (ADR 0013) and always readable (ADR 0013 accessibility bar).
final class CaptionStyleTests: XCTestCase {
    func testContrastRatioOfBlackOnWhiteIsTwentyOne() {
        XCTAssertEqual(RGBA.contrast(.black, .white), 21, accuracy: 0.01)
    }

    func testEveryPresetIsHighContrast() {
        for p in CaptionPreset.all {
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.text, p.background), 7, "\(p.name) is not readable enough")
        }
    }

    func testThereAreAFewPresetsNotAMenu() {
        XCTAssertTrue((3...6).contains(CaptionPreset.all.count))
        XCTAssertEqual(Set(CaptionPreset.all.map(\.id)).count, CaptionPreset.all.count, "preset ids must be unique")
    }

    func testApplyingAPresetKeepsSizeAndFont() {
        var style = CaptionStyle.standard
        style.size = .largest
        style.font = .serif
        let changed = style.applying(CaptionPreset.all[1])
        XCTAssertEqual(changed.background, CaptionPreset.all[1].background)
        XCTAssertEqual(changed.text, CaptionPreset.all[1].text)
        XCTAssertEqual(changed.size, .largest)
        XCTAssertEqual(changed.font, .serif)
    }

    func testSizeStepsAreIncreasingAndClampAtTheEnds() {
        XCTAssertEqual(CaptionTextSize.largest.larger(), .largest)
        XCTAssertEqual(CaptionTextSize.smallest.smaller(), .smallest)
        XCTAssertEqual(CaptionTextSize.medium.larger(), .large)
        XCTAssertEqual(CaptionTextSize.medium.smaller(), .small)
    }

    func testMediumStepEqualsSystemDefaultAtLarge() {
        let result = CaptionTextSize.medium.pointSize(for: .large)
        XCTAssertEqual(result, 28, accuracy: 0.01)
    }

    func testSizeStepsAreMonotonicAcrossEveryCategory() {
        for category in SystemTextSizeCategory.allCases {
            let points = CaptionTextSize.allCases.map { size in size.pointSize(for: category) }
            XCTAssertEqual(points, points.sorted(), "sizes not monotonic for category \(category)")
            XCTAssertEqual(Set(points).count, points.count, "duplicate point sizes for category \(category)")
        }
    }

    func testSystemTextSizeCategoryHasAllTwelveCategories() {
        XCTAssertEqual(SystemTextSizeCategory.allCases.count, 12)
    }

    func testStyleRoundTripsThroughTheStore() {
        let defaults = UserDefaults(suiteName: "caption-style-test-\(UUID())")!
        let store = CaptionStyleStore(defaults: defaults)
        var style = CaptionStyle.standard.applying(CaptionPreset.all[2])
        style.size = .large
        style.font = .rounded
        store.save(style)
        XCTAssertEqual(store.load(), style)
    }

    func testNothingSavedMeansTheStandardStyle() {
        let store = CaptionStyleStore(defaults: UserDefaults(suiteName: "caption-style-test-\(UUID())")!)
        XCTAssertEqual(store.load(), .standard)
    }

    func testCorruptSavedDataFallsBackToTheStandardStyle() {
        let defaults = UserDefaults(suiteName: "caption-style-test-\(UUID())")!
        defaults.set(Data("not json".utf8), forKey: CaptionStyleStore.key)
        XCTAssertEqual(CaptionStyleStore(defaults: defaults).load(), .standard)
    }

    func testStandardStyleIsReadable() {
        XCTAssertGreaterThanOrEqual(RGBA.contrast(CaptionStyle.standard.text, CaptionStyle.standard.background), 7)
    }

    func testDimmedCaptionStaysHighContrast() {
        let dimmedAlpha = CaptionLine.volatileOpacity
        for p in CaptionPreset.all {
            // the text itself is faded to dimmedAlpha, then seen against the opaque background
            let dimmedText = RGBA(p.text.r, p.text.g, p.text.b, dimmedAlpha).composited(over: p.background)
            let contrast = RGBA.contrast(dimmedText, p.background)
            XCTAssertGreaterThanOrEqual(contrast, 4.5, "\(p.name) dimmed is not readable enough at opacity \(dimmedAlpha)")
        }
    }
}

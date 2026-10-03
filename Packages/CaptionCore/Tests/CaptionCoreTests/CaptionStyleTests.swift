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
        style.size = .extraLarge
        style.font = .serif
        let changed = style.applying(CaptionPreset.all[1])
        XCTAssertEqual(changed.background, CaptionPreset.all[1].background)
        XCTAssertEqual(changed.text, CaptionPreset.all[1].text)
        XCTAssertEqual(changed.size, .extraLarge)
        XCTAssertEqual(changed.font, .serif)
    }

    func testSizeStepsAreIncreasingAndClampAtTheEnds() {
        let points = CaptionTextSize.allCases.map(\.points)
        XCTAssertEqual(points, points.sorted())
        XCTAssertEqual(Set(points).count, points.count)
        XCTAssertEqual(CaptionTextSize.extraLarge.larger(), .extraLarge)
        XCTAssertEqual(CaptionTextSize.small.smaller(), .small)
        XCTAssertEqual(CaptionTextSize.medium.larger(), .large)
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
}

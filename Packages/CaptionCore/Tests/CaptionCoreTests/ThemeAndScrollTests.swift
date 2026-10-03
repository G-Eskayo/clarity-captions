import XCTest
@testable import CaptionCore

/// A look restyles the whole app, so everything drawn on it must stay readable on every look.
final class ThemeTests: XCTestCase {
    func testDarkAndLightBackgroundsAreTold() {
        XCTAssertTrue(CaptionPreset.all.first { $0.id == "classic" }!.background.isDark)
        XCTAssertTrue(CaptionPreset.all.first { $0.id == "night" }!.background.isDark)
        XCTAssertFalse(CaptionPreset.all.first { $0.id == "paper" }!.background.isDark)
    }

    func testSpeakerColorsAreReadableOnEveryLook() {
        for p in CaptionPreset.all {
            let colors = SpeakerPalette.colors(on: p.background, text: p.text)
            XCTAssertEqual(colors.count, 4, "\(p.name) needs a color per speaker slot")
            for c in colors {
                XCTAssertGreaterThanOrEqual(RGBA.contrast(c, p.background), 4.5, "\(p.name): speaker color too faint")
            }
        }
    }

    func testSpeakerColorsAreDistinctFromEachOther() {
        for p in CaptionPreset.all {
            let colors = SpeakerPalette.colors(on: p.background, text: p.text)
            XCTAssertEqual(Set(colors.map { "\($0.r),\($0.g),\($0.b)" }).count, 4, "\(p.name) repeats a speaker color")
        }
    }
}

final class AutoScrollTests: XCTestCase {
    func testAtTheBottomMeansFollow() {
        XCTAssertTrue(AutoScroll.shouldFollow(offsetY: 600, viewportHeight: 400, contentHeight: 1000))
    }

    func testWithinAFewPointsOfTheBottomStillFollows() {
        XCTAssertTrue(AutoScroll.shouldFollow(offsetY: 570, viewportHeight: 400, contentHeight: 1000))
    }

    func testScrolledBackStopsFollowing() {
        XCTAssertFalse(AutoScroll.shouldFollow(offsetY: 200, viewportHeight: 400, contentHeight: 1000))
    }

    func testContentShorterThanTheScreenAlwaysFollows() {
        XCTAssertTrue(AutoScroll.shouldFollow(offsetY: 0, viewportHeight: 800, contentHeight: 300))
    }

    func testElasticOverscrollAtTheBottomStillFollows() {
        XCTAssertTrue(AutoScroll.shouldFollow(offsetY: 640, viewportHeight: 400, contentHeight: 1000))
    }
}

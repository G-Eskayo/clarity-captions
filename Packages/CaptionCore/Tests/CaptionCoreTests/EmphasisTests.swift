import XCTest
@testable import CaptionCore

final class EmphasisTests: XCTestCase {
    func testClassifierReturnsNoneDuringColdStart() {
        let classifier = EmphasisClassifier()
        var baseline = LoudnessBaseline()
        baseline.feed(-10.0)
        let level = classifier.classify(level: -5.0, baseline: baseline)
        XCTAssertEqual(level, .none)
    }

    func testClassifierReturnsCorrectLevelWhenTrusted() {
        let classifier = EmphasisClassifier()
        var baseline = LoudnessBaseline()
        baseline.feed(-10.0)
        baseline.feed(-10.0)
        baseline.feed(-10.0)
        XCTAssertTrue(baseline.isTrusted)

        XCTAssertEqual(classifier.classify(level: -10.0, baseline: baseline), .none)
        XCTAssertEqual(classifier.classify(level: -7.0, baseline: baseline), .raised)
        XCTAssertEqual(classifier.classify(level: -4.0, baseline: baseline), .loud)
    }

    func testClassifierHandlesQuietBaseline() {
        let classifier = EmphasisClassifier()
        var baseline = LoudnessBaseline()
        baseline.feed(-30.0)
        baseline.feed(-30.0)
        baseline.feed(-30.0)

        XCTAssertEqual(classifier.classify(level: -30.0, baseline: baseline), .none)
        XCTAssertEqual(classifier.classify(level: -27.0, baseline: baseline), .raised)
    }

    func testStyleForNone() {
        let style = EmphasisStyle.style(for: .none, background: .black, text: .white)
        XCTAssertEqual(style.fontWeight, 400)
        XCTAssertEqual(style.sizeMultiplier, 1.0)
        XCTAssertEqual(style.accentColor, .white)
    }

    func testStyleForRaised() {
        let style = EmphasisStyle.style(for: .raised, background: .black, text: .white)
        XCTAssertEqual(style.fontWeight, 600)
        XCTAssertEqual(style.sizeMultiplier, 1.05)
        XCTAssertNotEqual(style.accentColor, .white)
    }

    func testStyleForLoud() {
        let style = EmphasisStyle.style(for: .loud, background: .black, text: .white)
        XCTAssertEqual(style.fontWeight, 700)
        XCTAssertEqual(style.sizeMultiplier, 1.12)
        XCTAssertNotEqual(style.accentColor, .white)
    }

    func testEmphasisStyleMaintainsContrast() {
        for preset in CaptionPreset.all {
            for level: EmphasisLevel in [.none, .raised, .loud] {
                let style = EmphasisStyle.style(for: level, background: preset.background, text: preset.text)
                let contrast = RGBA.contrast(style.accentColor, preset.background)
                XCTAssertGreaterThanOrEqual(contrast, 4.5, "\(preset.name) \(level) contrast too low: \(contrast)")
            }
        }
    }
}

import XCTest
@testable import FluidAudio

/// Regression test: verify that text-processing-rs (NemoTextProcessing) is not linked
/// when the FluidAudio dependency uses `traits: []` to opt out (#32).
final class TextProcessingOptOutTests: XCTestCase {
    func testTextNormalizerIsDisabledWhenOptedOut() {
        // FluidAudio's TextNormalizer.isNativeAvailable is false when NemoTextProcessing
        // was excluded via traits. This test prevents regression: if someone re-adds
        // the text-processing trait, this test will fail immediately.
        let normalizer = TextNormalizer.shared
        XCTAssertFalse(TextNormalizer.isNativeAvailable,
                       "NemoTextProcessing binary must be excluded via traits: [] in Package.swift (#32)")
    }

    func testTextNormalizerReturnsInputUnchanged() {
        let normalizer = TextNormalizer.shared
        let input = "two hundred dollars"
        let result = normalizer.normalize(input)
        XCTAssertEqual(result, input,
                       "Without the NemoTextProcessing engine, normalization must be a no-op")
    }

    func testTextNormalizationRulesIgnoredWithoutEngine() {
        let normalizer = TextNormalizer.shared
        let testCases = [
            ("two hundred", "two hundred"),
            ("january fifth", "january fifth"),
            ("five dollars", "five dollars"),
        ]
        for (input, expected) in testCases {
            XCTAssertEqual(normalizer.normalize(input), expected,
                           "Input: \(input)")
        }
    }
}

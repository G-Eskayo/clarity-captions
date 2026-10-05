import XCTest
@testable import CaptionCore

final class SoundLabelTests: XCTestCase {
    // MARK: - SoundLabelKind init from classifier identifier

    func testIdentifierMappingLaughter() {
        XCTAssertEqual(SoundLabelKind(classifierIdentifier: "laughter"), .laughter)
    }

    func testIdentifierMappingApplause() {
        XCTAssertEqual(SoundLabelKind(classifierIdentifier: "applause"), .applause)
    }

    func testIdentifierMappingDoorbell() {
        XCTAssertEqual(SoundLabelKind(classifierIdentifier: "doorbell"), .doorbell)
    }

    func testIdentifierMappingPhoneRinging() {
        XCTAssertEqual(SoundLabelKind(classifierIdentifier: "telephone_bell_ringing"), .phoneRinging)
    }

    func testIdentifierMappingKnock() {
        XCTAssertEqual(SoundLabelKind(classifierIdentifier: "knock"), .knock)
    }

    func testUnknownIdentifierReturnsNil() {
        XCTAssertNil(SoundLabelKind(classifierIdentifier: "unknown_sound"))
        XCTAssertNil(SoundLabelKind(classifierIdentifier: ""))
        XCTAssertNil(SoundLabelKind(classifierIdentifier: "glass_breaking"))
    }

    // MARK: - Display text

    func testDisplayTextLaughter() {
        XCTAssertEqual(SoundLabelKind.laughter.displayText, "Laughter")
    }

    func testDisplayTextApplause() {
        XCTAssertEqual(SoundLabelKind.applause.displayText, "Applause")
    }

    func testDisplayTextDoorbell() {
        XCTAssertEqual(SoundLabelKind.doorbell.displayText, "Doorbell")
    }

    func testDisplayTextPhoneRinging() {
        XCTAssertEqual(SoundLabelKind.phoneRinging.displayText, "Phone ringing")
    }

    func testDisplayTextKnock() {
        XCTAssertEqual(SoundLabelKind.knock.displayText, "Knocking")
    }

    // MARK: - Formatter

    func testFormatterBracketsOutput() {
        XCTAssertEqual(SoundLabelFormatter.caption(for: .laughter), "[Laughter]")
        XCTAssertEqual(SoundLabelFormatter.caption(for: .applause), "[Applause]")
        XCTAssertEqual(SoundLabelFormatter.caption(for: .doorbell), "[Doorbell]")
        XCTAssertEqual(SoundLabelFormatter.caption(for: .phoneRinging), "[Phone ringing]")
        XCTAssertEqual(SoundLabelFormatter.caption(for: .knock), "[Knocking]")
    }

    // MARK: - SoundLabelDetector: threshold

    func testThresholdRejectsBelowThreshold() {
        var detector = SoundLabelDetector(threshold: 0.65)
        let result = detector.label(identifier: "laughter", confidence: 0.64, at: 1.0)
        XCTAssertNil(result)
    }

    func testThresholdAcceptsAtThreshold() {
        var detector = SoundLabelDetector(threshold: 0.65)
        let result = detector.label(identifier: "laughter", confidence: 0.65, at: 1.0)
        XCTAssertEqual(result, .laughter)
    }

    func testThresholdAcceptsAboveThreshold() {
        var detector = SoundLabelDetector(threshold: 0.65)
        let result = detector.label(identifier: "laughter", confidence: 0.90, at: 1.0)
        XCTAssertEqual(result, .laughter)
    }

    // MARK: - SoundLabelDetector: debouncing

    func testDebounceSuppressionWithinWindow() {
        var detector = SoundLabelDetector(threshold: 0.65, debounceSeconds: 3.0)
        let first = detector.label(identifier: "laughter", confidence: 0.8, at: 1.0)
        let second = detector.label(identifier: "laughter", confidence: 0.8, at: 2.5)
        XCTAssertEqual(first, .laughter)
        XCTAssertNil(second)
    }

    func testDebounceAllowsAfterWindowExpires() {
        var detector = SoundLabelDetector(threshold: 0.65, debounceSeconds: 3.0)
        let first = detector.label(identifier: "laughter", confidence: 0.8, at: 1.0)
        let second = detector.label(identifier: "laughter", confidence: 0.8, at: 4.1)
        XCTAssertEqual(first, .laughter)
        XCTAssertEqual(second, .laughter)
    }

    func testDebounceAllowsDifferentSounds() {
        var detector = SoundLabelDetector(threshold: 0.65, debounceSeconds: 3.0)
        let first = detector.label(identifier: "laughter", confidence: 0.8, at: 1.0)
        let second = detector.label(identifier: "applause", confidence: 0.8, at: 1.5)
        XCTAssertEqual(first, .laughter)
        XCTAssertEqual(second, .applause)
    }

    func testDebounceStateIsUpdatedOnEmission() {
        var detector = SoundLabelDetector(threshold: 0.65, debounceSeconds: 3.0)
        detector.label(identifier: "laughter", confidence: 0.8, at: 1.0)
        detector.label(identifier: "laughter", confidence: 0.8, at: 2.0)
        let third = detector.label(identifier: "laughter", confidence: 0.8, at: 2.5)
        XCTAssertNil(third)

        let fourth = detector.label(identifier: "laughter", confidence: 0.8, at: 5.1)
        XCTAssertEqual(fourth, .laughter)
    }

    func testDebounceExactWindowBoundary() {
        var detector = SoundLabelDetector(threshold: 0.65, debounceSeconds: 3.0)
        detector.label(identifier: "laughter", confidence: 0.8, at: 1.0)
        // At exactly 4.0s (3.0s after 1.0s), the debounce window has elapsed: 4.0 - 1.0 = 3.0, and 3.0 < 3.0 is false
        let second = detector.label(identifier: "laughter", confidence: 0.8, at: 4.0)
        XCTAssertEqual(second, .laughter)
        // Any sound within the next 3s is suppressed
        let third = detector.label(identifier: "laughter", confidence: 0.8, at: 6.5)
        XCTAssertNil(third)
        let fourth = detector.label(identifier: "laughter", confidence: 0.8, at: 7.1)
        XCTAssertEqual(fourth, .laughter)
    }

    // MARK: - Unknown identifier in detector

    func testDetectorRejectsUnknownIdentifier() {
        var detector = SoundLabelDetector(threshold: 0.65)
        let result = detector.label(identifier: "glass_breaking", confidence: 0.9, at: 1.0)
        XCTAssertNil(result)
    }

    func testDetectorRejectsUnknownEvenWithHighConfidence() {
        var detector = SoundLabelDetector(threshold: 0.65)
        let result = detector.label(identifier: "unknown", confidence: 0.99, at: 1.0)
        XCTAssertNil(result)
    }
}

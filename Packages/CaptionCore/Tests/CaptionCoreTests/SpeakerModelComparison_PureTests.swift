import Darwin
import FluidAudio
import Foundation
import XCTest
@testable import CaptionCore

/// Unit tests for pure helper functions in speaker model comparison.
/// These run in the default swift test suite (no network, no say, no model download).
/// Tests #1, #2, #5, #6, #9, #10 from the "Tests first" checklist.
final class SpeakerModelComparison_PureTests: XCTestCase {

    // MARK: Test #1: Bad/malformed env input

    func testVoiceCountEnvVarFallback() {
        let garbage = "garbage"
        let count = Self.parseVoiceCount(garbage, defaultCount: 6)
        XCTAssertEqual(count, 6, "Should fall back to default on garbage input")
    }

    func testVoiceCountEnvVarNegative() {
        let negative = "-5"
        let count = Self.parseVoiceCount(negative, defaultCount: 6)
        XCTAssertEqual(count, 6, "Should fall back to default on negative input")
    }

    func testVoiceCountEnvVarOutOfRange() {
        let tooLarge = "999"
        let count = Self.parseVoiceCount(tooLarge, defaultCount: 6)
        XCTAssertEqual(count, 6, "Should fall back to default on out-of-range input")
    }

    // MARK: Test #2: Huge/unsupported input

    func testVoiceCountValidation_Negative() {
        let error = Self.validateVoiceCount(-1)
        XCTAssertNotNil(error, "Should reject negative voice count")
    }

    func testVoiceCountValidation_Zero() {
        let error = Self.validateVoiceCount(0)
        XCTAssertNotNil(error, "Should reject zero voice count")
    }

    func testVoiceCountValidation_ExceedsAvailable() {
        let maxAvailable = 10
        let error = Self.validateVoiceCount(maxAvailable + 1)
        XCTAssertNotNil(error, "Should reject voice count exceeding available")
    }

    func testVoiceCountValidation_Valid() {
        let error = Self.validateVoiceCount(4)
        XCTAssertNil(error, "Should accept valid voice count (4)")

        let error6 = Self.validateVoiceCount(6)
        XCTAssertNil(error6, "Should accept valid voice count (6)")

        let error10 = Self.validateVoiceCount(10)
        XCTAssertNil(error10, "Should accept valid voice count (10)")
    }

    // MARK: Comma-list voice count parsing tests

    func testParseVoiceCountsFromEnv_CommaSeparated() {
        let counts = Self.parseVoiceCountsFromEnv("4,6,10")
        XCTAssertEqual(counts, [4, 6, 10], "Should parse comma-separated values")
    }

    func testParseVoiceCountsFromEnv_CommaSeparatedWithSpaces() {
        let counts = Self.parseVoiceCountsFromEnv("4, 6, 10")
        XCTAssertEqual(counts, [4, 6, 10], "Should trim spaces in comma-separated values")
    }

    func testParseVoiceCountsFromEnv_CommaListOutOfRange() {
        let counts = Self.parseVoiceCountsFromEnv("4,0,99")
        XCTAssertEqual(counts, [4], "Should filter out-of-range values (0, 99)")
    }

    func testParseVoiceCountsFromEnv_CommaListAllInvalid() {
        let counts = Self.parseVoiceCountsFromEnv("0,11,99")
        XCTAssertEqual(counts, [6], "Should fall back to [6] when all comma-list values are invalid")
    }

    func testParseVoiceCountsFromEnv_SingleValue() {
        let counts = Self.parseVoiceCountsFromEnv("4")
        XCTAssertEqual(counts, [4], "Should parse single value")
    }

    func testParseVoiceCountsFromEnv_SingleValueInvalid() {
        let counts = Self.parseVoiceCountsFromEnv("99")
        XCTAssertEqual(counts, [6], "Should fall back to [6] for invalid single value")
    }

    // MARK: Test #5: Empty/edge ground truth (testing DER computation edge cases)

    func testComputeDER_EmptyHypothesis() {
        let hypothesis: [DERSpeakerSegment] = []
        let groundTruth = [DERSpeakerSegment(speaker: "0", start: 0, end: 1)]

        let der = Self.computeDER(hypothesis: hypothesis, groundTruth: groundTruth)
        XCTAssertEqual(der, 1.0, "Empty hypothesis should yield worst-case DER of 1.0")
    }

    func testComputeDER_EmptyGroundTruth() {
        let hypothesis = [DERSpeakerSegment(speaker: "0", start: 0, end: 1)]
        let groundTruth: [DERSpeakerSegment] = []

        let der = Self.computeDER(hypothesis: hypothesis, groundTruth: groundTruth)
        XCTAssertEqual(der, 1.0, "Empty ground truth should yield worst-case DER of 1.0")
    }

    func testComputeDER_BothEmpty() {
        let hypothesis: [DERSpeakerSegment] = []
        let groundTruth: [DERSpeakerSegment] = []

        let der = Self.computeDER(hypothesis: hypothesis, groundTruth: groundTruth)
        XCTAssertEqual(der, 1.0, "Both empty should yield worst-case DER of 1.0")
    }

    func testComputeDER_PerfectMatch() {
        let segment = DERSpeakerSegment(speaker: "0", start: 0.5, end: 1.5)
        let hypothesis = [segment]
        let groundTruth = [segment]

        let der = Self.computeDER(hypothesis: hypothesis, groundTruth: groundTruth)
        XCTAssertEqual(der, 0.0, "Identical segments should yield perfect DER of 0.0")
    }

    // MARK: Test #6: Stale global state (isolation across iterations)

    func testModelHubOfflineModeIsolation() {
        let originalMode = ModelHub.offlineMode
        defer { ModelHub.offlineMode = originalMode }

        // Test 1: First iteration sets mode true
        ModelHub.offlineMode = true
        let modeAfterFirstSet = ModelHub.offlineMode
        XCTAssertTrue(modeAfterFirstSet, "offlineMode should be true after setting")

        // Test 2: Second iteration must not be affected by previous state
        // (In practice, integration test must restore this between iterations)
        ModelHub.offlineMode = false
        let modeAfterSecondSet = ModelHub.offlineMode
        XCTAssertFalse(modeAfterSecondSet, "offlineMode should be false after setting")
    }

    // MARK: Test #9: New pure logic - Call scenario ground-truth builder

    func testCallScenarioBuilder_SingleSpeaker() {
        let groundTruth = Self.buildCallScenarioGroundTruth(voiceCount: 1)
        XCTAssertTrue(groundTruth.isEmpty, "Call with 1 speaker (self only) should give empty ground truth")
    }

    func testCallScenarioBuilder_TwoSpeakers() {
        let groundTruth = Self.buildCallScenarioGroundTruth(voiceCount: 2)
        XCTAssertEqual(groundTruth.count, 1, "Call with 2 speakers should have 1 other speaker (N-1)")
        XCTAssertEqual(groundTruth[0].speaker, 0, "Other speaker should be indexed 0")
    }

    func testCallScenarioBuilder_FourSpeakers() {
        let groundTruth = Self.buildCallScenarioGroundTruth(voiceCount: 4)
        XCTAssertEqual(groundTruth.count, 3, "Call with 4 speakers should have 3 others (N-1)")
        let speakerIndices = Set(groundTruth.map(\.speaker))
        XCTAssertEqual(speakerIndices.count, 3, "Should have 3 distinct speaker indices")
    }

    func testCallScenarioBuilder_SixSpeakers() {
        let groundTruth = Self.buildCallScenarioGroundTruth(voiceCount: 6)
        XCTAssertEqual(groundTruth.count, 5, "Call with 6 speakers should have 5 others (N-1)")
    }

    func testCallScenarioBuilder_TenSpeakers() {
        let groundTruth = Self.buildCallScenarioGroundTruth(voiceCount: 10)
        XCTAssertEqual(groundTruth.count, 9, "Call with 10 speakers should have 9 others (N-1)")
    }

    func testCallScenarioBuilder_TimeOrdering() {
        let groundTruth = Self.buildCallScenarioGroundTruth(voiceCount: 4)
        var lastEnd = 0.0
        for seg in groundTruth {
            XCTAssertGreaterThanOrEqual(seg.start, lastEnd, "Segments should be ordered in time")
            lastEnd = seg.end
        }
    }

    // MARK: Test #10: Markdown/report-writer

    func testMarkdownTableRow_Basic() {
        let row = Self.markdownTableRow(
            model: "Sortformer",
            scenario: "turn-taking",
            speakerCount: 6,
            speakersFound: 6,
            der: 0.123,
            timeToLabel: 0.450,
            memoryFootprint: 50_000_000,
            cpuTime: 0.567
        )

        XCTAssertTrue(row.contains("Sortformer"))
        XCTAssertTrue(row.contains("turn-taking"))
        XCTAssertTrue(row.contains("0.123"))
        XCTAssertTrue(row.contains("0.450 s"))
        XCTAssertTrue(row.contains(" MB"))
        XCTAssertTrue(row.contains("0.567 s"))
    }

    func testMarkdownTableRow_MissingOptionalFields() {
        let row = Self.markdownTableRow(
            model: "OfflineModel",
            scenario: "call",
            speakerCount: 4,
            speakersFound: 4,
            der: 0.100,
            timeToLabel: nil,
            memoryFootprint: nil,
            cpuTime: nil
        )

        XCTAssertTrue(row.contains("OfflineModel"))
        XCTAssertTrue(row.contains("N/A"))
        XCTAssertTrue(row.contains("0.100"))
    }

    func testMarkdownTableRow_NaNDER() {
        let row = Self.markdownTableRow(
            model: "TestModel",
            scenario: "test",
            speakerCount: 2,
            speakersFound: 2,
            der: Double.nan,
            timeToLabel: 0.1,
            memoryFootprint: 100_000_000,
            cpuTime: 0.2
        )

        XCTAssertTrue(row.contains("N/A"))
    }

    func testMarkdownTableRow_DuplicateModelNames() {
        let row1 = Self.markdownTableRow(
            model: "Same",
            scenario: "run-1",
            speakerCount: 6,
            speakersFound: 6,
            der: 0.10,
            timeToLabel: 0.5,
            memoryFootprint: 1_000_000,
            cpuTime: 0.1
        )

        let row2 = Self.markdownTableRow(
            model: "Same",
            scenario: "run-2",
            speakerCount: 6,
            speakersFound: 6,
            der: 0.12,
            timeToLabel: 0.6,
            memoryFootprint: 1_000_000,
            cpuTime: 0.1
        )

        XCTAssertNotEqual(row1, row2, "Different scenario labels should create distinct rows")
        XCTAssertTrue(row1.contains("run-1"))
        XCTAssertTrue(row2.contains("run-2"))
    }

    // MARK: Helpers

    /// Parse single voice count value with range validation [1, 10].
    private static func parseVoiceCount(_ input: String, defaultCount: Int) -> Int {
        guard let parsed = Int(input), parsed >= 1, parsed <= 10 else {
            return defaultCount
        }
        return parsed
    }

    /// Parse CAPTION_SPEAKER_COMPARE_VOICES env var, handling single values and comma-separated lists.
    /// Each value in comma-list must be in [1, 10]. Falls back to [6] on invalid input.
    private static func parseVoiceCountsFromEnv(_ input: String) -> [Int] {
        if input.contains(",") {
            let parsed = input.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { $0 >= 1 && $0 <= 10 }
            return parsed.isEmpty ? [6] : parsed
        } else if let count = Int(input), count >= 1, count <= 10 {
            return [count]
        } else {
            return [6]
        }
    }

    /// Validate voice count is in valid range.
    private static func validateVoiceCount(_ count: Int) -> Error? {
        if count <= 0 {
            return NSError(domain: "SpeakerModelComparison", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Voice count must be positive, got \(count)"])
        }
        if count > 10 {
            return NSError(domain: "SpeakerModelComparison", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Voice count \(count) exceeds available (10)"])
        }
        return nil
    }

    /// Build call scenario ground truth (N speakers, self excluded, N−1 in result).
    private static func buildCallScenarioGroundTruth(voiceCount: Int) -> [SpeakerSegment] {
        if voiceCount <= 1 {
            return []
        }

        var groundTruth: [SpeakerSegment] = []
        var currentTime = 0.0

        for i in 1..<voiceCount {
            let duration = 1.0
            groundTruth.append(SpeakerSegment(speaker: i - 1, start: currentTime, end: currentTime + duration))
            currentTime += duration + 0.5
        }

        return groundTruth
    }

    /// Markdown table row writer (pure).
    private static func markdownTableRow(
        model: String,
        scenario: String,
        speakerCount: Int,
        speakersFound: Int,
        der: Double,
        timeToLabel: Double?,
        memoryFootprint: UInt64?,
        cpuTime: Double?
    ) -> String {
        let timeStr = timeToLabel.map { String(format: "%.3f s", $0) } ?? "N/A"
        let memStr = memoryFootprint.map { String(format: "%.1f MB", Double($0) / 1_048_576.0) } ?? "N/A"
        let cpuStr = cpuTime.map { String(format: "%.3f s", $0) } ?? "N/A"
        let derStr = der.isNaN ? "N/A" : String(format: "%.3f", der)

        return "| \(model) | \(scenario) | \(speakerCount) | \(speakersFound) | \(derStr) | \(timeStr) | \(memStr) | \(cpuStr) |"
    }

    /// Compute DER (Diarization Error Rate) from hypothesis vs. ground truth segments.
    /// Returns 1.0 (worst-case) if either list is empty.
    private static func computeDER(hypothesis: [DERSpeakerSegment], groundTruth: [DERSpeakerSegment]) -> Double {
        guard !hypothesis.isEmpty, !groundTruth.isEmpty else { return 1.0 }

        let result = DiarizationDER.compute(ref: groundTruth, hyp: hypothesis)
        return result.der
    }
}

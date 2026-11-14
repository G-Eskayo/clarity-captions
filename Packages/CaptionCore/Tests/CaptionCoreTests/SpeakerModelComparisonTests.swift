import AVFoundation
import Darwin
import FluidAudio
import Foundation
import XCTest
@testable import CaptionCore

/// Speaker diarization model comparison: Sortformer vs. LS-EEND variants on synthetic voices.
/// Run with: CAPTION_SPEAKER_COMPARE=1 swift test --filter SpeakerModelComparison
/// Synthesizes distinct voices with scripted turn-taking and overlap, feeds into bundled and
/// optional diarizers, and compares speakers found, DER (via FluidAudio's DiarizationDER.compute),
/// and time-to-label. Network access optional for optional model downloads.
final class SpeakerModelComparisonTests: XCTestCase {
    private func synth(voice: String, text: String) throws -> [Float] {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID()).wav")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@16000", text]
        try p.run(); p.waitUntilExit()

        guard p.terminationStatus == 0 else {
            throw NSError(domain: "SpeakerModelComparisonTests", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to synthesize voice: \(voice)"])
        }

        let file = try AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    }

    /// Available English voices on macOS (from `say -v '?'`).
    /// Fail loudly if the system has fewer than needed for a given scenario.
    private static let voicesCatalog = [
        "Samantha", "Daniel", "Karen", "Alex", "Victoria", "Fred",
        "Agnes", "Albert", "Bruce", "Junior"
    ]

    /// Scenario: turn-taking conversation (two voices in overlap).
    private func buildTestAudio(voiceCount: Int) throws -> (audio: [Float], groundTruth: [SpeakerSegment]) {
        guard voiceCount >= 1, voiceCount <= Self.voicesCatalog.count else {
            throw NSError(domain: "SpeakerModelComparisonTests", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Requested \(voiceCount) voices; only \(Self.voicesCatalog.count) available"])
        }

        let silence = [Float](repeating: 0, count: 8000)
        var audio: [Float] = []
        var groundTruth: [SpeakerSegment] = []
        let timePerSample = 1.0 / 16000.0

        let utterances = [
            "Hello, I just arrived for dinner. How has your week been so far?",
            "Pretty good. Work was busy but I got through it all right.",
            "That sounds about right. I have been meaning to ask you both about next month.",
            "Sure, what is on your mind?",
            "I was thinking we could all plan a trip together if everyone is interested.",
            "That sounds like a great idea to me. When were you thinking?",
            "I really appreciate your enthusiasm about this trip.",
            "Should we plan the dates soon, or can we think about it more?",
            "I am flexible with timing and can adjust as needed.",
            "Great, let us all share our calendars then.",
        ]

        let selectedVoices = Array(Self.voicesCatalog.prefix(voiceCount))
        let selectedUtterances = Array(utterances.prefix(voiceCount))

        for (i, (voice, text)) in zip(selectedVoices, selectedUtterances).enumerated() {
            let startTime = Double(audio.count) * timePerSample
            let synth = try self.synth(voice: voice, text: text)
            audio += synth
            audio += silence
            let endTime = Double(audio.count) * timePerSample
            groundTruth.append(SpeakerSegment(speaker: i, start: startTime, end: endTime))
        }

        // Add an overlap window: sum first two voices
        if voiceCount >= 2 {
            let overlapStart = Double(audio.count) * timePerSample
            let speech1 = try synth(voice: selectedVoices[0], text: "This is going to be wonderful.")
            let speech2 = try synth(voice: selectedVoices[1], text: "I absolutely agree with you.")

            let minLen = min(speech1.count, speech2.count)
            let overlapWindow = (0..<minLen).map { i -> Float in
                let combined = (speech1[i] + speech2[i]) / 2.0
                return min(1.0, max(-1.0, combined))
            }

            audio += overlapWindow
            audio += silence

            let overlapEnd = Double(audio.count) * timePerSample
            groundTruth.append(SpeakerSegment(speaker: 0, start: overlapStart, end: overlapEnd))
        }

        return (audio, groundTruth)
    }

    /// Parse CAPTION_SPEAKER_COMPARE_VOICES env var, handling single values and comma-separated lists.
    /// Validates each voice count is in [1, 10]. Falls back to [6] on invalid input.
    private func parseVoiceCountsFromEnv(_ input: String) -> [Int] {
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

    /// Scenario: N speakers, excluding self (N−1 distinct speakers to classify).
    /// Ground truth: each speaker except self speaks once, then silence.
    /// For N=1, returns empty ground truth (nothing to compare).
    private func buildCallScenarioGroundTruth(voiceCount: Int) throws -> [SpeakerSegment] {
        guard voiceCount >= 1, voiceCount <= Self.voicesCatalog.count else {
            throw NSError(domain: "SpeakerModelComparisonTests", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Call scenario: requested \(voiceCount) voices; only \(Self.voicesCatalog.count) available"])
        }

        if voiceCount == 1 {
            return []
        }

        let silence = [Float](repeating: 0, count: 8000)
        var audio: [Float] = []
        var groundTruth: [SpeakerSegment] = []
        let timePerSample = 1.0 / 16000.0

        let utterances = [
            "Hello, I just arrived for dinner. How has your week been so far?",
            "Pretty good. Work was busy but I got through it all right.",
            "That sounds about right. I have been meaning to ask you both about next month.",
            "Sure, what is on your mind?",
            "I was thinking we could all plan a trip together if everyone is interested.",
            "That sounds like a great idea to me. When were you thinking?",
            "I really appreciate your enthusiasm about this trip.",
            "Should we plan the dates soon, or can we think about it more?",
            "I am flexible with timing and can adjust as needed.",
            "Great, let us all share our calendars then.",
        ]

        let selectedVoices = Array(Self.voicesCatalog.prefix(voiceCount))
        let selectedUtterances = Array(utterances.prefix(voiceCount))

        for (i, (voice, text)) in zip(selectedVoices.dropFirst(), selectedUtterances.dropFirst()).enumerated() {
            let startTime = Double(audio.count) * timePerSample
            let synth = try self.synth(voice: voice, text: text)
            audio += synth
            audio += silence
            let endTime = Double(audio.count) * timePerSample
            groundTruth.append(SpeakerSegment(speaker: i, start: startTime, end: endTime))
        }

        return groundTruth
    }

    private func loadModelURL() throws -> URL {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return ProcessInfo.processInfo.environment["CAPTION_DIARIZER_MODEL"].map { URL(fileURLWithPath: $0) }
            ?? repo.appendingPathComponent("Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc")
    }

    func testCompareSortformerVsLSEENDModels() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_SPEAKER_COMPARE"] == "1", "opt-in")

        let voiceCountStr = ProcessInfo.processInfo.environment["CAPTION_SPEAKER_COMPARE_VOICES"] ?? "6"
        let voiceCounts = parseVoiceCountsFromEnv(voiceCountStr)

        let modelURL = try loadModelURL()
        var allResults: [SpeakerModelComparisonReport] = []
        let originalOfflineMode = ModelHub.offlineMode
        defer { ModelHub.offlineMode = originalOfflineMode }

        for voiceCount in voiceCounts {
            print("SPEAKER-COMPARE-START voices: \(voiceCount)")

            let (audio, groundTruth) = try buildTestAudio(voiceCount: voiceCount)
            print("Audio duration: \(Double(audio.count) / 16000.0) s, ground-truth speakers: \(Set(groundTruth.map(\.speaker)).count)")

            // Test 1: Sortformer (bundled)
            do {
                let d = LiveDiarizer(modelURL: modelURL)
                try await d.prepare()

                let startTime = Date()
                var firstLabelTime: TimeInterval?

                var i = 0
                while i < audio.count {
                    d.feed(Array(audio[i..<min(i + 1600, audio.count)]))
                    if firstLabelTime == nil && !d.segments.isEmpty {
                        firstLabelTime = Date().timeIntervalSince(startTime)
                    }
                    i += 1600
                }
                d.finish()

                let segments = d.segments
                let speakersFound = Set(segments.map(\.speaker)).count

                let der = computeDER(hypothesis: segments, groundTruth: groundTruth)
                let report = SpeakerModelComparisonReport(
                    modelName: "Sortformer/bundled",
                    speakersFound: speakersFound,
                    der: der,
                    timeToFirstLabel: firstLabelTime
                )
                allResults.append(report)
                print("SPEAKER-COMPARE-RESULT \(report.summaryLine())")
            } catch {
                print("SPEAKER-COMPARE-ERROR Sortformer failed: \(error)")
            }

            // Test 2 & 3: LS-EEND with dihard3 and ami variants
            let lseendVariants: [(name: String, variant: ModelNames.LSEEND.Variant)] = [
                ("LS-EEND/dihard3", .dihard3),
                ("LS-EEND/ami", .ami),
            ]

            for (modelName, variant) in lseendVariants {
                do {
                    let previousMode = ModelHub.offlineMode
                    defer { ModelHub.offlineMode = previousMode }
                    ModelHub.offlineMode = false
                    let diarizer = try await LSEENDDiarizer(variant: variant)

                    let startTime = Date()
                    var firstLabelTime: TimeInterval?

                    var i = 0
                    while i < audio.count {
                        let chunk = Array(audio[i..<min(i + 1600, audio.count)])
                        try diarizer.addAudio(chunk)

                        if let update = try diarizer.process() {
                            if firstLabelTime == nil && !(update.finalizedSegments.isEmpty && update.tentativeSegments.isEmpty) {
                                firstLabelTime = Date().timeIntervalSince(startTime)
                            }
                        }
                        i += 1600
                    }

                    try diarizer.finalizeSession()

                    let allSegments = diarizer.timeline.speakers.values.flatMap { speaker in
                        speaker.finalizedSegments + speaker.tentativeSegments
                    }
                    let hypothesis = fluidAudioToSpeakerSegments(allSegments)
                    let speakersFound = Set(hypothesis.map(\.speaker)).count

                    let der = computeDER(hypothesis: hypothesis, groundTruth: groundTruth)
                    let report = SpeakerModelComparisonReport(
                        modelName: modelName,
                        speakersFound: speakersFound,
                        der: der,
                        timeToFirstLabel: firstLabelTime
                    )
                    allResults.append(report)
                    print("SPEAKER-COMPARE-RESULT \(report.summaryLine())")
                } catch {
                    print("SPEAKER-COMPARE-ERROR \(modelName) failed: \(error)")
                }
            }
        }

        // Summary
        print("SPEAKER-COMPARE-SUMMARY \(allResults.count) models tested")
        for r in allResults {
            XCTAssertGreaterThanOrEqual(r.speakersFound, 1, "\(r.modelName) should detect at least 1 speaker")
            XCTAssertGreaterThanOrEqual(r.der, 0.0, "DER should be non-negative")
            XCTAssertLessThanOrEqual(r.der, 1.0, "DER should be at most 1")
        }
    }

    /// Compute DER (Diarization Error Rate) from hypothesis speaker segments vs. ground truth.
    /// Hypothesis and ground truth are both lists of [SpeakerSegment].
    private func computeDER(hypothesis: [SpeakerSegment], groundTruth: [SpeakerSegment]) -> Double {
        guard !hypothesis.isEmpty, !groundTruth.isEmpty else { return 1.0 }

        let hypothesisDER = hypothesis.map { seg in
            DERSpeakerSegment(speaker: String(seg.speaker), start: seg.start, end: seg.end)
        }

        let referenceDER = groundTruth.map { seg in
            DERSpeakerSegment(speaker: String(seg.speaker), start: seg.start, end: seg.end)
        }

        let result = DiarizationDER.compute(ref: referenceDER, hyp: hypothesisDER)
        return result.der
    }

    /// Adapt FluidAudio's DiarizerSegment to [SpeakerSegment].
    private func fluidAudioToSpeakerSegments(_ segments: [DiarizerSegment]) -> [SpeakerSegment] {
        segments.map { seg in
            SpeakerSegment(speaker: seg.speakerIndex, start: Double(seg.startTime), end: Double(seg.endTime))
        }
    }

    /// Memory footprint in bytes (task info VM size). Copied from EngineEvalKit.swift with citing comment.
    private func memoryFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size)/4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    /// CPU time delta via getrusage over an interval.
    private func cpuTimeDelta(before: rusage, after: rusage) -> Double {
        let beforeCPU = Double(before.ru_utime.tv_sec) + Double(before.ru_utime.tv_usec) / 1_000_000.0
        let afterCPU = Double(after.ru_utime.tv_sec) + Double(after.ru_utime.tv_usec) / 1_000_000.0
        return afterCPU - beforeCPU
    }

    /// Markdown table row writer for docs/perf/speaker-model-comparison.md.
    /// Format: model | scenario | speaker-count | speakers-found | DER | time-to-label | memory-footprint | cpu-time
    private func markdownTableRow(
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
}

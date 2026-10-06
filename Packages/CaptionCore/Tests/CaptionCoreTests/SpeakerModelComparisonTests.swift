import AVFoundation
import FluidAudio
import XCTest
@testable import CaptionCore

/// Speaker diarization model comparison: Sortformer vs. LS-EEND variants on synthetic voices.
/// Run with: CAPTION_SPEAKER_COMPARE=1 swift test --filter SpeakerModelComparison
/// Synthesizes 6 distinct voices (Samantha, Daniel, Karen, Alex, Victoria, Fred) with scripted
/// turn-taking and overlap, feeds into both bundled Sortformer and LS-EEND (downloaded if needed),
/// and compares speakers found, DER (via FluidAudio's DiarizationDER.compute), and time-to-label.
/// Note: Network access required for LS-EEND model download (~450 MB per variant).
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

    private func buildTestAudio() throws -> (audio: [Float], groundTruth: [SpeakerSegment]) {
        let silence = [Float](repeating: 0, count: 8000)
        var audio: [Float] = []
        var groundTruth: [SpeakerSegment] = []

        let timePerSample = 1.0 / 16000.0

        let utterances: [(voice: String, text: String, speaker: Int)] = [
            ("Samantha", "Hello, I just arrived for dinner. How has your week been so far?", 0),
            ("Daniel", "Pretty good. Work was busy but I got through it all right.", 1),
            ("Karen", "That sounds about right. I have been meaning to ask you both about next month.", 2),
            ("Alex", "Sure, what is on your mind?", 3),
            ("Victoria", "I was thinking we could all plan a trip together if everyone is interested.", 4),
            ("Fred", "That sounds like a great idea to me. When were you thinking?", 5),
        ]

        for (voice, text, speaker) in utterances {
            let startTime = Double(audio.count) * timePerSample
            let synth = try self.synth(voice: voice, text: text)
            audio += synth
            audio += silence

            let endTime = Double(audio.count) * timePerSample
            groundTruth.append(SpeakerSegment(speaker: speaker, start: startTime, end: endTime))
        }

        // Add an overlap window: sum Samantha and Daniel's voices
        let overlapStart = Double(audio.count) * timePerSample
        let samanthaSpeech = try synth(voice: "Samantha", text: "This is going to be wonderful.")
        let danielSpeech = try synth(voice: "Daniel", text: "I absolutely agree with you.")

        let minLen = min(samanthaSpeech.count, danielSpeech.count)
        let overlapWindow = (0..<minLen).map { i -> Float in
            let combined = (samanthaSpeech[i] + danielSpeech[i]) / 2.0
            return min(1.0, max(-1.0, combined))
        }

        audio += overlapWindow
        audio += silence

        let overlapEnd = Double(audio.count) * timePerSample
        groundTruth.append(SpeakerSegment(speaker: 0, start: overlapStart, end: overlapEnd))

        return (audio, groundTruth)
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

        let (audio, groundTruth) = try buildTestAudio()
        let modelURL = try loadModelURL()

        var results: [SpeakerModelComparisonReport] = []

        print("SPEAKER-COMPARE-START audio duration: \(Double(audio.count) / 16000.0) s, ground-truth speakers: \(Set(groundTruth.map(\.speaker)).count)")

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

            let der = computeDER(sortformerSegments: segments, fluidAudioSegments: nil, groundTruth: groundTruth)
            let report = SpeakerModelComparisonReport(
                modelName: "Sortformer/bundled",
                speakersFound: speakersFound,
                der: der,
                timeToFirstLabel: firstLabelTime
            )
            results.append(report)
            print("SPEAKER-COMPARE-RESULT \(report.summaryLine())")
        } catch {
            print("SPEAKER-COMPARE-ERROR Sortformer failed: \(error)")
        }

        // Test 2 & 3: LS-EEND with dihard3 and ami variants
        // Note: ModelHub.offlineMode must stay false (default) to allow HF downloads.
        // LSEENDDiarizer uses ModelNames.LSEEND.Variant enum cases (.ami, .dihard3, etc.)
        let lseendVariants: [(name: String, variant: ModelNames.LSEEND.Variant)] = [
            ("LS-EEND/dihard3", .dihard3),
            ("LS-EEND/ami", .ami),
        ]

        for (modelName, variant) in lseendVariants {
            do {
                // Ensure we're not in offline mode before downloading LS-EEND model
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
                let speakersFound = Set(allSegments.map(\.speakerIndex)).count

                let der = computeDER(sortformerSegments: nil, fluidAudioSegments: allSegments, groundTruth: groundTruth)
                let report = SpeakerModelComparisonReport(
                    modelName: modelName,
                    speakersFound: speakersFound,
                    der: der,
                    timeToFirstLabel: firstLabelTime
                )
                results.append(report)
                print("SPEAKER-COMPARE-RESULT \(report.summaryLine())")
            } catch {
                print("SPEAKER-COMPARE-ERROR \(modelName) failed: \(error)")
            }
        }

        // Summary
        print("SPEAKER-COMPARE-SUMMARY \(results.count) models tested")
        for r in results {
            XCTAssertGreaterThanOrEqual(r.speakersFound, 1, "\(r.modelName) should detect at least 1 speaker")
            XCTAssertGreaterThanOrEqual(r.der, 0.0, "DER should be non-negative")
            XCTAssertLessThanOrEqual(r.der, 1.0, "DER should be at most 1")
        }
    }

    private func computeDER(sortformerSegments: [SpeakerSegment]?, fluidAudioSegments: [DiarizerSegment]?, groundTruth: [SpeakerSegment]) -> Double {
        let hypothesisDER: [DERSpeakerSegment]
        if let sortformerSegs = sortformerSegments {
            hypothesisDER = sortformerSegs.map { seg in
                DERSpeakerSegment(speaker: String(seg.speaker), start: seg.start, end: seg.end)
            }
        } else if let fluidAudioSegs = fluidAudioSegments {
            hypothesisDER = fluidAudioSegs.map { seg in
                DERSpeakerSegment(speaker: String(seg.speakerIndex), start: Double(seg.startTime), end: Double(seg.endTime))
            }
        } else {
            return 1.0
        }

        guard !hypothesisDER.isEmpty, !groundTruth.isEmpty else { return 1.0 }

        let referenceDER = groundTruth.map { seg in
            DERSpeakerSegment(speaker: String(seg.speaker), start: seg.start, end: seg.end)
        }

        let result = DiarizationDER.compute(ref: referenceDER, hyp: hypothesisDER)
        return result.der
    }
}

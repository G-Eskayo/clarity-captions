import AVFoundation
import FluidAudio
import XCTest
@testable import CaptionCore

/// Speaker diarization model comparison: Sortformer vs. LS-EEND variants on synthetic voices.
/// Run with: CAPTION_SPEAKER_COMPARE=1 swift test --filter SpeakerModelComparison
/// Synthesizes 6 and 10 distinct voices with scripted turn-taking and overlap, feeds into
/// Sortformer (bundled), LS-EEND (downloaded if needed), Nemotron3 (stub), and OfflineVBx (stub),
/// and compares speakers found, DER (via FluidAudio's DiarizationDER.compute), and time-to-label.
/// Note: Network access required for LS-EEND model download (~450 MB per variant).
final class SpeakerModelComparisonTests: XCTestCase {
    // MARK: - Test-local adapters for Nemotron3 and OfflineVBx (stubbed for now)

    /// Stub adapter for Nemotron3Diarizer (batch-only, not suitable for live use per plan).
    final class Nemotron3DiarizerAdapter: Diarizer {
        var segments: [DiarizerSegment] = []
        var audioBuffer: [Float] = []

        func addAudio(_ samples: [Float]) throws {
            audioBuffer.append(contentsOf: samples)
        }

        func process() throws -> DiarizerTimelineUpdate? {
            // Nemotron3 would process the accumulated audio in batch; stubbed here.
            return nil
        }

        func finalizeSession() throws {
            // Would run batch diarization on accumulated audio.
            // For now, return no segments (conservative estimate).
        }
    }

    /// Stub adapter for OfflineDiarizerManager (batch VBx embedding+clustering, not live).
    final class OfflineDiarizerManagerAdapter: Diarizer {
        var audioBuffer: [Float] = []

        func addAudio(_ samples: [Float]) throws {
            audioBuffer.append(contentsOf: samples)
        }

        func process() throws -> DiarizerTimelineUpdate? {
            // Batch-only diarizer; returns nothing until finalization.
            return nil
        }

        func finalizeSession() throws {
            // Would extract embeddings and run VBx clustering on all accumulated audio.
            // Stubbed: no output (batch only, unsuitable for live captions).
        }
    }
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

    private func buildTestAudio(voiceCount: Int = 6) throws -> (audio: [Float], groundTruth: [SpeakerSegment]) {
        guard voiceCount == 6 || voiceCount == 10 else {
            throw NSError(domain: "SpeakerModelComparisonTests", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "voiceCount must be 6 or 10"])
        }

        let silence = [Float](repeating: 0, count: 8000)
        var audio: [Float] = []
        var groundTruth: [SpeakerSegment] = []

        let timePerSample = 1.0 / 16000.0

        // 6-voice base: Samantha, Daniel, Karen, Alex, Victoria, Fred
        // 10-voice expanded: add Moira, Rishi, Nora, Fiona
        var utterances: [(voice: String, text: String, speaker: Int)] = [
            ("Samantha", "Hello, I just arrived for dinner. How has your week been so far?", 0),
            ("Daniel", "Pretty good. Work was busy but I got through it all right.", 1),
            ("Karen", "That sounds about right. I have been meaning to ask you both about next month.", 2),
            ("Alex", "Sure, what is on your mind?", 3),
            ("Victoria", "I was thinking we could all plan a trip together if everyone is interested.", 4),
            ("Fred", "That sounds like a great idea to me. When were you thinking?", 5),
        ]

        if voiceCount == 10 {
            utterances.append(contentsOf: [
                ("Moira", "I think that's a wonderful opportunity for all of us.", 6),
                ("Rishi", "Absolutely, I'm quite enthusiastic about the possibility.", 7),
                ("Nora", "That sounds like it could be very enjoyable for everyone.", 8),
                ("Fiona", "Count me in, I'm very interested in making this happen.", 9),
            ])
        }

        for (voice, text, speaker) in utterances {
            let startTime = Double(audio.count) * timePerSample
            let synth = try self.synth(voice: voice, text: text)
            audio += synth
            audio += silence

            let endTime = Double(audio.count) * timePerSample
            groundTruth.append(SpeakerSegment(speaker: speaker, start: startTime, end: endTime))
        }

        // Add an overlap window: sum first two voices
        let overlapStart = Double(audio.count) * timePerSample
        let speech1 = try synth(voice: utterances[0].voice, text: "This is going to be wonderful.")
        let speech2 = try synth(voice: utterances[1].voice, text: "I absolutely agree with you.")

        let minLen = min(speech1.count, speech2.count)
        let overlapWindow = (0..<minLen).map { i -> Float in
            let combined = (speech1[i] + speech2[i]) / 2.0
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

        let modelURL = try loadModelURL()

        // Run comparison for both 6-voice and 10-voice test cases
        for voiceCount in [6, 10] {
            let (audio, groundTruth) = try buildTestAudio(voiceCount: voiceCount)
            var results: [SpeakerModelComparisonReport] = []

            let voiceLabel = voiceCount == 6 ? "6-voice" : "10-voice"
            print("SPEAKER-COMPARE-START \(voiceLabel) audio duration: \(Double(audio.count) / 16000.0) s, ground-truth speakers: \(Set(groundTruth.map(\.speaker)).count)")

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
                    modelName: "Sortformer/bundled(\(voiceLabel))",
                    speakersFound: speakersFound,
                    der: der,
                    timeToFirstLabel: firstLabelTime
                )
                results.append(report)
                print("SPEAKER-COMPARE-RESULT \(report.summaryLine())")
            } catch {
                print("SPEAKER-COMPARE-ERROR Sortformer(\(voiceLabel)) failed: \(error)")
            }

            // Test 2 & 3: LS-EEND with dihard3 and ami variants
            let lseendVariants: [(name: String, variant: ModelNames.LSEEND.Variant)] = [
                ("LS-EEND/dihard3", .dihard3),
                ("LS-EEND/ami", .ami),
            ]

            for (modelName, variant) in lseendVariants {
                do {
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
                        modelName: "\(modelName)(\(voiceLabel))",
                        speakersFound: speakersFound,
                        der: der,
                        timeToFirstLabel: firstLabelTime
                    )
                    results.append(report)
                    print("SPEAKER-COMPARE-RESULT \(report.summaryLine())")
                } catch {
                    print("SPEAKER-COMPARE-ERROR \(modelName)(\(voiceLabel)) failed: \(error)")
                }
            }

            // Test 4 & 5: Nemotron3 and OfflineVBx stubs (batch-only, untimed)
            let stubVariants: [(name: String, factory: () -> Diarizer)] = [
                ("Nemotron3Diarizer", { Nemotron3DiarizerAdapter() }),
                ("OfflineDiarizer/VBx", { OfflineDiarizerManagerAdapter() }),
            ]

            for (modelName, factory) in stubVariants {
                do {
                    let adapter = factory()
                    let d = LiveDiarizer(diarizer: adapter)
                    try await d.prepare()

                    var i = 0
                    while i < audio.count {
                        d.feed(Array(audio[i..<min(i + 1600, audio.count)]))
                        i += 1600
                    }
                    d.finish()

                    let segments = d.segments
                    let speakersFound = Set(segments.map(\.speaker)).count
                    let der = segments.isEmpty ? 1.0 : computeDER(sortformerSegments: segments, fluidAudioSegments: nil, groundTruth: groundTruth)

                    let report = SpeakerModelComparisonReport(
                        modelName: "\(modelName)(\(voiceLabel))",
                        speakersFound: speakersFound,
                        der: der,
                        timeToFirstLabel: nil
                    )
                    results.append(report)
                    print("SPEAKER-COMPARE-RESULT \(report.summaryLine())")
                } catch {
                    print("SPEAKER-COMPARE-ERROR \(modelName)(\(voiceLabel)) failed: \(error)")
                }
            }

            // Summary for this voice count
            print("SPEAKER-COMPARE-SUMMARY \(voiceLabel): \(results.count) models tested")
            for r in results {
                XCTAssertGreaterThanOrEqual(r.der, 0.0, "DER should be non-negative")
                XCTAssertLessThanOrEqual(r.der, 1.0, "DER should be at most 1")
            }
        }
    }

    // MARK: - Harness generalization tests (15 misuse cases)

    func testHarnessEmptyAudio() async throws {
        let modelURL = try loadModelURL()
        let phrases = [SpeakerReplayPhrase(start: 0, end: 1)]
        var feedCalled = false

        let result = try await SpeakerPathReplay.run(
            next: { feedCalled ? nil : (feedCalled = true; return []) },
            phrases: phrases,
            modelURL: modelURL
        )

        XCTAssertEqual(result.emissions.count, 0)
        XCTAssertEqual(result.finalSegments.count, 0)
    }

    func testHarnessPhrasesNotAStream() async throws {
        let modelURL = try loadModelURL()
        let phrases = [
            SpeakerReplayPhrase(start: 0, end: 1),
            SpeakerReplayPhrase(start: 0.5, end: 1.5),  // overlapping, invalid stream
        ]

        do {
            _ = try await SpeakerPathReplay.run(
                next: { nil },
                phrases: phrases,
                modelURL: modelURL
            )
            XCTFail("Should reject non-stream phrases")
        } catch SpeakerReplayError.phrasesNotAStream {
            // expected
        }
    }

    func testHarnessEmptyPhraseList() async throws {
        let modelURL = try loadModelURL()
        let phrases: [SpeakerReplayPhrase] = []

        let result = try await SpeakerPathReplay.run(
            next: { nil },
            phrases: phrases,
            modelURL: modelURL
        )

        XCTAssertEqual(result.emissions.count, 0)
    }

    func testHarnessNegativeTimestamp() async throws {
        let modelURL = try loadModelURL()
        let phrases = [SpeakerReplayPhrase(start: -1, end: 0)]

        do {
            _ = try await SpeakerPathReplay.run(
                next: { nil },
                phrases: phrases,
                modelURL: modelURL
            )
            XCTFail("Should reject negative timestamps")
        } catch SpeakerReplayError.phrasesNotAStream {
            // expected
        }
    }

    func testHarnessUnsortedPhrases() async throws {
        let modelURL = try loadModelURL()
        let phrases = [
            SpeakerReplayPhrase(start: 2, end: 3),
            SpeakerReplayPhrase(start: 0, end: 1),  // out of order
        ]

        do {
            _ = try await SpeakerPathReplay.run(
                next: { nil },
                phrases: phrases,
                modelURL: modelURL
            )
            XCTFail("Should reject unsorted phrases")
        } catch SpeakerReplayError.phrasesNotAStream {
            // expected
        }
    }

    func testHarnessZeroDurationPhrase() async throws {
        let modelURL = try loadModelURL()
        let phrases = [SpeakerReplayPhrase(start: 1, end: 1)]  // zero length

        do {
            _ = try await SpeakerPathReplay.run(
                next: { nil },
                phrases: phrases,
                modelURL: modelURL
            )
            XCTFail("Should reject zero-duration phrases")
        } catch SpeakerReplayError.phrasesNotAStream {
            // expected
        }
    }

    func testHarnessNullAudioFactory() async throws {
        let phrases = [SpeakerReplayPhrase(start: 0, end: 1)]

        let result = try await SpeakerPathReplay.run(
            next: { nil },
            phrases: phrases,
            diarizer: { LiveDiarizer(diarizer: OfflineDiarizerManagerAdapter()) }
        )

        XCTAssertEqual(result.audioSeconds, 0)
    }

    func testHarnessLargeAudioWithFactoryDiarizer() async throws {
        let phrases = [SpeakerReplayPhrase(start: 0, end: 1)]
        let silence = [Float](repeating: 0, count: 16_000)
        var feedCount = 0

        let result = try await SpeakerPathReplay.run(
            next: {
                feedCount += 1
                return feedCount <= 2 ? silence : nil
            },
            phrases: phrases,
            diarizer: { LiveDiarizer(diarizer: OfflineDiarizerManagerAdapter()) }
        )

        XCTAssertGreaterThan(result.audioSeconds, 0)
    }

    func testHarnessMultipleDrain() async throws {
        let modelURL = try loadModelURL()
        let d = LiveDiarizer(modelURL: modelURL)
        try await d.prepare()

        d.feed([Float](repeating: 0, count: 1000))
        d.drain()
        d.drain()
        d.drain()

        d.finish()
        XCTAssertNil(d.lastError)
    }

    func testLiveDiarizerDoubleFinish() async throws {
        let modelURL = try loadModelURL()
        let d = LiveDiarizer(modelURL: modelURL)
        try await d.prepare()

        d.finish()
        d.finish()

        XCTAssertNil(d.lastError)
    }

    func testLiveDiarizerDiagnosticsEmpty() async throws {
        let modelURL = try loadModelURL()
        let d = LiveDiarizer(modelURL: modelURL)
        try await d.prepare()

        let diag = d.diagnostics
        XCTAssert(diag.contains("diarizer:"))
        XCTAssert(diag.contains("speakers []"))
    }

    func testLiveDiarizerSegmentsInitiallyEmpty() async throws {
        let modelURL = try loadModelURL()
        let d = LiveDiarizer(modelURL: modelURL)
        try await d.prepare()

        XCTAssertEqual(d.segments.count, 0)
    }

    func testSpeakerModelReportOptionalFields() {
        let report = SpeakerModelComparisonReport(
            modelName: "Test",
            speakersFound: 2,
            der: 0.1
        )

        XCTAssertNil(report.timeToFirstLabelSeconds)
        XCTAssertNil(report.peakMemoryMB)
        XCTAssertNil(report.wallSecondsPerAudioSecond)
    }

    func testSpeakerModelReportWithMemoryAndEfficiency() {
        let report = SpeakerModelComparisonReport(
            modelName: "Test",
            speakersFound: 2,
            der: 0.1,
            timeToFirstLabel: 0.5,
            peakMemory: 256,
            wallSecondsPerAudio: 0.75
        )

        XCTAssertEqual(report.peakMemoryMB, 256)
        XCTAssertEqual(report.wallSecondsPerAudioSecond, 0.75)
        let summary = report.summaryLine()
        XCTAssert(summary.contains("256 MB"))
        XCTAssert(summary.contains("x0.8"))
    }

    func testHarnessReplayWithVeryShortPhrase() async throws {
        let modelURL = try loadModelURL()
        let phrases = [SpeakerReplayPhrase(start: 0, end: 0.001)]  // 1 ms phrase
        let audio = [Float](repeating: 0.1, count: 100)
        var feedCount = 0

        let result = try await SpeakerPathReplay.run(
            next: {
                feedCount += 1
                return feedCount == 1 ? audio : nil
            },
            phrases: phrases,
            modelURL: modelURL
        )

        XCTAssertGreaterThanOrEqual(result.audioSeconds, 0)
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

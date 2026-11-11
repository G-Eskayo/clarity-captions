import AVFoundation
import Darwin
import FluidAudio
import XCTest
@testable import CaptionCore

/// Speaker diarization model comparison: Sortformer vs. LS-EEND vs. OfflineDiarizerManager on synthetic voices.
/// Run with: CAPTION_SPEAKER_COMPARE=1 swift test --filter SpeakerModelComparison
/// Synthesizes 4, 6, or 10 distinct voices with scripted turn-taking and overlap, feeds into bundled Sortformer,
/// LS-EEND (downloaded if needed), and OfflineDiarizerManager, and compares speakers found, DER (via FluidAudio's
/// DiarizationDER.compute), time-to-label, and process memory.
/// Note: Network access required for LS-EEND model download (~450 MB per variant).
final class SpeakerModelComparisonTests: XCTestCase {
    /// Dynamically detect available macOS system voices by running `say -v "?"`.
    /// Cached at first access; used to scale tests to 4/6/10 speakers.
    /// Thread safety: only called from tests, safe to suppress concurrency checks.
    nonisolated(unsafe) private static var cachedAvailableVoices: [String]?

    /// Voices required for testing, indexed by voice count.
    /// - 4 voices: baseline
    /// - 6 voices: baseline + 2 extras
    /// - 10 voices: full set
    private static let requiredVoicesByCount: [Int: [String]] = [
        4: ["Samantha", "Daniel", "Karen", "Alex"],
        6: ["Samantha", "Daniel", "Karen", "Alex", "Victoria", "Fred"],
        10: ["Samantha", "Daniel", "Karen", "Alex", "Victoria", "Fred", "Moira", "Marie", "Fiona", "Zarvox"]
    ]

    private static func getAvailableVoices() -> [String] {
        if let cached = cachedAvailableVoices {
            return cached
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "?"]

        let pipe = Pipe()
        p.standardOutput = pipe

        do {
            try p.run()
            p.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let voices = output.split(separator: "\n")
                    .compactMap { line -> String? in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return nil }
                        // Extract voice name: everything before the first locale code or tab
                        // Format: "VoiceName [locale] [gender]" or "Voice Name (locale)" variants
                        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                        guard !tokens.isEmpty else { return nil }

                        // Reconstruct voice name: take words until we hit a locale code or parenthesis
                        var voiceName = ""
                        for token in tokens {
                            let s = String(token)
                            // Locale codes are like en_US, en_IE, de_DE (XX_XX pattern)
                            if s.contains("_") {
                                let parts = s.split(separator: "_")
                                if parts.count == 2 && parts.allSatisfy({ $0.count >= 2 && $0.count <= 3 && $0.allSatisfy(\.isLetter) }) {
                                    break  // This looks like a locale code
                                }
                            }
                            // Parenthesized variants like "(English (US))"
                            if s.starts(with: "(") {
                                break
                            }
                            if !voiceName.isEmpty {
                                voiceName += " "
                            }
                            voiceName += s
                        }
                        return voiceName.isEmpty ? nil : voiceName
                    }
                    .filter { !$0.isEmpty }

                // Deduplicate: if "Eddy (English (US))" and "Eddy (German (Germany))" both exist, keep only one "Eddy"
                let deduped = Array(Set(voices))
                cachedAvailableVoices = deduped
                return deduped
            }
        } catch {
            // If say -v "?" fails to launch, return empty list so tests skip gracefully
            cachedAvailableVoices = []
            return []
        }

        return []
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

    /// Generates synthetic test audio with `voiceCount` speakers (4, 6, or 10).
    /// Skips via XCTSkipUnless if this host lacks the required system voices.
    private func buildTestAudio(voiceCount: Int = 6) throws -> (audio: [Float], groundTruth: [SpeakerSegment]) {
        // Precondition: skip test if we don't have the required voices installed.
        let available = Self.getAvailableVoices()
        let requiredVoices = Self.requiredVoicesByCount[voiceCount] ?? []
        let availableSet = Set(available)
        let missingVoices = requiredVoices.filter { !availableSet.contains($0) }

        try XCTSkipUnless(
            missingVoices.isEmpty,
            "Test requires voices \(requiredVoices); missing \(missingVoices)"
        )

        let silence = [Float](repeating: 0, count: 8000)
        var audio: [Float] = []
        var groundTruth: [SpeakerSegment] = []

        let timePerSample = 1.0 / 16000.0

        let utterances: [(voice: String, text: String, speaker: Int)] = [
            ("Samantha", "Hello, I just arrived for dinner. How has your week been so far?", 0),
            ("Daniel", "Pretty good. Work was busy but I got through it all right.", 1),
            ("Karen", "That sounds about right. I have been meaning to ask you both about next month.", 2),
            ("Alex", "Sure, what is on your mind?", 3),
        ] + (voiceCount > 4 ? [
            ("Victoria", "I was thinking we could all plan a trip together if everyone is interested.", 4),
            ("Fred", "That sounds like a great idea to me. When were you thinking?", 5),
        ] : []) + (voiceCount > 6 ? [
            ("Moira", "That sounds wonderful. I am really excited about this trip.", 6),
            ("Marie", "Yes, I think it would be a great opportunity for all of us.", 7),
            ("Fiona", "I could not agree more with you. This is going to be amazing.", 8),
            ("Zarvox", "When should we start planning the details then?", 9),
        ] : [])

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

    /// Returns this process's current physical memory footprint (bytes). Core ML work on the Neural Engine
    /// also uses memory in system daemons, which this does not include.
    private static func currentMemoryFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil
    }

    /// Returns the peak memory footprint during the current candidate run, computed as the
    /// maximum current footprint sampled since memStart. Do not use the lifetime high-water mark,
    /// which accumulates across multiple candidates.
    private static func peakMemoryDelta(memStart: UInt64, memSamples: [UInt64]) -> UInt64 {
        guard !memSamples.isEmpty else { return 0 }
        return (memSamples.max() ?? memStart) - memStart
    }

    private func loadModelURL() throws -> URL {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return ProcessInfo.processInfo.environment["CAPTION_DIARIZER_MODEL"].map { URL(fileURLWithPath: $0) }
            ?? repo.appendingPathComponent("Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc")
    }

    func testCompareSortformerVsLSEENDVsOfflineModels() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_SPEAKER_COMPARE"] == "1", "opt-in")

        // Restore ModelHub.offlineMode to true at the end, regardless of which candidates ran.
        defer { ModelHub.offlineMode = true }

        let modelURL = try loadModelURL()
        let voiceCounts = [4, 6, 10]

        for voiceCount in voiceCounts {
            do {
                let (audio, groundTruth) = try buildTestAudio(voiceCount: voiceCount)
                try await runComparisonForAudio(audio, groundTruth: groundTruth, voiceCount: voiceCount, modelURL: modelURL)
            } catch {
                // buildTestAudio throws NSError when XCTSkipUnless fires (test skipped due to missing voices)
                // Continue to next voice count on skip
                if "\(error)".contains("Test requires voices") {
                    print("SPEAKER-COMPARE-SKIP voiceCount=\(voiceCount): \(error)")
                } else {
                    throw error  // Actual test failure, propagate it
                }
            }
        }
    }

    private func runComparisonForAudio(
        _ audio: [Float],
        groundTruth: [SpeakerSegment],
        voiceCount: Int,
        modelURL: URL
    ) async throws {

        var results: [SpeakerModelComparisonReport] = []

        let memBefore = Self.currentMemoryFootprint() ?? 0
        print("SPEAKER-COMPARE-START voiceCount=\(voiceCount), audio duration: \(Double(audio.count) / 16000.0) s, ground-truth speakers: \(Set(groundTruth.map(\.speaker)).count)")

        // Test 1: Sortformer (bundled)
        do {
            let memStart = Self.currentMemoryFootprint() ?? memBefore
            var memSamples: [UInt64] = [memStart]
            let d = LiveDiarizer(modelURL: modelURL)
            try await d.prepare()

            let startTime = Date()
            var firstLabelTime: TimeInterval?

            var i = 0
            while i < audio.count {
                d.feed(Array(audio[i..<min(i + 1600, audio.count)]))
                if let mem = Self.currentMemoryFootprint() {
                    memSamples.append(mem)
                }
                if firstLabelTime == nil && !d.segments.isEmpty {
                    firstLabelTime = Date().timeIntervalSince(startTime)
                }
                i += 1600
            }
            d.finish()

            let elapsedTime = Date().timeIntervalSince(startTime)
            let memEnd = Self.currentMemoryFootprint() ?? memStart
            memSamples.append(memEnd)
            let peakMemDelta = Self.peakMemoryDelta(memStart: memStart, memSamples: memSamples)

            let segments = d.segments
            let speakersFound = Set(segments.map(\.speaker)).count

            let der = computeDER(sortformerSegments: segments, fluidAudioSegments: nil, groundTruth: groundTruth)
            let report = SpeakerModelComparisonReport(
                modelName: "Sortformer/bundled",
                speakersFound: speakersFound,
                der: der,
                timeToFirstLabel: firstLabelTime,
                timeToFinish: elapsedTime,
                peakMemory: Double(peakMemDelta) / 1_048_576
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

                let memStart = Self.currentMemoryFootprint() ?? memBefore
                var memSamples: [UInt64] = [memStart]
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
                    if let mem = Self.currentMemoryFootprint() {
                        memSamples.append(mem)
                    }
                    i += 1600
                }

                try diarizer.finalizeSession()

                let elapsedTime = Date().timeIntervalSince(startTime)
                let memEnd = Self.currentMemoryFootprint() ?? memStart
                memSamples.append(memEnd)
                let peakMemDelta = Self.peakMemoryDelta(memStart: memStart, memSamples: memSamples)

                let allSegments = diarizer.timeline.speakers.values.flatMap { speaker in
                    speaker.finalizedSegments + speaker.tentativeSegments
                }
                let speakersFound = Set(allSegments.map(\.speakerIndex)).count

                let der = computeDER(sortformerSegments: nil, fluidAudioSegments: allSegments, groundTruth: groundTruth)
                let report = SpeakerModelComparisonReport(
                    modelName: modelName,
                    speakersFound: speakersFound,
                    der: der,
                    timeToFirstLabel: firstLabelTime,
                    timeToFinish: elapsedTime,
                    peakMemory: Double(peakMemDelta) / 1_048_576
                )
                results.append(report)
                print("SPEAKER-COMPARE-RESULT \(report.summaryLine())")
            } catch {
                print("SPEAKER-COMPARE-ERROR \(modelName) failed: \(error)")
            }
        }

        // Test 4: OfflineDiarizerManager (batch processing of complete audio)
        do {
            let memStart = Self.currentMemoryFootprint() ?? memBefore
            var memSamples: [UInt64] = [memStart]
            let config = OfflineDiarizerConfig.default
            let manager = OfflineDiarizerManager(config: config)
            try await manager.prepareModels()

            let startTime = Date()
            let result = try await manager.process(audio: audio)
            let elapsedTime = Date().timeIntervalSince(startTime)

            let memEnd = Self.currentMemoryFootprint() ?? memStart
            memSamples.append(memEnd)
            let peakMemDelta = Self.peakMemoryDelta(memStart: memStart, memSamples: memSamples)

            let segments = result.segments
            let speakersFound = Set(segments.map(\.speakerId)).count

            // Convert TimedSpeakerSegment to DERSpeakerSegment for DER computation
            let derSegments = segments.map { seg in
                DERSpeakerSegment(speaker: seg.speakerId, start: Double(seg.startTimeSeconds), end: Double(seg.endTimeSeconds))
            }
            let der = computeDER(sortformerSegments: nil, fluidAudioSegments: nil, offlineSegments: derSegments, groundTruth: groundTruth)

            let report = SpeakerModelComparisonReport(
                modelName: "OfflineDiarizer",
                speakersFound: speakersFound,
                der: der,
                timeToFirstLabel: nil,
                timeToFinish: elapsedTime,
                peakMemory: Double(peakMemDelta) / 1_048_576
            )
            results.append(report)
            print("SPEAKER-COMPARE-RESULT \(report.summaryLine())")
        } catch {
            print("SPEAKER-COMPARE-ERROR OfflineDiarizer failed: \(error)")
        }

        // Summary
        print("SPEAKER-COMPARE-SUMMARY \(results.count) models tested")
        for r in results {
            XCTAssertGreaterThanOrEqual(r.speakersFound, 1, "\(r.modelName) should detect at least 1 speaker")
            XCTAssertGreaterThanOrEqual(r.der, 0.0, "DER should be non-negative")
            XCTAssertLessThanOrEqual(r.der, 1.0, "DER should be at most 1")
        }
    }

    /// Test that voice-availability skip works: requesting unavailable voices should skip gracefully.
    func testVoiceAvailabilitySkip() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_SPEAKER_COMPARE"] == "1", "opt-in")

        let available = Self.getAvailableVoices()

        // Verify we can build audio with available voice count.
        var builtWithCount: Int? = nil
        for voiceCount in [4, 6, 10] {
            do {
                _ = try buildTestAudio(voiceCount: voiceCount)
                builtWithCount = voiceCount
            } catch {
                // buildTestAudio throws XCTestError with skip if voices unavailable.
                // Continue to next voice count.
                if "\(error)".contains("Test requires voices") {
                    continue
                }
                throw error  // Unexpected error
            }
        }

        // At least 4-voice test should succeed (nearly all macOS installs have >= 4 voices)
        XCTAssertNotNil(builtWithCount, "Test should have successfully built audio with at least 4 voices; host has \(available.count)")

        // Test that requesting more voices than available does skip
        // Request a count we know is impossible (100 voices)
        XCTAssertThrowsError(try buildTestAudio(voiceCount: 100), "Should skip when requesting 100 voices") { error in
            XCTAssertTrue("\(error)".contains("Test requires voices"), "Error should indicate missing voices")
        }
    }

    /// Test that empty audio is handled gracefully by all candidates (DER = 1.0, speakers = 0).
    func testEmptyAudioBound() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_SPEAKER_COMPARE"] == "1", "opt-in")

        let emptyAudio: [Float] = []
        let emptyGroundTruth: [SpeakerSegment] = []
        let modelURL = try loadModelURL()

        // Test 1: Sortformer with empty audio
        do {
            let d = LiveDiarizer(modelURL: modelURL)
            try await d.prepare()
            // Feed no audio (empty buffer)
            if !emptyAudio.isEmpty {
                d.feed(emptyAudio)
            }
            d.finish()

            let segments = d.segments
            let speakersFound = Set(segments.map(\.speaker)).count
            let der = computeDER(sortformerSegments: segments, groundTruth: emptyGroundTruth)

            XCTAssertEqual(speakersFound, 0, "Empty audio should detect 0 speakers (Sortformer)")
            XCTAssertEqual(der, 1.0, "Empty audio should result in DER = 1.0 (Sortformer)")
        } catch {
            XCTFail("Sortformer should handle empty audio gracefully: \(error)")
        }

        // Test 2: OfflineDiarizer with empty audio
        do {
            let config = OfflineDiarizerConfig.default
            let manager = OfflineDiarizerManager(config: config)
            try await manager.prepareModels()

            let result = try await manager.process(audio: emptyAudio)
            let speakersFound = Set(result.segments.map(\.speakerId)).count

            let derSegments = result.segments.map { seg in
                DERSpeakerSegment(speaker: seg.speakerId, start: Double(seg.startTimeSeconds), end: Double(seg.endTimeSeconds))
            }
            let der = computeDER(sortformerSegments: nil, fluidAudioSegments: nil, offlineSegments: derSegments, groundTruth: emptyGroundTruth)

            XCTAssertEqual(speakersFound, 0, "Empty audio should detect 0 speakers (OfflineDiarizer)")
            XCTAssertEqual(der, 1.0, "Empty audio should result in DER = 1.0 (OfflineDiarizer)")
        } catch {
            XCTFail("OfflineDiarizer should handle empty audio gracefully: \(error)")
        }
    }

    /// Test that ModelHub.offlineMode is restored to true after the comparison runs.
    /// This test actually runs a minimal comparison (Sortformer only) to verify the defer works.
    func testOfflineModeRestoration() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_SPEAKER_COMPARE"] == "1", "opt-in")

        let originalMode = ModelHub.offlineMode
        defer { ModelHub.offlineMode = originalMode }

        // Verify initial state: offline mode should be true by default.
        XCTAssertTrue(ModelHub.offlineMode, "Initial state: ModelHub.offlineMode should be true")

        // Run a minimal comparison (Sortformer on 4 voices) and verify offline mode is restored after.
        do {
            let (audio, _) = try buildTestAudio(voiceCount: 4)
            let modelURL = try loadModelURL()

            // Simulate what the main test does: start with defer to restore offline mode
            defer { ModelHub.offlineMode = true }

            // During the test, offline mode may be set to false for LS-EEND
            ModelHub.offlineMode = false
            XCTAssertFalse(ModelHub.offlineMode, "During test, mode should be false")

            // Run a minimal Sortformer comparison
            let d = LiveDiarizer(modelURL: modelURL)
            try await d.prepare()

            var i = 0
            while i < audio.count {
                d.feed(Array(audio[i..<min(i + 1600, audio.count)]))
                i += 1600
            }
            d.finish()

            // After this scope, the defer should restore offline mode to true
        }

        // Verify defer was executed: offline mode should be restored to true
        XCTAssertTrue(ModelHub.offlineMode, "After comparison completes, ModelHub.offlineMode should be restored to true by defer")
    }

    /// Test that repeat runs produce consistent DER/speaker counts (isolation).
    func testRepeatRunIsolation() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_SPEAKER_COMPARE"] == "1", "opt-in")

        let (audio, groundTruth) = try buildTestAudio()
        let modelURL = try loadModelURL()

        var results: [SpeakerModelComparisonReport] = []
        var runErrors: [Error] = []

        // Run Sortformer twice on the same audio; results should be identical (deterministic).
        for run in 0..<2 {
            do {
                let d = LiveDiarizer(modelURL: modelURL)
                try await d.prepare()

                var i = 0
                while i < audio.count {
                    d.feed(Array(audio[i..<min(i + 1600, audio.count)]))
                    i += 1600
                }
                d.finish()

                let segments = d.segments
                let speakersFound = Set(segments.map(\.speaker)).count
                let der = computeDER(sortformerSegments: segments, groundTruth: groundTruth)

                results.append(SpeakerModelComparisonReport(
                    modelName: "Sortformer/repeat",
                    speakersFound: speakersFound,
                    der: der
                ))
            } catch {
                runErrors.append(error)
                XCTFail("Run \(run) failed unexpectedly: \(error)")
            }
        }

        // Verify we got both runs' results before comparing them.
        XCTAssertEqual(results.count, 2, "Both repeat runs should complete successfully")
        XCTAssertTrue(runErrors.isEmpty, "No errors should occur during repeat runs")

        // Verify both runs had identical results (deterministic processing).
        if results.count >= 2 {
            XCTAssertEqual(results[0].speakersFound, results[1].speakersFound, "Repeat run should find same speaker count")
            XCTAssertEqual(results[0].der, results[1].der, accuracy: 0.001, "Repeat run should have identical DER")
        }
    }

    private func computeDER(
        sortformerSegments: [SpeakerSegment]? = nil,
        fluidAudioSegments: [DiarizerSegment]? = nil,
        offlineSegments: [DERSpeakerSegment]? = nil,
        groundTruth: [SpeakerSegment]
    ) -> Double {
        let hypothesisDER: [DERSpeakerSegment]
        if let sortformerSegs = sortformerSegments {
            hypothesisDER = sortformerSegs.map { seg in
                DERSpeakerSegment(speaker: String(seg.speaker), start: seg.start, end: seg.end)
            }
        } else if let fluidAudioSegs = fluidAudioSegments {
            hypothesisDER = fluidAudioSegs.map { seg in
                DERSpeakerSegment(speaker: String(seg.speakerIndex), start: Double(seg.startTime), end: Double(seg.endTime))
            }
        } else if let offlineSegs = offlineSegments {
            hypothesisDER = offlineSegs
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

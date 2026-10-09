import AVFoundation
import FluidAudio
import XCTest
@testable import CaptionCore

/// #91 measurement, opt-in like DiarizerIntegrationTests (needs the bundled model and macOS `say`):
///   CAPTION_INTEGRATION=1 swift test --filter SpeakerStabilityReplay
/// Replays synthetic speech through the real LiveDiarizer at the app's chunk size, labels "captions" against the
/// segments the app would have had at that moment, feeds them into CaptionStream exactly as the app does, and
/// prints how steady the labels are. Synthetic voices are not a far-field phone mic in a room: this separates
/// "the labeling logic flips" from "the room confuses the model", it does not replace a real-device check.
final class SpeakerStabilityReplayTests: XCTestCase {

    // MARK: material

    struct Part { let voice: String; let text: String; let gapAfter: Double }
    struct Phrase { let truth: Int; let start: Double; let end: Double }
    struct Scenario { let name: String; let audio: [Float]; let phrases: [Phrase] }

    private static let sr = 16_000.0

    /// `say` occasionally stalls (seen once, ten minutes on one sentence), so each attempt gets 30 s and a retry.
    private func synth(voice: String, text: String, attempts: Int = 3) throws -> [Float] {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@16000", text]
        try p.run()
        let deadline = Date().addingTimeInterval(30)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning {
            p.terminate()
            guard attempts > 1 else { throw CocoaError(.fileWriteUnknown) }
            return try synth(voice: voice, text: text, attempts: attempts - 1)
        }
        let file = try AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    }

    private func build(_ name: String, _ parts: [Part]) throws -> Scenario {
        var audio: [Float] = [], phrases: [Phrase] = []
        var voices: [String] = []
        for part in parts {
            if !voices.contains(part.voice) { voices.append(part.voice) }
            let speech = try synth(voice: part.voice, text: part.text)
            let start = Double(audio.count) / Self.sr
            audio += speech
            phrases.append(Phrase(truth: voices.firstIndex(of: part.voice)!, start: start, end: Double(audio.count) / Self.sr))
            audio += [Float](repeating: 0, count: Int(part.gapAfter * Self.sr))
        }
        return Scenario(name: name, audio: audio, phrases: phrases)
    }

    /// One person talking for about 90 seconds, changing pitch and pace the way a real person does, with a laugh.
    private func monologue(_ voice: String) throws -> Scenario {
        let lines = [
            "[[pbas 45]] So I finally went to the new bakery on Main Street this morning.",
            "[[pbas 55]] [[rate 210]] Honestly, the line was out the door, which I did not expect on a Tuesday.",
            "[[pbas 40]] [[rate 160]] I ordered a sourdough loaf and two of those little almond croissants.",
            "[[pbas 65]] Ha ha ha, and then I dropped one of them right on the floor.",
            "[[pbas 50]] [[rate 190]] The woman behind the counter just laughed and gave me another one for free.",
            "[[pbas 35]] [[rate 150]] Anyway, after that I walked down to the park to sit by the pond for a while.",
            "[[pbas 60]] There were ducks everywhere, and a man feeding them half a bag of bread.",
            "[[pbas 45]] [[rate 220]] I keep telling people bread is bad for ducks, but nobody listens to me.",
            "[[pbas 55]] Then my sister called, and we talked about her trip to the mountains next month.",
            "[[pbas 38]] [[rate 170]] She wants to rent a cabin with a fireplace and no internet at all.",
            "[[pbas 62]] [[rate 200]] I said that sounds lovely for about two days, and then I would go a little crazy.",
            "[[pbas 47]] Maybe we will all go together if the weather holds up.",
            "[[pbas 52]] [[rate 180]] After lunch I tried to fix the squeaky door in the hallway.",
            "[[pbas 42]] It still squeaks, but now it also sticks, so I think I made it worse.",
            "[[pbas 58]] [[rate 210]] Tomorrow I am going to call someone who actually knows what they are doing.",
        ]
        return try build("one voice (\(voice))", lines.enumerated().map { i, t in
            Part(voice: voice, text: t, gapAfter: i % 4 == 3 ? 1.6 : 0.5)
        })
    }

    private func dialogue(_ a: String, _ b: String, name: String) throws -> Scenario {
        let turns: [(String, String, Double)] = [
            (a, "Did you get a chance to look at the photos from the wedding?", 0.6),
            (b, "Not yet, I have been so busy with work this week.", 0.5),
            (a, "Oh you have to, there is one of grandma dancing that is just wonderful.", 0.4),
            (b, "Grandma was dancing? I missed that completely.", 0.3),
            (a, "Right after the cake. She would not sit down for an hour.", 0.7),
            (b, "That sounds like her. Who took the pictures, the cousin from Denver?", 0.4),
            (a, "Yes, and he is sending the rest of them on Friday.", 0.2),
            (b, "Great.", 0.3),
            (a, "I will forward them to you as soon as they come in.", 1.5),
            (b, "Thanks. By the way, are we still having dinner on Sunday?", 0.5),
            (a, "Of course, six o'clock, and bring that salad you made last time.", 0.4),
            (b, "The one with the oranges? Sure, I can do that.", 0.6),
        ]
        return try build(name, turns.map { Part(voice: $0.0, text: $0.1, gapAfter: $0.2) })
    }

    // MARK: replay

    /// What the app asks when a caption result arrives: which speaker owns [start, end], given the diarizer now.
    struct LabelRequest { let phrase: Int; let start: Double; let end: Double; let now: Double; let segments: [SpeakerSegment]; let isFinal: Bool }
    typealias Labeler = (LabelRequest) -> Int?

    struct Emission { let time: Double; let phrase: Int; let isFinal: Bool; let label: Int? }
    struct Result { let emissions: [Emission]; let lines: [CaptionLine] }
    struct Recording { let requests: [LabelRequest]; let finalSegments: [SpeakerSegment] }

    /// Runs the audio through the real diarizer once, at the app's buffer size, and records every caption result the
    /// app would have labeled, with the segments it would have had at that moment, so every labeler is compared on
    /// identical diarizer output. The tap delivers ~85 ms buffers (4096 frames at 48 kHz); live results arrive about
    /// every half second, and the final for a phrase about a second after it ends.
    private func record(_ s: Scenario, model: URL, config: SortformerConfig) async throws -> Recording {
        let d = LiveDiarizer(modelURL: model, config: config)
        try await d.prepare()
        let chunk = 1365, volatileEvery = 0.5, finalDelay = 1.0
        var requests: [LabelRequest] = [], finalized = Set<Int>()
        var nextVolatile = volatileEvery
        let audio = s.audio + [Float](repeating: 0, count: Int(3 * Self.sr))
        var i = 0
        func ask(_ p: Int, _ isFinal: Bool, _ now: Double) {
            let ph = s.phrases[p]
            let end = isFinal ? ph.end : min(now, ph.end)
            guard end > ph.start else { return }
            requests.append(LabelRequest(phrase: p, start: ph.start, end: end, now: now, segments: d.segments, isFinal: isFinal))
        }
        while i < audio.count {
            d.feed(Array(audio[i..<min(i + chunk, audio.count)]))
            i += chunk
            d.drain()
            let now = Double(i) / Self.sr
            for (p, ph) in s.phrases.enumerated() where !finalized.contains(p) && now >= ph.end + finalDelay {
                finalized.insert(p); ask(p, true, now)
            }
            if now >= nextVolatile {
                nextVolatile += volatileEvery
                if let p = s.phrases.firstIndex(where: { $0.start < now && now < $0.end + finalDelay }), !finalized.contains(p) {
                    ask(p, false, now)
                }
            }
        }
        d.finish()
        return Recording(requests: requests, finalSegments: d.segments)
    }

    /// Labels the recorded results and feeds them into CaptionStream, as the app does.
    private func play(_ rec: Recording, labeler: Labeler) -> Result {
        var stream = CaptionStream(), emissions: [Emission] = []
        for r in rec.requests {
            let label = labeler(r)
            emissions.append(Emission(time: r.now, phrase: r.phrase, isFinal: r.isFinal, label: label))
            let words = Array(repeating: "p\(r.phrase)", count: max(1, Int((r.end - r.start) * 2.5))).joined(separator: " ")
            stream.apply(text: words, isFinal: r.isFinal, speaker: label, range: r.start...r.end)
        }
        return Result(emissions: emissions, lines: stream.lines)
    }

    // MARK: metrics

    /// Scored on what ends up on screen (the final transcript) plus how the live line behaved getting there.
    struct Metrics: CustomStringConvertible {
        var minutes = 0.0
        var transcriptSpeakers = 0   // distinct labels in the final transcript (truth: 1 or 2)
        var highestNumber = 0        // the biggest "Speaker N" ever on screen, live included
        var highestInTranscript = 0  // the biggest "Speaker N" left in the final transcript
        var speakerLineChanges = 0   // consecutive transcript lines with different labels
        var mixedLines = 0           // lines holding words from two different people
        var mislabeledPercent = 0.0  // words whose line label isn't their person's label (one-to-one by majority)
        var liveRelabels = 0         // a live caption's label changed while it was being spoken
        var turnDelays: [Double] = []
        var missedTurns = 0
        var description: String {
            let delays = turnDelays.sorted()
            let median = delays.isEmpty ? Double.nan : delays[delays.count / 2]
            return String(format: "transcript speakers %d · highest Speaker N live %d / transcript %d · line changes %d · mixed lines %d · mislabeled %.0f%% · live relabels/min %.1f · turn delay median %.2fs max %.2fs · missed turns %d",
                          transcriptSpeakers, highestNumber, highestInTranscript, speakerLineChanges, mixedLines, mislabeledPercent,
                          Double(liveRelabels) / max(minutes, 0.01), median, delays.last ?? .nan, missedTurns)
        }
    }

    private func measure(_ s: Scenario, _ r: Result) -> Metrics {
        var m = Metrics()
        m.minutes = (s.phrases.last?.end ?? 0) / 60
        // Words are tagged "p<phrase>", so each transcript word knows who really said it.
        let lineWords: [(label: Int?, truths: [Int])] = r.lines.map { line in
            let text = (line.committed.map(\.text) + [line.tail ?? ""]).joined(separator: " ")
            let truths = text.split(separator: " ").compactMap { Int($0.dropFirst()) }.map { s.phrases[$0].truth }
            return (line.speaker, truths)
        }
        let labels = lineWords.compactMap(\.label)
        m.transcriptSpeakers = Set(labels).count
        m.highestNumber = (r.emissions.compactMap(\.label).max() ?? -1) + 1
        m.highestInTranscript = (labels.max() ?? -1) + 1
        m.speakerLineChanges = zip(labels, labels.dropFirst()).filter { $0 != $1 }.count
        m.mixedLines = lineWords.filter { Set($0.truths).count > 1 }.count
        // One-to-one by word votes: two people sharing one label is a merge, so only the bigger vote keeps it.
        var votes: [Int: [Int: Int]] = [:]
        for l in lineWords { if let label = l.label { for t in l.truths { votes[t, default: [:]][label, default: 0] += 1 } } }
        var labelFor: [Int: Int] = [:], taken = Set<Int>()
        let ranked = votes.flatMap { t, v in v.map { (truth: t, label: $0.key, n: $0.value) } }.sorted { $0.n > $1.n }
        for v in ranked where labelFor[v.truth] == nil && !taken.contains(v.label) { labelFor[v.truth] = v.label; taken.insert(v.label) }
        let total = lineWords.reduce(0) { $0 + $1.truths.count }
        let wrong = lineWords.reduce(0) { acc, l in acc + l.truths.filter { l.label == nil || l.label != labelFor[$0] }.count }
        m.mislabeledPercent = total == 0 ? 0 : 100 * Double(wrong) / Double(total)
        for (a, b) in zip(r.emissions, r.emissions.dropFirst()) where a.phrase == b.phrase && !b.isFinal {
            if let x = a.label, let y = b.label, x != y { m.liveRelabels += 1 }
        }
        for (p, ph) in s.phrases.enumerated() where p > 0 && s.phrases[p - 1].truth != ph.truth {
            if let hit = r.emissions.first(where: { $0.phrase == p && $0.label != nil && $0.label == labelFor[ph.truth] }) {
                m.turnDelays.append(hit.time - ph.start)
            } else { m.missedTurns += 1 }
        }
        return m
    }

    // MARK: runs

    private var model: URL {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return ProcessInfo.processInfo.environment["CAPTION_DIARIZER_MODEL"].map { URL(fileURLWithPath: $0) }
            ?? repo.appendingPathComponent("Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc")
    }

    private func scenarios() throws -> [Scenario] {
        [try monologue("Samantha"), try monologue("Daniel"),
         try dialogue("Samantha", "Daniel", name: "two voices (Samantha/Daniel)"),
         try dialogue("Eddy (English (US))", "Eddy (English (UK))", name: "similar voices (Eddy US/UK)"),
         try dialogue("Samantha", "Flo (English (US))", name: "two women (Samantha/Flo)")]
    }

    private func smoothed(_ make: @escaping () -> SpeakerLabelSmoother) -> () -> Labeler {
        {
            var smoother = make()
            return { smoother.label(start: $0.start, end: $0.end, segments: $0.segments, isFinal: $0.isFinal) }
        }
    }

    private var labelers: [(String, () -> Labeler)] { [
        ("before: SpeakerAligner", { { SpeakerAligner.speaker(start: $0.start, end: $0.end, segments: $0.segments) } }),
        ("after: SpeakerLabelSmoother", smoothed { SpeakerLabelSmoother() }),
    ] }

    /// The shipped model, plus any other Sortformer variant given by path (each needs its own model file):
    ///   CAPTION_DIARIZER_MODEL_BALANCED=/path/SortformerNvidiaLow_v2.1.mlmodelc
    private var models: [(String, URL, SortformerConfig)] {
        var all = [("fastV2_1 (shipped)", model, SortformerConfig.default)]
        if let p = ProcessInfo.processInfo.environment["CAPTION_DIARIZER_MODEL_BALANCED"] {
            all.append(("balancedV2_1", URL(fileURLWithPath: p), .balancedV2_1))
        }
        return all
    }

    func testReportSpeakerLabelStability() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_INTEGRATION"] == "1", "opt-in")
        let dump = ProcessInfo.processInfo.environment["CAPTION_STABILITY_DUMP"] == "1"
        for s in try scenarios() {
          for (modelName, url, config) in models {
            let clock = Date()
            let rec = try await record(s, model: url, config: config)
            let audioSeconds = Double(s.audio.count) / Self.sr + 3
            print(String(format: "SPEED \(s.name) | \(modelName) | %.0fx real time (replay incl. labeling bookkeeping)",
                         audioSeconds / Date().timeIntervalSince(clock)))
            for (name, make) in labelers {
                let r = play(rec, labeler: make())
                print("STABILITY \(s.name) | \(modelName) + \(name) | \(measure(s, r))")
                if dump {
                    for e in r.emissions {
                        print("EMIT t=\(String(format: "%5.1f", e.time)) phrase \(e.phrase) truth \(s.phrases[e.phrase].truth + 1) \(e.isFinal ? "FINAL" : "vol  ") -> \(e.label.map { String($0 + 1) } ?? "-")")
                    }
                }
            }
            if dump { for seg in rec.finalSegments { print("SEG speaker \(seg.speaker + 1) \(String(format: "%.2f", seg.start))-\(String(format: "%.2f", seg.end))") } }
          }
        }
    }
}

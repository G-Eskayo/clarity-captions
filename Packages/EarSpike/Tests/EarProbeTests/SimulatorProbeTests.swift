@preconcurrency import AVFoundation
import EarProbe
import EarSpikeKit
import Foundation
import Testing
@preconcurrency import Translation

// The device-side probes on the iPhone simulator (#233). Opt-in: EAR_PROBE=1 (through xcodebuild,
// TEST_RUNNER_EAR_PROBE=1). Each prints one `EARPROBE <name> <json>` line; scripts read the xcodebuild log.
private let enabled = ProcessInfo.processInfo.environment["EAR_PROBE"] == "1"

private func emit<T: Encodable>(_ name: String, _ value: T) throws {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    print("EARPROBE \(name) \(String(decoding: try e.encode(value), as: UTF8.self))")
}

@Suite(.enabled(if: enabled), .serialized) struct SimulatorProbeTests {
    @Test func voiceTable() async throws {
        let rows = await Voices.table()
        try emit("voices", rows)
        #expect(!rows.isEmpty)
    }

    /// Every language the device has a voice in, of any quality: a translation language missing here is captions only.
    @Test func allVoiceLanguages() throws {
        struct V: Encodable { let language: String; let name: String; let quality: String; let identifier: String }
        try emit("allvoices", AVSpeechSynthesisVoice.speechVoices().map {
            V(language: $0.language, name: $0.name, quality: Voices.quality($0.quality), identifier: $0.identifier)
        }.sorted { $0.identifier < $1.identifier })
    }

    @Test @MainActor func renderLag() async throws {
        struct Row: Encodable { let language: String; let voice: String?; let render: [SynthSample] }
        let synth = AVSpeechSynthesizer()
        let codes = AVSpeechSynthesisVoice.speechVoices().map(\.language)
        var rows: [Row] = []
        for target in ReferenceTranslations.lines.keys.sorted() {
            let voice = VoiceCoverage.voice(for: target, among: codes).flatMap { Voices.best(for: $0) }
            guard let voice, let lines = ReferenceTranslations.lines[target] else {
                rows.append(Row(language: target, voice: nil, render: [])); continue
            }
            var render: [SynthSample] = []
            for line in lines { render.append(await SynthLag.render(line, voice: voice, synth: synth)) }
            rows.append(Row(language: target, voice: voice.identifier, render: render))
        }
        try emit("render", rows)
    }

    /// What the simulator does when asked to translate: the pair's status and the error from an installed-only session.
    @Test func translate() async throws {
        struct Row: Encodable { let target: String; let status: String; let result: String }
        var rows: [Row] = []
        let availability = LanguageAvailability()
        for target in ["es", "fr", "de", "he", "ja"] {
            let status = await availability.status(from: Locale.Language(identifier: "en"),
                                                   to: Locale.Language(identifier: target))
            var result: String
            do {
                let t = try await TranslateLag.run(target: target, lines: SampleLines.english)
                result = "translated, cold \(Int(t.coldMs)) ms, warm \(t.warm.map { Int($0) })"
            } catch { result = "error: \(error)" }
            rows.append(Row(target: target, status: "\(status)", result: result))
        }
        try emit("translate", rows)
    }

    /// The audio route the app would play into, and its latencies, on the simulator (the Mac's output).
    @Test func audioRoute() throws {
        struct Route: Encodable {
            let category: String; let outputs: [String]; let inputs: [String]
            let outputLatencyMs: Double; let ioBufferMs: Double; let sampleRate: Double; let bluetoothHFPAllowed: Bool
            let setActiveError: String?
        }
        let s = AVAudioSession.sharedInstance()
        var err: String?
        do {
            try s.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers])
            try s.setActive(true)
        } catch { err = "\(error)" }
        let r = s.currentRoute
        try emit("route", Route(category: s.category.rawValue, outputs: r.outputs.map { "\($0.portType.rawValue): \($0.portName)" },
                                inputs: r.inputs.map { "\($0.portType.rawValue): \($0.portName)" },
                                outputLatencyMs: s.outputLatency * 1000, ioBufferMs: s.ioBufferDuration * 1000,
                                sampleRate: s.sampleRate, bluetoothHFPAllowed: s.categoryOptions.contains(.allowBluetoothHFP),
                                setActiveError: err))
    }
}

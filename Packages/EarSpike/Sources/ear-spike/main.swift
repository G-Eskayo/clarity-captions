// Live Translation in your ear, spike (#233). Measurements on this Mac; the probe tests run the device-side ones on
// the iPhone simulator.
//
//   swift run --package-path Packages/EarSpike ear-spike voices     --out DIR   which languages have a voice
//   swift run --package-path Packages/EarSpike ear-spike lag        --out DIR   translate + synthesize timings
//   swift run --package-path Packages/EarSpike ear-spike echo       --out DIR   the app's voice fed to the captioner
//   swift run --package-path Packages/EarSpike ear-spike fingerprint --out DIR  echo guard with the own-voice fingerprint
//   swift run --package-path Packages/EarSpike ear-spike finish-lag --out DIR   end of speech -> finished line (EdAcc, live-paced)
//   swift run --package-path Packages/EarSpike ear-spike headset-real --out DIR 16 kHz vs 8 kHz on real speech (EdAcc)
//   swift run --package-path Packages/EarSpike ear-spike acoustic   --out DIR   speaker -> mic, voice processing off/on
//   swift run --package-path Packages/EarSpike ear-spike headset    --out DIR   16 kHz vs 8 kHz vs room mic accuracy
@preconcurrency import AVFoundation
import EarProbe
import EarSpikeKit
import Foundation

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

let command = CommandLine.arguments.dropFirst().first ?? ""
let out = URL(fileURLWithPath: arg("--out") ?? FileManager.default.currentDirectoryPath)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

func save<T: Encodable>(_ value: T, _ name: String) throws {
    try encoder.encode(value).write(to: out.appendingPathComponent(name))
    print("wrote \(out.appendingPathComponent(name).path)")
}

let host = ProcessInfo.processInfo.hostName
let os = ProcessInfo.processInfo.operatingSystemVersionString

struct Envelope<T: Encodable>: Encodable { let device: String; let os: String; let date: String; let results: T }
func envelope<T: Encodable>(_ r: T) -> Envelope<T> {
    Envelope(device: "Mac mini (\(host))", os: "macOS \(os)", date: ISO8601DateFormatter().string(from: Date()), results: r)
}

switch command {
case "voices":
    let rows = await Voices.table()
    try save(envelope(rows), "voices-mac.json")
    for r in rows { print("\(r.language)\t\(r.fromEnglish)\t\(r.voice ?? "-")\t\(r.bestQuality ?? "-")") }

case "lag":
    struct LangLag: Encodable {
        let language: String; let voice: String?; let translate: TranslateTiming?
        let render: [SynthSample]; let speak: [SpeakSample]; let error: String?
    }
    var results: [LangLag] = []
    let synth = AVSpeechSynthesizer()
    let only = arg("--only")?.split(separator: ",").map(String.init)
    let codes = AVSpeechSynthesisVoice.speechVoices().map(\.language)
    for target in ReferenceTranslations.lines.keys.sorted() where only == nil || only!.contains(target) {
        let (t, lines) = await TranslateLag.linesOrReference(target: target, lines: SampleLines.english)
        let voice = VoiceCoverage.voice(for: target, among: codes).flatMap { Voices.best(for: $0) }
        guard let lines, let voice else {
            results.append(LangLag(language: target, voice: nil, translate: t, render: [], speak: [], error: "no voice"))
            continue
        }
        var render: [SynthSample] = []
        var speak: [SpeakSample] = []
        for line in lines { render.append(await SynthLag.render(line, voice: voice, synth: synth)) }
        if arg("--speak") != nil {
            for line in lines.prefix(3) { speak.append(await SynthLag.speak(line, voice: voice)) }
        }
        results.append(LangLag(language: target, voice: voice.identifier, translate: t, render: render, speak: speak,
                               error: t == nil ? "pair not installed: reference translation, no translate timing" : nil))
        let a = LagStats(render.dropFirst().map(\.audibleMs))
        print("\(target)\t\(voice.identifier)\taudible p50 \(Int(a.median ?? -1)) p95 \(Int(a.p95 ?? -1)) first(cold) \(Int(render.first?.audibleMs ?? -1)) speak.didStart \(speak.map { Int($0.didStartMs) })")
    }
    // English itself, the voice with no translation in front of it.
    let en = Voices.best(for: "en-US")
    var enRender: [SynthSample] = []
    for line in SampleLines.english { enRender.append(await SynthLag.render(line, voice: en, synth: synth)) }
    results.append(LangLag(language: "en", voice: en?.identifier, translate: nil, render: enRender, speak: [], error: nil))
    // What the output adds after the first buffer: the device's presentation latency (Mac mini speakers here; a
    // Bluetooth headset adds its own, measured only on a device).
    let engine = AVAudioEngine()
    _ = engine.mainMixerNode
    let outputLatencyMs = engine.outputNode.presentationLatency * 1000
    print("output presentation latency \(outputLatencyMs) ms")
    struct LagFile: Encodable { let outputPresentationLatencyMs: Double; let languages: [LangLag] }
    try save(envelope(LagFile(outputPresentationLatencyMs: outputLatencyMs, languages: results)), arg("--name") ?? "lag-mac.json")

case "echo":
    // The app speaks the translation; the phone's mic hears it; the caption engine (still in the other person's
    // language, English here) captions it. Fed digitally, the worst case: no room, no distance, no echo canceller.
    struct EchoLine: Encodable {
        let spoken: String; let source: String
        let captionedBySourceEngine: String; let sourceEngineSimilarity: Double
        let captionedByTargetEngine: String?; let targetEngineSimilarity: Double?
        let realSpeechSimilarity: Double // the English line itself vs the spoken translation: false-echo risk
    }
    var results: [String: [EchoLine]] = [:]
    let synth = AVSpeechSynthesizer()
    let en = Locale(identifier: "en-US")
    try await Transcribe.ensureInstalled(en)
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ear-spike-echo")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let pairs = (arg("--targets") ?? "es:es-ES,fr:fr-FR,de:de-DE,it:it-IT,he:-,ja:ja-JP").split(separator: ",")
    for pair in pairs {
        let bits = pair.split(separator: ":").map(String.init)
        let target = bits[0], engine = bits.count > 1 && bits[1] != "-" ? Locale(identifier: bits[1]) : nil
        var targetEngine = engine
        if let e = engine { do { try await Transcribe.ensureInstalled(e) } catch { targetEngine = nil } }
        let (_, translated) = await TranslateLag.linesOrReference(target: target, lines: SampleLines.english)
        guard let tlines = translated,
              let voice = Voices.best(for: VoiceCoverage.voice(for: target, among: AVSpeechSynthesisVoice.speechVoices().map(\.language)) ?? "")
        else { print("\(target): no pair or no voice"); continue }
        var lines: [EchoLine] = []
        for (i, spoken) in tlines.enumerated() {
            var bufs: [AVAudioPCMBuffer] = []
            _ = await SynthLag.render(spoken, voice: voice, synth: synth) { b in
                let copy = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength)!
                copy.frameLength = b.frameLength
                if let s = b.int16ChannelData { memcpy(copy.int16ChannelData![0], s[0], Int(b.frameLength) * 2) }
                if let s = b.floatChannelData { memcpy(copy.floatChannelData![0], s[0], Int(b.frameLength) * 4) }
                bufs.append(copy)
            }
            let audio = AudioFiles.concat([AudioFiles.silence(0.5, rate: 16000), try AudioFiles.resample(bufs, to: 16000),
                                           AudioFiles.silence(0.5, rate: 16000)])
            let url = tmp.appendingPathComponent("\(target)-\(i).caf")
            try AudioFiles.write(audio, to: url)
            let bySource = (try? await Transcribe.file(url, locale: en)) ?? ""
            let byTarget = targetEngine == nil ? nil : (try? await Transcribe.file(url, locale: targetEngine!)) ?? ""
            lines.append(EchoLine(spoken: spoken, source: SampleLines.english[i], captionedBySourceEngine: bySource,
                                  sourceEngineSimilarity: EchoGuard.similarity(caption: bySource, spoken: spoken),
                                  captionedByTargetEngine: byTarget,
                                  targetEngineSimilarity: byTarget.map { EchoGuard.similarity(caption: $0, spoken: spoken) },
                                  realSpeechSimilarity: EchoGuard.similarity(caption: SampleLines.english[i], spoken: spoken)))
            print("\(target)[\(i)] en-engine: \"\(bySource)\" | \(targetEngine?.identifier ?? "-"): \"\(byTarget ?? "-")\"")
        }
        results[target] = lines
    }
    try? FileManager.default.removeItem(at: tmp)
    try save(envelope(results), "echo-digital-mac.json")

case "fingerprint":
    // The echo guard's own-voice fingerprint: the app captions its rendered voice with the caption engine (English
    // here) before playing it, then a caption of that voice coming back through the mic should match. The way back is
    // simulated (8 kHz band, then 8 kHz plus noise at 10 dB SNR); a real speaker-to-mic test is a device step.
    struct Line: Encodable {
        let spoken: String; let heardAs: String; let condition: String; let echoCaption: String
        let caughtWordsOnly: Bool; let caughtWithFingerprint: Bool
    }
    struct Lang: Encodable { let language: String; let lines: [Line]; let falseEchoes: Int; let realLinesChecked: Int }
    let synth = AVSpeechSynthesizer()
    let en = Locale(identifier: "en-US")
    try await Transcribe.ensureInstalled(en)
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ear-spike-fingerprint")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    var langs: [Lang] = []
    for target in (arg("--targets") ?? "es,fr,de,it,he,ja").split(separator: ",").map(String.init) {
        let (_, translated) = await TranslateLag.linesOrReference(target: target, lines: SampleLines.english)
        guard let tlines = translated,
              let voice = Voices.best(for: VoiceCoverage.voice(for: target, among: AVSpeechSynthesisVoice.speechVoices().map(\.language)) ?? "")
        else { print("\(target): no pair or no voice"); continue }
        var lines: [Line] = []
        var falseEchoes = 0, realChecked = 0
        for (i, spoken) in tlines.enumerated() {
            var bufs: [AVAudioPCMBuffer] = []
            _ = await SynthLag.render(spoken, voice: voice, synth: synth) { b in
                let copy = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength)!
                copy.frameLength = b.frameLength
                if let s = b.int16ChannelData { memcpy(copy.int16ChannelData![0], s[0], Int(b.frameLength) * 2) }
                if let s = b.floatChannelData { memcpy(copy.floatChannelData![0], s[0], Int(b.frameLength) * 4) }
                bufs.append(copy)
            }
            let clean = AudioFiles.concat([AudioFiles.silence(0.5, rate: 16000), try AudioFiles.resample(bufs, to: 16000),
                                           AudioFiles.silence(0.5, rate: 16000)])
            let cu = tmp.appendingPathComponent("c.caf")
            try AudioFiles.write(clean, to: cu)
            let heardAs = (try? await Transcribe.file(cu, locale: en)) ?? ""
            let narrow = try AudioFiles.narrowband(clean)
            var guardWords = EchoGuard(), guardPrint = EchoGuard()
            guardWords.spoke(spoken, from: 0, to: 4)
            guardPrint.spoke(spoken, heardAs: heardAs, from: 0, to: 4)
            for (name, audio) in [("8 kHz", narrow), ("8 kHz + noise 10 dB", AudioFiles.noisy(narrow, snrDb: 10))] {
                let u = tmp.appendingPathComponent("d.caf")
                try AudioFiles.write(audio, to: u)
                let echo = (try? await Transcribe.file(u, locale: en)) ?? ""
                lines.append(Line(spoken: spoken, heardAs: heardAs, condition: name, echoCaption: echo,
                                  caughtWordsOnly: echo.isEmpty || guardWords.isEcho(echo, from: 0.3, to: 4.2),
                                  caughtWithFingerprint: echo.isEmpty || guardPrint.isEcho(echo, from: 0.3, to: 4.2)))
                print("\(target)[\(i)] \(name): heard \"\(heardAs)\" echo \"\(echo)\" words \(lines.last!.caughtWordsOnly) print \(lines.last!.caughtWithFingerprint)")
            }
            // The other person talking over the voice: every English sample line must stay a caption.
            for real in SampleLines.english {
                realChecked += 1
                if guardPrint.isEcho(real, from: 0.3, to: 4.2) { falseEchoes += 1; print("  FALSE ECHO: \(real)") }
            }
        }
        langs.append(Lang(language: target, lines: lines, falseEchoes: falseEchoes, realLinesChecked: realChecked))
    }
    try? FileManager.default.removeItem(at: tmp)
    try save(envelope(langs), "echo-fingerprint-mac.json")
    for l in langs {
        let w = l.lines.filter(\.caughtWordsOnly).count, p = l.lines.filter(\.caughtWithFingerprint).count
        print("\(l.language): caught words-only \(w)/\(l.lines.count), with fingerprint \(p)/\(l.lines.count), false echoes \(l.falseEchoes)/\(l.realLinesChecked)")
    }

case "finish-lag":
    // End of speech to finished line, on real conversational English (EdAcc) played in real time: the wait before
    // the translator can start. 10 clips per stream with 2 s gaps, like turns in a conversation.
    let shard = URL(fileURLWithPath: arg("--shard") ?? NSString(string: "~/edacc-eval/shards-203/shard-001").expandingTildeInPath)
    let clips = try EdaccClip.load(shard: shard, min: 3, max: 15, count: Int(arg("--clips") ?? "40")!)
    let en = Locale(identifier: "en-US")
    try await Transcribe.ensureInstalled(en)
    var all: [LineTiming] = []
    for (si, group) in stride(from: 0, to: clips.count, by: 10).map({ Array(clips[$0..<min($0 + 10, clips.count)]) }).enumerated() {
        var parts: [AVAudioPCMBuffer] = []
        for c in group { parts.append(try c.audio(in: shard)); parts.append(AudioFiles.silence(2.0, rate: 16000)) }
        let lines = try await StreamLag.run(AudioFiles.concat(parts), locale: en)
        all += lines
        let lag = LagStats(lines.filter { !$0.afterInputEnded }.map(\.finishLagMs))
        print("stream \(si): \(lines.count) lines, finish lag p50 \(Int(lag.median ?? -1)) p95 \(Int(lag.p95 ?? -1)) ms")
    }
    let live = all.filter { !$0.afterInputEnded }
    struct F: Encodable {
        let clips: [String]; let lines: [LineTiming]
        let finishLag: LagStats; let headStart3: LagStats; let headStart5: LagStats
        let linesWithStable3: Int; let linesWithStable5: Int
    }
    let f = F(clips: clips.map(\.clipID), lines: all, finishLag: LagStats(live.map(\.finishLagMs)),
              headStart3: LagStats(live.compactMap(\.headStart3Ms)), headStart5: LagStats(live.compactMap(\.headStart5Ms)),
              linesWithStable3: live.filter { $0.headStart3Ms != nil }.count, linesWithStable5: live.filter { $0.headStart5Ms != nil }.count)
    try save(envelope(f), "finish-lag-mac.json")
    print("all: \(live.count) lines; finish lag p50 \(f.finishLag.median ?? -1) p95 \(f.finishLag.p95 ?? -1); head start 3w p50 \(f.headStart3.median ?? -1) (\(f.linesWithStable3) lines), 5w p50 \(f.headStart5.median ?? -1) (\(f.linesWithStable5))")

case "headset-real":
    // Real conversational English (EdAcc) at 16 kHz (the band an mSBC headset mic carries, no codec loss) and
    // narrowed to 8 kHz (CVSD, older headsets). Pooled WER, the same clips both ways.
    let shard = URL(fileURLWithPath: arg("--shard") ?? NSString(string: "~/edacc-eval/shards-203/shard-001").expandingTildeInPath)
    let clips = try EdaccClip.load(shard: shard, min: 3, max: 15, count: Int(arg("--clips") ?? "80")!)
    let en = Locale(identifier: "en-US")
    try await Transcribe.ensureInstalled(en)
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ear-spike-headset-real")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    struct Clip: Encodable { let clip: String; let words: Int; let wide: Double; let narrow: Double }
    var rows: [Clip] = []
    for c in clips {
        let wide = try c.audio(in: shard)
        let wu = tmp.appendingPathComponent("w.caf"), nu = tmp.appendingPathComponent("n.caf")
        try AudioFiles.write(wide, to: wu); try AudioFiles.write(try AudioFiles.narrowband(wide), to: nu)
        let words = WordErrorRate.normal(c.reference).count
        rows.append(Clip(clip: c.clipID, words: words,
                         wide: WordErrorRate.of((try? await Transcribe.file(wu, locale: en)) ?? "", reference: c.reference),
                         narrow: WordErrorRate.of((try? await Transcribe.file(nu, locale: en)) ?? "", reference: c.reference)))
    }
    try? FileManager.default.removeItem(at: tmp)
    func pooled(_ k: KeyPath<Clip, Double>) -> Double {
        rows.reduce(0) { $0 + $1[keyPath: k] * Double($1.words) } / Double(rows.reduce(0) { $0 + $1.words })
    }
    struct H: Encodable { let clips: [Clip]; let pooledWER16k: Double; let pooledWER8k: Double; let narrowWorseClips: Int }
    let h = H(clips: rows, pooledWER16k: pooled(\.wide), pooledWER8k: pooled(\.narrow),
              narrowWorseClips: rows.filter { $0.narrow > $0.wide }.count)
    try save(envelope(h), "headset-real-mac.json")
    print("EdAcc \(rows.count) clips: 16 kHz WER \(h.pooledWER16k), 8 kHz WER \(h.pooledWER8k), 8 kHz worse on \(h.narrowWorseClips)")

case "acoustic":
    // Out loud: Mac mini speakers -> USB camera mic (16 kHz) in the same room, voice processing off then on.
    struct Run: Encodable {
        let voiceProcessing: Bool; let error: String?; let recordingRMS: Double
        let captionedEnglishEngine: String; let captionedTargetEngine: String; let spoken: String
    }
    let target = arg("--target") ?? "es"
    let targetLocale = Locale(identifier: arg("--target-engine") ?? "es-ES")
    let synth = AVSpeechSynthesizer()
    let tl = Array((await TranslateLag.linesOrReference(target: target, lines: SampleLines.english)).1!.prefix(4))
    let voice = Voices.best(for: VoiceCoverage.voice(for: target, among: AVSpeechSynthesisVoice.speechVoices().map(\.language)) ?? "")
    var parts: [AVAudioPCMBuffer] = []
    for line in tl {
        var bufs: [AVAudioPCMBuffer] = []
        _ = await SynthLag.render(line, voice: voice, synth: synth) { b in
            let copy = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength)!
            copy.frameLength = b.frameLength
            if let s = b.int16ChannelData { memcpy(copy.int16ChannelData![0], s[0], Int(b.frameLength) * 2) }
            if let s = b.floatChannelData { memcpy(copy.floatChannelData![0], s[0], Int(b.frameLength) * 4) }
            bufs.append(copy)
        }
        parts.append(try AudioFiles.resample(bufs, to: 48000))
        parts.append(AudioFiles.silence(0.6, rate: 48000))
    }
    let play = AudioFiles.concat(parts)
    var runs: [Run] = []
    for vp in [false, true] {
        let take = await Acoustic.playAndRecord(play, voiceProcessing: vp)
        let url = out.appendingPathComponent("acoustic-\(vp ? "vp" : "plain").caf")
        try AudioFiles.write(take.recording, to: url)
        let english = (try? await Transcribe.file(url, locale: Locale(identifier: "en-US"))) ?? ""
        let other = (try? await Transcribe.file(url, locale: targetLocale)) ?? ""
        runs.append(Run(voiceProcessing: vp, error: take.error, recordingRMS: AudioFiles.rms(take.recording),
                        captionedEnglishEngine: english, captionedTargetEngine: other, spoken: tl.joined(separator: " ")))
        print("vp=\(vp) rms=\(AudioFiles.rms(take.recording)) err=\(take.error ?? "-")\n  en: \(english)\n  \(target): \(other)")
        if arg("--keep") == nil { try? FileManager.default.removeItem(at: url) }
    }
    try save(envelope(runs), "echo-acoustic-mac.json")

case "headset":
    // Synthetic English (the Mac's best voices) at the 16 kHz a modern Bluetooth headset mic carries (mSBC) and the
    // 8 kHz of an older one (CVSD), then out loud through the room to a USB mic. Relative only: real voices,
    // real headset codecs and noise suppression are a device test.
    struct Cond: Encodable { let condition: String; let wer: Double; let perLine: [Double] }
    let synth = AVSpeechSynthesizer()
    let en = Locale(identifier: "en-US")
    try await Transcribe.ensureInstalled(en)
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ear-spike-headset")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let harvard = [
        "The birch canoe slid on the smooth planks.", "Glue the sheet to the dark blue background.",
        "It's easy to tell the depth of a well.", "These days a chicken leg is a rare dish.",
        "Rice is often served in round bowls.", "The juice of lemons makes fine punch.",
        "The box was thrown beside the parked truck.", "The hogs were fed chopped corn and garbage.",
        "Four hours of steady work faced us.", "A large size in stockings is hard to sell.",
    ] + SampleLines.english
    let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en-") }
        .sorted { $0.quality.rawValue > $1.quality.rawValue }.prefix(3)
    var wide: [Double] = [], narrow: [Double] = [], room: [Double] = []
    let doRoom = arg("--room") != nil
    for (vi, v) in voices.enumerated() {
        for (i, line) in harvard.enumerated() {
            var bufs: [AVAudioPCMBuffer] = []
            _ = await SynthLag.render(line, voice: v, synth: synth) { b in
                let copy = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength)!
                copy.frameLength = b.frameLength
                if let s = b.int16ChannelData { memcpy(copy.int16ChannelData![0], s[0], Int(b.frameLength) * 2) }
                if let s = b.floatChannelData { memcpy(copy.floatChannelData![0], s[0], Int(b.frameLength) * 4) }
                bufs.append(copy)
            }
            let w = AudioFiles.concat([AudioFiles.silence(0.4, rate: 16000), try AudioFiles.resample(bufs, to: 16000),
                                       AudioFiles.silence(0.4, rate: 16000)])
            let n = try AudioFiles.narrowband(w)
            let wu = tmp.appendingPathComponent("w\(vi)-\(i).caf"), nu = tmp.appendingPathComponent("n\(vi)-\(i).caf")
            try AudioFiles.write(w, to: wu); try AudioFiles.write(n, to: nu)
            wide.append(WordErrorRate.of((try? await Transcribe.file(wu, locale: en)) ?? "", reference: line))
            narrow.append(WordErrorRate.of((try? await Transcribe.file(nu, locale: en)) ?? "", reference: line))
            if doRoom {
                let take = await Acoustic.playAndRecord(try AudioFiles.resample([w], to: 48000), voiceProcessing: false, tail: 0.6)
                let ru = tmp.appendingPathComponent("r\(vi)-\(i).caf")
                try AudioFiles.write(take.recording, to: ru)
                room.append(WordErrorRate.of((try? await Transcribe.file(ru, locale: en)) ?? "", reference: line))
            }
        }
        print("voice \(v.identifier): wide \(wide.suffix(harvard.count).reduce(0,+)/Double(harvard.count)) narrow \(narrow.suffix(harvard.count).reduce(0,+)/Double(harvard.count))")
    }
    try? FileManager.default.removeItem(at: tmp)
    func mean(_ a: [Double]) -> Double { a.isEmpty ? .nan : a.reduce(0, +) / Double(a.count) }
    var conds = [Cond(condition: "16 kHz (mSBC headset band)", wer: mean(wide), perLine: wide),
                 Cond(condition: "8 kHz (CVSD headset band)", wer: mean(narrow), perLine: narrow)]
    if doRoom { conds.append(Cond(condition: "speaker -> USB mic ~1 m (16 kHz)", wer: mean(room), perLine: room)) }
    struct H: Encodable { let voices: [String]; let lines: Int; let conditions: [Cond] }
    try save(envelope(H(voices: voices.map(\.identifier), lines: harvard.count, conditions: conds)), "headset-band-mac.json")
    for c in conds { print("\(c.condition): WER \(c.wer)") }

default:
    print("usage: ear-spike voices|lag|echo|fingerprint|finish-lag|headset-real|acoustic|headset --out DIR")
    exit(2)
}

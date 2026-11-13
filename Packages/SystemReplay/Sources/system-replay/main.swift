import AVFoundation
import CaptionCore
import Foundation
import SystemReplayKit

// system-replay (#273): recorded audio through the app's own live path, in real time.
//
//   system-replay run   --audio FILE.wav --out SESSION.json --diarizer Sortformer_v2.1.mlmodelc [--parakeet DIR]
//                       [--engine parakeet|apple] [--locale en-US] [--rate 48000] [--frames 4096] [--tail 3] [--label L]
//                       [--path source|replaying]  (replaying: the engine's own startReplaying, the only file path in 1.0)
//   system-replay batch --list LIST.jsonl --audio-dir DIR --out-dir DIR  (same options; one session per line, resumable)
//
// The path, end to end: ReplayAudioSource (an AudioSource, as the microphone is) -> TranscriptionEngine (its
// converters, the 16 kHz side path, diarizer, sound labeler, loudness, EngineFallbackPolicy triggers) -> the
// recognizer CaptionEnginePlan picks -> CaptionSessionController -> the app's CaptionStream line building. Nothing
// between the source and the lines is skipped. docs/perf/whole-system-replay-design.md.

func arg(_ name: String, _ args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("system-replay: \(message)\n".utf8))
    exit(2)
}

func uptime() -> Double { ProcessInfo.processInfo.systemUptime }

#if !CAPTIONCORE_1_0
/// A recording as the engine's audio source, shaped like the iPhone's microphone tap: by default 48 kHz mono
/// Float32 in 4096-frame buffers, each handed over when its last sample has been "spoken" (ReplaySchedule), so the
/// engine does the same conversion to 16 kHz it does live. After the file, `tailSeconds` of silence (a quiet room
/// before she taps Stop), then `onEnd`.
final class ReplayAudioSource: AudioSource, @unchecked Sendable {
    private let url: URL
    private let rate: Double
    private let framesPerBuffer: Int
    private let tailSeconds: Double
    private var samples: [Float] = []
    private var format: AVAudioFormat?
    private let lock = NSLock()
    private var running = false
    private var startedAtValue: Double?
    /// Uptime when `start` was called: the zero of every `at` in the session log.
    var startedAt: Double? { lock.withLock { startedAtValue } }
    var onEnd: () -> Void = {}
    private(set) var fileSeconds = 0.0

    init(url: URL, rate: Double, framesPerBuffer: Int, tailSeconds: Double) {
        self.url = url
        self.rate = rate
        self.framesPerBuffer = framesPerBuffer
        self.tailSeconds = tailSeconds
    }

    func open() throws -> AVAudioFormat {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard let whole = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }
        try file.read(into: whole)
        fileSeconds = Double(whole.frameLength) / inFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(whole.frameLength) * rate / inFormat.sampleRate) + 8192
        guard let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: out),
              let converted = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: capacity)
        else { throw TranscriptionError.converterUnavailable }
        // Converted once, up front: the mic hands over buffers that already exist, so the replay's own work stays
        // out of the paced loop.
        var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return whole
        }
        if let error { throw error }
        let n = Int(converted.frameLength)
        samples = Array(UnsafeBufferPointer(start: converted.floatChannelData![0], count: n))
        samples += [Float](repeating: 0, count: Int(tailSeconds * rate))
        format = out
        return out
    }

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard let format else { throw TranscriptionError.noCompatibleAudioFormat }
        lock.withLock { running = true; startedAtValue = uptime() }
        let schedule = ReplaySchedule(sampleRate: rate, framesPerBuffer: framesPerBuffer)
        let samples = self.samples
        let thread = Thread { [weak self] in
            PacedLoop.run(schedule: schedule, totalFrames: samples.count, now: uptime,
                          sleepUntil: { due in let d = due - uptime(); if d > 0 { Thread.sleep(forTimeInterval: d) } },
                          shouldContinue: { self?.isRunning ?? false }) { _, span in
                guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(span.count)) else { return }
                buf.frameLength = AVAudioFrameCount(span.count)
                samples.withUnsafeBufferPointer { src in
                    buf.floatChannelData![0].update(from: src.baseAddress! + span.lowerBound, count: span.count)
                }
                onBuffer(buf)
            }
            self?.onEnd()
        }
        thread.qualityOfService = .userInteractive   // the mic's tap runs on a real-time thread
        thread.start()
    }

    private var isRunning: Bool { lock.withLock { running } }

    func stop() { lock.withLock { running = false } }
}

#else
/// 1.0 has no AudioSource: only the engine's own startReplaying path runs, and nothing makes one of these.
final class ReplayAudioSource {
    var startedAt: Double? { nil }
    var onEnd: () -> Void = {}
    var fileSeconds: Double { 0 }
}
#endif

/// Fallback callbacks arrive on the engine's threads.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func mutate(_ f: (inout T) -> Void) { lock.withLock { f(&value) } }
    var get: T { lock.withLock { value } }
}

struct Options {
    var diarizer: URL
    var parakeet: URL?
    /// "parakeet" or "apple": the developer panel's pick (CaptionEngineChoice), for isolating the engine.
    var choice: String
    var locale: Locale
    var rate: Double
    var frames: Int
    var tail: Double
    var stopWait: Double
    var label: String
    var path: String

    init(_ args: [String]) {
        guard let d = arg("--diarizer", args) else { fail("--diarizer is required (Sortformer_v2.1.mlmodelc)") }
        diarizer = URL(fileURLWithPath: d)
        parakeet = arg("--parakeet", args).map { URL(fileURLWithPath: $0) }
        choice = arg("--engine", args) ?? "parakeet"
        guard ["parakeet", "apple"].contains(choice) else { fail("--engine parakeet|apple") }
        locale = Locale(identifier: arg("--locale", args) ?? "en-US")
        rate = Double(arg("--rate", args) ?? "48000") ?? 48_000
        frames = Int(arg("--frames", args) ?? "4096") ?? 4_096
        tail = Double(arg("--tail", args) ?? "3") ?? 3
        stopWait = Double(arg("--stop-wait", args) ?? "10") ?? 10
        label = arg("--label", args) ?? "unlabelled"
        path = arg("--path", args) ?? "source"
        guard ["source", "replaying"].contains(path) else { fail("--path source|replaying") }
        #if CAPTIONCORE_1_0
        if path == "source" { fail("1.0 has no AudioSource: use --path replaying") }
        #endif
        if choice == "parakeet" && parakeet == nil {
            FileHandle.standardError.write(Data("system-replay: no --parakeet: the plan will say modelMissing\n".utf8))
        }
    }
}

func stateName(_ s: CaptionState) -> String {
    switch s {
    case .idle: "idle"
    case .preparing: "preparing"
    case .listening: "listening"
    case .failed(let why): "failed: \(why)"
    case .pausedQuiet(let m): "pausedQuiet(\(m))"
    }
}

/// One session, the way the iPhone app runs one (CaptionEngineFactory.make, EngineWarmup's load ahead of Start, then
/// CaptionModel's controller callbacks), with the clock, the plan and every engine change written down.
@MainActor
func replay(audio: URL, options o: Options) async -> SessionLog {
    let made = makeEngine(audio: audio, options: o, path: o.path)
    let engine = made.engine, source = made.source
    var log = SessionLog(label: o.label, audio: audio.lastPathComponent, audioSeconds: 0, tailSeconds: source == nil ? 0 : o.tail,
                         deliveryRate: o.rate, framesPerBuffer: o.frames, host: ProcessInfo.processInfo.hostName,
                         os: ProcessInfo.processInfo.operatingSystemVersionString,
                         startedAt: ISO8601DateFormatter().string(from: Date()), plan: made.plan)
    log.path = o.path
    if o.path == "replaying" {
        // startReplaying reads the file's own format in 4096-frame buffers: replay the 48 kHz Float32 copy.
        if let f = try? AVAudioFile(forReading: audio) {
            log.deliveryRate = f.processingFormat.sampleRate
            log.framesPerBuffer = 4_096
            log.audioSeconds = Double(f.length) / f.processingFormat.sampleRate
        }
    }
    var zero: Double?
    func at() -> Double {
        if let s = source?.startedAt { return uptime() - s }
        return zero.map { uptime() - $0 } ?? 0
    }
    let fallbacks = Box<[SessionLog.Fallback]>([])
    let decodeWindows = Box<[Double]>([])
    let clockBox = Box<Double?>(nil)
    watchFallbacks(engine, into: fallbacks) {
        if let s = source?.startedAt { return uptime() - s }
        return clockBox.get.map { uptime() - $0 } ?? -1
    }
    engine.onDecodeWindow = { time in
        decodeWindows.mutate { $0.append(time) }
    }
    let wallStart = uptime()

    let captioning: CaptioningEngine
    if source != nil {
        // EngineWarmup: the app loads the engine during the launch, before Start.
        let loadStart = uptime()
        do { try await engine.prepare { _ in } } catch {
            log.error = "prepare failed: \(error)"
            await engine.stop()
            return log
        }
        log.loadSeconds = uptime() - loadStart
        captioning = engine
    } else {
        // startReplaying loads what it needs itself (1.0 makes its own analyzer there).
        captioning = ReplayingEngine(engine, url: audio)
    }

    var stream = CaptionStream()
    let controller = CaptionSessionController(makeEngine: { captioning })
    var ended: CheckedContinuation<Void, Never>?
    var done = false
    var sawListening = false
    func finish() {
        done = true
        if let e = ended { ended = nil; e.resume() }
    }
    let audioSeconds = max(log.audioSeconds, (try? AVAudioFile(forReading: audio)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0)
    var stopTap: Task<Void, Never>?
    controller.onStateChange = { s in
        if s == .listening, zero == nil {
            zero = uptime(); clockBox.mutate { $0 = zero }
            // Replaying path: she taps Stop 2 s after the recording (and its silent tail) has played, the same moment
            // for every build. 1.0's own replay never ends its stream by itself; build 10's ends at the file's end.
            if source == nil {
                stopTap = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(audioSeconds + 2))
                    if !done { log.stoppedByTap = true; finish() }
                }
            }
        }
        log.states.append(.init(state: stateName(s), at: at()))
        if s == .listening { sawListening = true }
        if case .failed = s { finish() }
        if s == .idle, sawListening { finish() }
    }
    controller.onStartup = { log.startupReport = $0 }
    controller.onSoundLabel = { stream.insertSoundLabel($0) }
    controller.onUpdate = { u in
        apply(u, to: &stream)
        let e = engineOf(u)
        log.record(.init(at: at(), text: u.text, isFinal: u.isFinal, lag: u.lagSeconds, speaker: u.speaker,
                         start: u.startSeconds, end: u.endSeconds, engine: e.name, fallback: e.fallback))
    }
    source?.onEnd = { Task { @MainActor in finish() } }

    controller.start()
    // Source path: ends when the recording and its silent tail have been fed. Replaying path: when the engine's own
    // replay finishes its stream (the controller goes idle). Either way a failure ends it, and a hard limit stops a
    // hung session: twice the audio plus four minutes.
    let limit = Task { @MainActor in
        try? await Task.sleep(for: .seconds(2 * (audioSeconds + o.tail) + 240))
        if !done { log.error = "timed out"; finish() }
    }
    if !done { await withCheckedContinuation { c in ended = c } }
    limit.cancel()
    stopTap?.cancel()
    let stopStart = uptime()
    // Stop, waited for at most `stopWait` seconds. 1.0's Stop takes minutes on a Mac with no microphone (it waits on
    // its analyzer and the mic's input node); its lines are complete by then. The lines are taken as they are when
    // the wait ends, the same rule for every arm; `run` exits the process right after, which frees anything left.
    var stopped = false
    let stopTask = Task { @MainActor in await controller.stopAndWait(); stopped = true }
    while !stopped && uptime() - stopStart < o.stopWait { try? await Task.sleep(for: .milliseconds(50)) }
    if stopped { log.stopSeconds = uptime() - stopStart } else { log.stopTimedOut = true }
    _ = stopTask
    // Stop flushes the recognizer's last words as final; give the main actor a moment to apply them.
    try? await Task.sleep(for: .milliseconds(500))

    if let source { log.audioSeconds = source.fileSeconds }
    log.wallSeconds = uptime() - wallStart
    log.decodeWindows = decodeWindows.get
    captureEngineState(&log, from: engine, fallbacks: fallbacks.get)
    log.lines = stream.lines.map { .init(text: $0.text, speaker: $0.speaker, soundLabel: $0.soundLabel.map { "\($0)" }) }
    if let failed = log.states.first(where: { $0.state.hasPrefix("failed") }), log.error == nil { log.error = failed.state }
    if !sawListening, log.error == nil { log.error = "never reached listening" }
    return log
}

func write(_ log: SessionLog, to url: URL) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let tmp = url.appendingPathExtension("part")
    try enc.encode(log).write(to: tmp)
    _ = try? FileManager.default.removeItem(at: url)
    try FileManager.default.moveItem(at: tmp, to: url)
}

func summary(_ log: SessionLog) -> String {
    let finals = log.updates.filter(\.isFinal).count
    let lags = log.updates.compactMap(\.lag).sorted()
    let p50 = lags.isEmpty ? "-" : String(format: "%.2f", lags[lags.count / 2])
    return "plan \(log.plan.engine)\(log.plan.reason.map { " (\($0))" } ?? "") · ran \(log.enginesSeen.map(\.name).joined(separator: " -> "))"
        + " · fallbacks \(log.fallbacks.map(\.reason)) · finals \(finals) · word lag p50 \(p50)s · \(String(format: "%.0f", log.wallSeconds))s"
        + (log.error.map { " · ERROR \($0)" } ?? "")
}

@MainActor
func main() async {
    setvbuf(stdout, nil, _IOLBF, 0)
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "run":
        guard let audio = arg("--audio", args), let out = arg("--out", args) else { fail("run needs --audio and --out") }
        let log = await replay(audio: URL(fileURLWithPath: audio), options: Options(args))
        do { try write(log, to: URL(fileURLWithPath: out)) } catch { fail("writing \(out): \(error)") }
        print("SYSTEM-REPLAY \(log.audio) \(summary(log))")
        exit(log.error == nil ? 0 : 1)
    case "batch":
        guard let list = arg("--list", args), let audioDir = arg("--audio-dir", args), let outDir = arg("--out-dir", args) else {
            fail("batch needs --list, --audio-dir and --out-dir")
        }
        let options = Options(args)
        guard let text = try? String(contentsOfFile: list, encoding: .utf8) else { fail("can't read \(list)") }
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let items = text.split(separator: "\n").compactMap { line -> (String, String)? in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = obj["id"] as? String, let file = obj["file"] as? String else { return nil }
            return (id, file)
        }
        var failures = 0
        for (i, (id, file)) in items.enumerated() {
            let out = URL(fileURLWithPath: outDir).appendingPathComponent("\(id).json")
            if FileManager.default.fileExists(atPath: out.path) { continue }   // resumable
            let log = await replay(audio: URL(fileURLWithPath: audioDir).appendingPathComponent(file), options: options)
            if log.error != nil { failures += 1 }
            do { try write(log, to: out) } catch { fail("writing \(out.path): \(error)") }
            print("SYSTEM-REPLAY [\(i + 1)/\(items.count)] \(id) \(summary(log))")
        }
        exit(failures == 0 ? 0 : 1)
    default:
        fail("usage: system-replay run|batch ... (see the top of main.swift)")
    }
}

await main()

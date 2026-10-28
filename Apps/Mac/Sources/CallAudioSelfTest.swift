import AVFoundation
import CaptionCore
import Foundation

/// Call captions checked from inside the app (#172), because macOS grants "System Audio Recording" and the microphone
/// to an app, not to a test runner. Launched with `-CallAudioSelfTest <mode>`, the app makes speech with `say`, plays
/// it with `afplay` (a separate process, out of the speakers), runs the real caption engine on the chosen source,
/// prints what it heard and quits: exit 0 when the sentence came through exactly once, 1 when it didn't.
///   process  tap the player only            all      tap every sound but our own
///   mic      the microphone, plain          mic-vp   the microphone with echo cancellation
///   both     microphone (echo cancelled) and every sound, mixed: what the app uses by default
/// The mic modes measure how much of the speakers' sound the microphone picks up (the echo).
enum CallAudioSelfTest {
    static let sentence = "She sells seashells by the seashore. The harbor is calm this morning."

    static var isRequested: Bool { UserDefaults.standard.string(forKey: "CallAudioSelfTest") != nil }

    static func runIfRequested() {
        if UserDefaults.standard.bool(forKey: "MarvinRouteWatch") { Task.detached { await watchRoute() } ; return }
        guard let mode = UserDefaults.standard.string(forKey: "CallAudioSelfTest") else { return }
        Task.detached {
            let ok: Bool
            do { ok = try await run(mode: mode) } catch { log("FAILED: \(error)"); ok = false }
            exit(ok ? 0 : 1)
        }
    }

    private static func log(_ line: String) { FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!) }

    /// The inputs inside a mix, metered one by one.
    nonisolated(unsafe) private static var parts: [(String, LevelMeter)] = []

    private static func source(for mode: String, player: pid_t) throws -> AudioSource {
        switch mode {
        case "process": return ProcessTapAudioSource(target: .processes([player]))
        case "all": return ProcessTapAudioSource(target: .allSystemAudio)
        case "mic": return MicAudioSource(micMode: .standard)
        case "mic-vp": return MicAudioSource(micMode: .voiceProcessing)
        case "both", "both-raw", "both-taponly":
            let mic = LevelMeter(mode == "both" ? RoomMicSource() : MicAudioSource(micMode: mode == "both-raw" ? .standard : .voiceProcessing))
            let tapSource = ProcessTapAudioSource(target: .allSystemAudio)
            tapSource.usesOutputDevice = mode == "both-raw"
            let tap = LevelMeter(tapSource)
            parts = [("mic", mic), ("tap", tap)]
            return MixedAudioSource([mic, tap])
        default: throw CallAudioError.appNotPlayingSound
        }
    }

    private static func run(mode: String) async throws -> Bool {
        guard let model = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") else {
            throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
        }
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("selftest-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: file) }
        try launch("/usr/bin/say", ["-v", "Samantha", "-o", file.path, "[[slnc 2000]] " + sentence]).waitUntilExit()

        let deferred = DeferredSource()
        let engine = TranscriptionEngine(diarizerModelURL: model, audioSource: deferred)
        try await engine.prepare { _ in }
        log("engine ready")

        let player = try launch("/usr/bin/afplay", [file.path])
        defer { if player.isRunning { player.terminate() } }
        if mode == "process" {
            for _ in 0..<40 where ProcessTapAudioSource.processObject(for: player.processIdentifier) == nil {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        let source = try source(for: mode, player: player.processIdentifier)
        let level = LevelMeter(source)
        deferred.inner = level

        let updates = try await engine.start()
        log("listening (\(mode))")
        let collector = Task { () -> [(Int?, String)] in
            var finals: [(Int?, String)] = [], volatile: (Int?, String)?
            do {
                for try await u in updates {
                    if u.isFinal { finals.append((u.speaker, u.text)); volatile = nil } else { volatile = (u.speaker, u.text) }
                }
            } catch {}
            return finals + (volatile.map { [$0] } ?? [])
        }
        try await Task.sleep(nanoseconds: 12_000_000_000)
        await engine.stop()
        let lines = await collector.value
        let text = lines.map(\.1).joined(separator: " ").lowercased()
        log("frames: \(level.frames), peak: \(String(format: "%.3f", level.peak)), rms: \(String(format: "%.4f", level.rms))")
        for (name, m) in parts {
            log("  \(name): frames \(m.frames), peak \(String(format: "%.3f", m.peak)), opened: \(m.openError.map { "no (\($0))" } ?? "yes")")
        }
        for (speaker, words) in lines { log("  [\(speaker.map { "Speaker \($0 + 1)" } ?? "?")] \(words)") }
        let times = text.components(separatedBy: "harbor").count - 1
        log("'harbor' heard \(times) time(s)")
        return times == 1 && (text.contains("seashells") || text.contains("sea shells"))
    }

    /// `-MarvinRouteWatch YES`: runs the room mic until quit and prints every route change, the mic it chose and how loud
    /// it is, so headphones can be connected and disconnected while it runs. Never touches the call.
    private static func watchRoute() async {
        let room = RoomMicSource()
        let meter = LevelMeter(room)
        do {
            _ = try meter.open()
            try meter.start { _ in }
        } catch { log("FAILED: \(error)"); exit(1) }
        var last = ""
        for second in 0..<3600 {
            let route = RoomMicSource.describeRoute()
            if route != last { log("t=\(second)s \(route)"); last = route }
            if second % 5 == 4 { log("t=\(second + 1)s mic now \(room.choice), peak so far \(String(format: "%.3f", meter.peak)), frames \(meter.frames), choices \(room.history)") }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        log("choices made: \(room.history)")
        meter.stop()
        exit(0)
    }

    @discardableResult
    private static func launch(_ path: String, _ args: [String]) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        return p
    }
}

/// Hands the engine its source after the engine has loaded, so the clip isn't over before the source opens.
private final class DeferredSource: AudioSource {
    var inner: AudioSource?
    func open() throws -> AVAudioFormat {
        guard let inner else { throw CallAudioError.appNotPlayingSound }
        return try inner.open()
    }
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws { try inner?.start(onBuffer: onBuffer) }
    func stop() { inner?.stop() }
}

/// Passes buffers through and keeps loudness numbers: how much sound a source really delivered.
private final class LevelMeter: AudioSource {
    private let inner: AudioSource
    private let lock = NSLock()
    private var sumSquares = 0.0, count = 0, maxSample: Float = 0
    init(_ inner: AudioSource) { self.inner = inner }
    var frames: Int { lock.withLock { count } }
    var peak: Float { lock.withLock { maxSample } }
    var rms: Double { lock.withLock { count > 0 ? (sumSquares / Double(count)).squareRoot() : 0 } }
    private(set) var openError: Error?
    func open() throws -> AVAudioFormat {
        do { return try inner.open() } catch { openError = error; throw error }
    }
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        try inner.start { [weak self] buffer in
            if let self, let ch = buffer.floatChannelData {
                let n = Int(buffer.frameLength)
                var s = 0.0, m: Float = 0
                for i in 0..<n { let v = ch[0][i]; s += Double(v * v); m = max(m, abs(v)) }
                self.lock.withLock { self.sumSquares += s; self.count += n; self.maxSample = max(self.maxSample, m) }
            }
            onBuffer(buffer)
        }
    }
    func stop() { inner.stop() }
}

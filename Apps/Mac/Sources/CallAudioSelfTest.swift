import AVFoundation
import CaptionCore
import Foundation

/// Call captions checked from inside the app (#172), because macOS grants "System Audio Recording" to an app, not to a
/// test runner. Launched with `-CallAudioSelfTest process|all`, the app makes speech with `say`, plays it with `afplay`
/// (a separate process), taps that process (`process`) or every sound but its own (`all`), runs the real caption engine
/// on it, prints what it heard and quits: exit 0 when the words came through, 1 when they didn't.
enum CallAudioSelfTest {
    static let sentence = "She sells seashells by the seashore. The harbor is calm this morning."

    static var isRequested: Bool { UserDefaults.standard.string(forKey: "CallAudioSelfTest") != nil }

    static func runIfRequested() {
        guard let mode = UserDefaults.standard.string(forKey: "CallAudioSelfTest") else { return }
        Task.detached {
            let ok: Bool
            do { ok = try await run(mode: mode) } catch { log("FAILED: \(error)"); ok = false }
            exit(ok ? 0 : 1)
        }
    }

    private static func log(_ line: String) { FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!) }

    private static func run(mode: String) async throws -> Bool {
        guard let model = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") else {
            throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
        }
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("selftest-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: file) }
        try launch("/usr/bin/say", ["-v", "Samantha", "-o", file.path, "[[slnc 2000]] " + sentence]).waitUntilExit()

        let source = DeferredSource()
        let engine = TranscriptionEngine(diarizerModelURL: model, audioSource: source)
        try await engine.prepare { _ in }
        log("engine ready")

        let player = try launch("/usr/bin/afplay", [file.path])
        defer { if player.isRunning { player.terminate() } }
        let tap: ProcessTapAudioSource
        if mode == "all" {
            tap = ProcessTapAudioSource(target: .allSystemAudio)
        } else {
            for _ in 0..<40 where ProcessTapAudioSource.processObject(for: player.processIdentifier) == nil {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            tap = ProcessTapAudioSource(target: .processes([player.processIdentifier]))
        }
        source.inner = tap

        let updates = try await engine.start()
        log("tap started (\(mode))")
        let collector = Task { () -> String in
            var finals: [String] = [], volatile = ""
            do {
                for try await u in updates {
                    if u.isFinal { finals.append(u.text); volatile = "" } else { volatile = u.text }
                }
            } catch {}
            return (finals + [volatile]).joined(separator: " ")
        }
        try await Task.sleep(nanoseconds: 12_000_000_000)
        let frames = tap.framesDelivered, peak = tap.peakLevel
        let t0 = Date()
        await engine.stop()
        let text = await collector.value
        log("frames delivered: \(frames), peak level: \(peak), stop took \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
        log("heard: \(text)")
        let lower = text.lowercased()
        return lower.contains("harbor") && (lower.contains("seashells") || lower.contains("sea shells"))
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

/// Hands the engine its source after the engine has loaded, so the clip isn't over before the tap opens.
private final class DeferredSource: AudioSource {
    var inner: AudioSource?
    func open() throws -> AVAudioFormat {
        guard let inner else { throw CallAudioError.appNotPlayingSound }
        return try inner.open()
    }
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws { try inner?.start(onBuffer: onBuffer) }
    func stop() { inner?.stop() }
}

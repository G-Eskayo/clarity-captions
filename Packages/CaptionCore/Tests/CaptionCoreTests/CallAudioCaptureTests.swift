#if os(macOS)
import AVFoundation
import CoreAudio
import XCTest
@testable import CaptionCore

/// Call captions on the Mac (#172): another app's sound, tapped with a Core Audio process tap, goes through the real
/// caption engine. No fakes: `say` makes the speech, `afplay` plays it as a separate process, the tap captures that
/// process, and the real SpeechAnalyzer engine must write the words.
///
/// Opt-in because it plays sound and needs the "System Audio Recording" permission for whatever runs the tests:
///   CAPTION_CALL_AUDIO=1 CAPTION_DIARIZER_MODEL=<path to Sortformer_v2.1.mlmodelc> swift test --filter CallAudioCapture
final class CallAudioCaptureTests: XCTestCase {
    private static let sentence = "She sells seashells by the seashore. The harbor is calm this morning."

    private func speechFile() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("call-audio-\(UUID().uuidString).aiff")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        // Leading silence: the player is already an audio client when the tap opens, and no word is lost.
        p.arguments = ["-v", "Samantha", "-o", url.path, "[[slnc 3000]] " + Self.sentence]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "say failed")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Starts a separate process (so the tap has someone else to listen to) and ends it when the test does.
    private func launch(_ path: String, _ args: [String]) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        addTeardownBlock { if p.isRunning { p.terminate() } }
        return p
    }

    /// Core Audio lists a process only once it has opened audio; tapping before that has nothing to tap.
    private func waitUntilPlaying(_ pid: pid_t) async throws {
        for _ in 0..<40 where ProcessTapAudioSource.processObject(for: pid) == nil { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNotNil(ProcessTapAudioSource.processObject(for: pid), "process \(pid) never opened audio")
    }

    private func diarizerModel() throws -> URL {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["CAPTION_DIARIZER_MODEL"], "set CAPTION_DIARIZER_MODEL")
        return URL(fileURLWithPath: path)
    }

    private func optIn() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_CALL_AUDIO"] == "1", "opt-in: plays sound")
    }

    /// Loads the real engine first (as the app does during launch), then calls `play` to start the sound and get the
    /// source to tap, captions for `seconds`, stops, and returns everything written.
    private func transcript(seconds: Double, play: () async throws -> AudioSource) async throws -> String {
        let source = DeferredSource()
        let engine = TranscriptionEngine(diarizerModelURL: try diarizerModel(), audioSource: source)
        try await engine.prepare { _ in }
        source.inner = try await play()
        let updates = try await engine.start()
        let collector = Task { () -> String in
            var finals: [String] = [], volatile = ""
            do {
                for try await u in updates {
                    if u.isFinal { finals.append(u.text); volatile = "" } else { volatile = u.text }
                }
            } catch {}
            return (finals + [volatile]).joined(separator: " ")
        }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
        await engine.stop()
        return await collector.value.lowercased()
    }

    func testTappedAppSpeechIsCaptionedByTheRealEngine() async throws {
        try optIn()
        let file = try speechFile()
        // A quiet second first, so the tap is running before the first word.
        var tap: ProcessTapAudioSource!
        let text = try await transcript(seconds: 10) {
            let player = try launch("/usr/bin/afplay", [file.path])
            try await waitUntilPlaying(player.processIdentifier)
            tap = ProcessTapAudioSource(target: .processes([player.processIdentifier]))
            return tap
        }
        let source = tap!
        XCTAssertTrue(text.contains("seashells") || text.contains("sea shells"), "heard: \(text)")
        XCTAssertTrue(text.contains("harbor"), "heard: \(text)")
        XCTAssertGreaterThan(source.framesDelivered, 0, "the tap never ran")
        XCTAssertGreaterThan(source.peakLevel, 0, "the tap delivered only silence: is System Audio Recording allowed?")
    }

    func testEverythingButOurselvesHearsAnotherApp() async throws {
        try optIn()
        let file = try speechFile()
        let text = try await transcript(seconds: 10) {
            let player = try launch("/usr/bin/afplay", [file.path])
            try await waitUntilPlaying(player.processIdentifier)
            return ProcessTapAudioSource(target: .allSystemAudio)
        }
        XCTAssertTrue(text.contains("harbor"), "heard: \(text)")
    }

    /// The tap must be about the chosen app only: a FaceTime tap must not caption music playing in another app.
    func testTapOnAnotherProcessDoesNotHearThePlayer() async throws {
        try optIn()
        let file = try speechFile()
        // A second player of pure silence: a real audio client that must not hear the first.
        let quiet = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quiet-\(UUID().uuidString).aiff")
        let q = Process(); q.executableURL = URL(fileURLWithPath: "/usr/bin/say"); q.arguments = ["-o", quiet.path, "[[slnc 15000]]"]
        try q.run(); q.waitUntilExit()
        addTeardownBlock { try? FileManager.default.removeItem(at: quiet) }
        let text = try await transcript(seconds: 10) {
            let bystander = try launch("/usr/bin/afplay", [quiet.path])
            try await waitUntilPlaying(bystander.processIdentifier)
            let player = try launch("/usr/bin/afplay", [file.path])
            try await waitUntilPlaying(player.processIdentifier)
            return ProcessTapAudioSource(target: .processes([bystander.processIdentifier]))
        }
        XCTAssertFalse(text.contains("harbor"), "a tap on another process heard the player: \(text)")
        XCTAssertFalse(text.contains("seashells"), "a tap on another process heard the player: \(text)")
    }
}

/// Lets a test hand the engine its source after the engine has loaded, so the clip isn't over before the tap opens.
private final class DeferredSource: AudioSource {
    var inner: AudioSource?
    func open() throws -> AVAudioFormat { try XCTUnwrap(inner).open() }
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws { try XCTUnwrap(inner).start(onBuffer: onBuffer) }
    func stop() { inner?.stop() }
}

/// Rules that need no sound and no permission, so they always run.
final class ProcessTapAudioSourceRulesTests: XCTestCase {
    func testNoAppNamedIsAPlainError() {
        XCTAssertThrowsError(try ProcessTapAudioSource(target: .apps(bundleIDs: [])).open()) { error in
            XCTAssertEqual(error as? CallAudioError, .appNotPlayingSound)
        }
    }

    func testAProcessThatPlaysNoSoundIsAPlainError() throws {
        let silent = Process(); silent.executableURL = URL(fileURLWithPath: "/bin/sleep"); silent.arguments = ["5"]
        try silent.run()
        defer { silent.terminate() }
        XCTAssertThrowsError(try ProcessTapAudioSource(target: .processes([silent.processIdentifier])).open()) { error in
            XCTAssertEqual(error as? CallAudioError, .appNotPlayingSound)
        }
    }

    func testStopBeforeStartAndTwiceIsSafe() {
        let source = ProcessTapAudioSource(target: .allSystemAudio)
        source.stop()
        source.stop()
    }

    func testStopRemovesTheAggregateDevice() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTION_CALL_AUDIO"] == "1", "opt-in: opens a tap")
        let before = Set(ProcessTapAudioSource.deviceUIDs())
        let source = ProcessTapAudioSource(target: .allSystemAudio)
        _ = try source.open()
        try source.start { _ in }
        let made = Set(ProcessTapAudioSource.deviceUIDs()).subtracting(before)
        XCTAssertGreaterThan(made.count, 0, "no aggregate device made")
        let t0 = Date()
        source.stop()
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.5, "stop must return at once even when the tap never ran")
        XCTAssertTrue(source.waitForTeardown(timeout: 180), "teardown never finished")
        for _ in 0..<50 where !made.isDisjoint(with: ProcessTapAudioSource.deviceUIDs()) { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertTrue(made.isDisjoint(with: ProcessTapAudioSource.deviceUIDs()), "stop left a device behind")
    }
}
#endif

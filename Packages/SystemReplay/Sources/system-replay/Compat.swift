import CaptionCore
import Foundation
import SystemReplayKit

// The few CaptionCore calls that differ between the builds this harness replays. 1.0 (5) had Apple's engine only,
// with the microphone wired straight into the engine: no CaptionEnginePlan, no AudioSource, no engine names or
// fallbacks. scripts/system-replay/at-build.sh builds with -DCAPTIONCORE_1_0 for it; every later build (9 on) takes
// the default branch.

/// The engine for one session, made as the app makes it, plus the plan it was made from.
struct MadeEngine {
    let engine: TranscriptionEngine
    let plan: SessionLog.Plan
    let source: ReplayAudioSource?
}

#if CAPTIONCORE_1_0
let buildFlavor = "1.0 (Apple's engine only)"

func makeEngine(audio: URL, options o: Options, path: String) -> MadeEngine {
    // 1.0's app: TranscriptionEngine(micMode:, diarizerModelURL:, contextualStrings: her vocabulary list). The list is
    // empty here (recorded): the demo phone's list is a confounder to ask about.
    let plan = SessionLog.Plan(engine: "apple", reason: nil, locale: o.locale.identifier, choice: "apple (1.0 has no other)",
                               availableMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                               memorySource: "not used by 1.0", modelPresent: false)
    let engine = TranscriptionEngine(locale: o.locale, micMode: .standard, diarizerModelURL: o.diarizer, contextualStrings: [])
    return MadeEngine(engine: engine, plan: plan, source: nil)
}

func engineOf(_ u: CaptionUpdate) -> (name: String, fallback: String?) { ("apple-speechanalyzer", nil) }

func apply(_ u: CaptionUpdate, to stream: inout CaptionStream) {
    var range: ClosedRange<Double>?
    if let a = u.startSeconds, let b = u.endSeconds, a <= b { range = a...b }
    stream.apply(text: u.text, isFinal: u.isFinal, speaker: u.speaker, range: range)
}

func captureEngineState(_ log: inout SessionLog, from engine: TranscriptionEngine, fallbacks: [SessionLog.Fallback]) {
    log.finalEngine = "apple-speechanalyzer"
}

func watchFallbacks(_ engine: TranscriptionEngine, into box: Box<[SessionLog.Fallback]>, clock: @escaping () -> Double) {}

#else
let buildFlavor = "1.1 (CaptionEnginePlan, AudioSource)"

func makeEngine(audio: URL, options o: Options, path: String) -> MadeEngine {
    // The plan the app makes. On the Mac there is no per-app memory limit (os_proc_available_memory is iOS only), so
    // physical memory stands in, as the simulator build does; the device run records the real figure. The fallback
    // history is empty: one replay must never pin the next to Apple.
    let memory = ProcessInfo.processInfo.physicalMemory
    let modelPresent = o.parakeet.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    let plan = CaptionEnginePlan.make(captionLanguage: o.locale, choice: CaptionEngineChoice(rawValue: o.choice) ?? .parakeet, now: Date(), recentFallbacks: [],
                                      availableMemory: memory, modelPresent: modelPresent)
    let recognizer: SpeechRecognizerSetup
    if plan.selection.engine == .parakeet, let url = o.parakeet { recognizer = .parakeet(modelURL: url) } else { recognizer = .apple }
    let source = path == "source" ? ReplayAudioSource(url: audio, rate: o.rate, framesPerBuffer: o.frames, tailSeconds: o.tail) : nil
    let engine = TranscriptionEngine(locale: plan.locale, micMode: .standard, diarizerModelURL: o.diarizer,
                                     recognizer: recognizer, startReason: plan.selection.reason, audioSource: source)
    return MadeEngine(engine: engine,
                      plan: .init(engine: plan.selection.engine.rawValue, reason: plan.selection.reason?.rawValue,
                                  locale: plan.locale.identifier, choice: o.choice, availableMemoryBytes: memory,
                                  memorySource: "macOS physicalMemory (no per-app limit on the Mac)", modelPresent: modelPresent),
                      source: source)
}

func engineOf(_ u: CaptionUpdate) -> (name: String, fallback: String?) { (u.engine, u.engineFallback?.rawValue) }

func apply(_ u: CaptionUpdate, to stream: inout CaptionStream) {
    // CaptionModel.onUpdate's own call.
    var range: ClosedRange<Double>?
    if let a = u.startSeconds, let b = u.endSeconds, a <= b { range = a...b }
    stream.apply(text: u.text, isFinal: u.isFinal, speaker: u.speaker, range: range, lane: u.lane)
}

func captureEngineState(_ log: inout SessionLog, from engine: TranscriptionEngine, fallbacks: [SessionLog.Fallback]) {
    log.fallbacks = fallbacks
    log.finalEngine = engine.engineName
    log.finalFallbackReason = engine.fallbackReason?.rawValue
    log.fallbackDetail = engine.fallbackDetail
    if let d = engine.decodeSeconds { log.decodeP50 = d.p50; log.decodeP95 = d.p95 }
}

func watchFallbacks(_ engine: TranscriptionEngine, into box: Box<[SessionLog.Fallback]>, clock: @escaping () -> Double) {
    engine.onFallback = { reason in box.mutate { $0.append(.init(reason: reason.rawValue, at: clock())) } }
}
#endif

/// The engine's own file replay (`startReplaying(fileURL:)`, in every build) behind the controller: the same
/// converters, recognizer, diarizer and lag clock as the microphone, fed from the file at real-time pace.
final class ReplayingEngine: CaptioningEngine {
    let inner: TranscriptionEngine
    let url: URL
    init(_ inner: TranscriptionEngine, url: URL) { self.inner = inner; self.url = url }
    var startupReport: String { inner.startupReport }
    func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error> { try await inner.startReplaying(fileURL: url) }
    func soundLabelsStream() -> AsyncStream<SoundLabelKind> { inner.soundLabelsStream() }
    func audioLevelStream() -> AsyncStream<Double> { inner.audioLevelStream() }
    func stop() async { await inner.stop() }
    func prepare(onStep: @escaping @Sendable (Int) -> Void) async throws { try await inner.prepare(onStep: onStep) }
}

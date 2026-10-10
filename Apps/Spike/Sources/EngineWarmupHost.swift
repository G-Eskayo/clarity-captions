import CaptionCore
import Foundation
import UIKit

/// The app's one EngineWarmup (#119): the launch animation covers loading the captioning engine, so Start is instant.
/// The owner, on #117: "The loading screen at the beginning is supposed to cover the getting-ready."
///
/// - Loading starts once first run is done (the microphone allowed, the speech model installed), and again after
///   each conversation pauses, so the next Start is instant too.
/// - An engine nobody took is freed when Seal goes to the background or iOS warns about memory, and loaded again
///   on the way back (Decision "idlerelease" on #119).
@MainActor
final class EngineWarmupHost: ObservableObject {
    static let shared = EngineWarmupHost()

    @Published private(set) var state: EngineWarmup.State = .idle
    /// Non-optional on purpose: on an optional, `.take()` would be Optional's own `take()` and empty the property.
    private let warmup: EngineWarmup
    /// The mic mode the next engine is made with (a box, so the factory can read it without capturing self).
    private let requested: Requested
    private final class Requested { var micMode: MicMode = .standard }
    private var allowed = false
    /// The mic mode the loaded engine was made for; a session with another mode makes its own engine.
    private var loadedMicMode: MicMode?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let box = Requested()
        requested = box
        warmup = EngineWarmup(make: { try Self.makeEngine(micMode: box.micMode) })
        warmup.onChange = { [weak self] in self?.state = $0 }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.release() }
            },
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.release() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.prepareIfAllowed() }
            },
        ]
    }

    /// The real engine, made the same way CaptionModel makes one.
    static func makeEngine(micMode: MicMode) throws -> CaptioningEngine {
        #if DEBUG
        if let seconds = demoLoadSeconds { return DemoLoadingEngine(seconds: seconds) }
        #endif
        guard let url = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") else {
            throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
        }
        let vocabulary = VocabularyList(rawText: VocabularyStore().loadRawText()).entries
        return TranscriptionEngine(micMode: micMode, diarizerModelURL: url, contextualStrings: vocabulary)
    }

    /// First run is done: from now on the engine may load ahead of Start.
    func allow() {
        allowed = true
        prepareIfAllowed()
    }

    /// Loads an engine for `micMode` unless one is loaded or loading.
    func prepareIfAllowed(micMode: MicMode = .standard) {
        guard allowed, UIApplication.shared.applicationState != .background else { return }
        #if DEBUG
        // Demo screens (screenshots, recordings) never load the real engine, except the launch demo that shows it.
        if DemoMode.isOn && Self.demoLoadSeconds == nil { return }
        #endif
        if state == .idle || state == .failed {
            requested.micMode = micMode
            loadedMicMode = micMode
        }
        warmup.prepare()
    }

    /// The loaded (or loading) engine for a session, or nil if none matches; the session then makes its own.
    func take(micMode: MicMode) -> CaptioningEngine? {
        guard loadedMicMode == micMode, let engine = warmup.take() else { return nil }
        loadedMicMode = nil
        return engine
    }

    func release() async {
        await warmup.release()
        loadedMicMode = nil
    }

    #if DEBUG
    /// `-ClarityDemoEngineLoad <seconds>`: a pretend engine whose three loading steps take this long in all, so the
    /// launch's bar can be recorded following a load that outlasts the dance (simctl has no speech engine).
    static var demoLoadSeconds: Double? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ClarityDemoEngineLoad"), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }

    private final class DemoLoadingEngine: CaptioningEngine, @unchecked Sendable {
        let seconds: Double
        var startupReport = "demo engine"
        init(seconds: Double) { self.seconds = seconds }
        func prepare(onStep: @escaping @Sendable (Int) -> Void) async throws {
            for step in 1...EngineWarmup.steps {
                try await Task.sleep(for: .seconds(seconds / Double(EngineWarmup.steps)))
                onStep(step)
            }
        }
        func start() async throws -> AsyncThrowingStream<CaptionUpdate, Error> { AsyncThrowingStream { _ in } }
        func soundLabelsStream() -> AsyncStream<SoundLabelKind> { AsyncStream { $0.finish() } }
        func audioLevelStream() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
        func stop() async {}
    }
    #endif
}

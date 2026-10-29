import CaptionCore
import Foundation
import os

/// The one place the iPhone app makes a captioning engine (ADR 0025). Parakeet unless the developer flag says Apple,
/// the model is missing, memory is short, or it fell back twice in the last day (EngineFallbackPolicy).
enum CaptionEngineFactory {
    static var speakerModelURL: URL? { Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") }
    static var parakeetModelURL: URL? { Bundle.main.url(forResource: "ParakeetUltra", withExtension: nil) }
    /// The caption language she chose (#37). Parakeet is English only, so another language runs Apple's engine in it.
    static var captionLocale: Locale { CaptionLanguageCenter.engineLocale }
    /// Only an Xcode (debug) build has the developer panel, so only it honours the panel's engine pick (owner, PR #155).
    #if DEBUG
    static let developerBuild = true
    #else
    static let developerBuild = false
    #endif

    static func plan(now: Date = Date()) -> CaptionEnginePlan {
        CaptionEnginePlan.make(captionLanguage: captionLocale, choice: CaptionEngineChoice.stored(developerBuild: developerBuild),
                               now: now, recentFallbacks: EngineFallbackHistory().recent(now: now),
                               availableMemory: UInt64(os_proc_available_memory()), modelPresent: parakeetModelURL != nil)
    }

    static func selection(now: Date = Date()) -> EngineSelection { plan(now: now).selection }

    static func make(micMode: MicMode) throws -> TranscriptionEngine {
        guard let speakerModel = speakerModelURL else {
            throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
        }
        let plan = plan()
        let selection = plan.selection
        let recognizer: SpeechRecognizerSetup = selection.engine == .parakeet
            ? parakeetModelURL.map { .parakeet(modelURL: $0) } ?? .apple : .apple
        let engine = TranscriptionEngine(locale: plan.locale, micMode: micMode, diarizerModelURL: speakerModel,
                                         recognizer: recognizer, startReason: selection.reason)
        engine.onFallback = { _ in
            var history = EngineFallbackHistory()
            history.record(Date(), now: Date())
        }
        return engine
    }

    /// First run: Core ML compiles Parakeet for this phone once (35 s on a Mac), so it happens here and not behind
    /// the first Start. Skipped when this launch would not use Parakeet anyway.
    static func warmUpSpeechModel() async throws {
        guard selection().engine == .parakeet, let url = parakeetModelURL else { return }
        try await TranscriptionEngine.warmUp(parakeetModelURL: url)
    }
}

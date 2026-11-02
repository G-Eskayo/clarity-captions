import CaptionCore
import Foundation
import os

/// The one place the iPhone app makes a captioning engine (ADR 0025). Parakeet unless the developer flag says Apple,
/// the model is missing, memory is short, or it fell back twice in the last day (EngineFallbackPolicy).
enum CaptionEngineFactory {
    static var speakerModelURL: URL? { Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") }
    static var parakeetModelURL: URL? { Bundle.main.url(forResource: "ParakeetUltra", withExtension: nil) }
    /// The caption language she chose (#37). It picks the engine (#234): Parakeet where it won, Apple's engine elsewhere.
    static var captionLocale: Locale { CaptionLanguageCenter.engineLocale }
    /// Only an Xcode (debug) build has the developer panel, so only it honours the panel's engine pick (owner, PR #155).
    #if DEBUG
    static let developerBuild = true
    #else
    static let developerBuild = false
    #endif

    static func plan(now: Date = Date()) -> CaptionEnginePlan { plan(for: captionLocale, now: now) }

    static func plan(for language: Locale, now: Date = Date()) -> CaptionEnginePlan {
        CaptionEnginePlan.make(captionLanguage: language, choice: CaptionEngineChoice.stored(developerBuild: developerBuild),
                               now: now, recentFallbacks: EngineFallbackHistory().recent(now: now),
                               availableMemory: UInt64(os_proc_available_memory()), modelPresent: parakeetModelURL != nil)
    }

    static func selection(now: Date = Date()) -> EngineSelection { plan(now: now).selection }

    /// One-way captions in the caption language, or (#208, one half of the split picked) in `locale`. #245: the split
    /// passes `.mustBeOnDevice`; its languages are set up in Settings, and it never downloads.
    static func make(micMode: MicMode, locale: Locale? = nil, speechModel: SpeechModelPolicy = .downloadIfNeeded) throws -> TranscriptionEngine {
        guard let speakerModel = speakerModelURL else {
            throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
        }
        let plan = Self.plan(for: locale ?? captionLocale)
        let selection = plan.selection
        let recognizer: SpeechRecognizerSetup = selection.engine == .parakeet
            ? parakeetModelURL.map { .parakeet(modelURL: $0) } ?? .apple : .apple
        let engine = TranscriptionEngine(locale: plan.locale, micMode: micMode, diarizerModelURL: speakerModel,
                                         recognizer: recognizer, startReason: selection.reason, speechModel: speechModel)
        engine.onFallback = { _ in
            var history = EngineFallbackHistory()
            history.record(Date(), now: Date())
        }
        return engine
    }

    /// #60 face to face: one engine per half, each in its half's language, picked per language the same way as one-way
    /// captions (#234, CaptionEngineRouting: Parakeet where it won, Apple's engine for the rest). Since #208 each half's language is the one its list picked.
    /// No engine loaded ahead is used: it was made for one-way captions. #245: never downloads a speech model.
    static func makeFaceToFace(micMode: MicMode, ownerLocale: Locale, partnerLocale: Locale) throws -> TranscriptionEngine {
        guard let speakerModel = speakerModelURL else {
            throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
        }
        func recognizer(_ locale: Locale) -> SpeechRecognizerSetup {
            plan(for: locale).selection.engine == .parakeet ? parakeetModelURL.map { .parakeet(modelURL: $0) } ?? .apple : .apple
        }
        let setup = FaceToFaceSetup(ownerLocale: ownerLocale, ownerRecognizer: recognizer(ownerLocale),
                                    partnerLocale: partnerLocale, partnerRecognizer: recognizer(partnerLocale))
        return TranscriptionEngine(locale: partnerLocale, micMode: micMode, diarizerModelURL: speakerModel, faceToFace: setup,
                                   speechModel: .mustBeOnDevice)
    }

    /// First run: Core ML compiles Parakeet for this phone once (35 s on a Mac), so it happens here and not behind
    /// the first Start. Skipped when this launch would not use Parakeet anyway.
    static func warmUpSpeechModel() async throws {
        guard selection().engine == .parakeet, let url = parakeetModelURL else { return }
        try await TranscriptionEngine.warmUp(parakeetModelURL: url)
    }
}

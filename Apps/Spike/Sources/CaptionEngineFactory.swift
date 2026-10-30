import CaptionCore
import Foundation
import os

/// The one place the iPhone app makes a captioning engine (ADR 0025). Seal's own model for the caption language
/// (Parakeet for English, the zipformer for Hebrew, #220) unless the developer flag says Apple, the model is missing,
/// memory is short, or it fell back twice in the last day (EngineFallbackPolicy).
enum CaptionEngineFactory {
    static var speakerModelURL: URL? { Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") }
    static var parakeetModelURL: URL? { Bundle.main.url(forResource: "ParakeetUltra", withExtension: nil) }
    /// Hebrew's engine (#220): scripts/fetch-asr-models.sh with SEAL_ASR_MODEL=hebrew.
    static var hebrewModelURL: URL? { Bundle.main.url(forResource: "HebrewZipformer", withExtension: nil) }
    /// Caption languages Seal brings its own engine for, so they're listed and need no download from Apple (#220).
    static var bundledLanguages: [Locale] { hebrewModelURL != nil ? [Locale(identifier: "he-IL")] : [] }
    static func isBundled(_ locale: Locale) -> Bool {
        bundledLanguages.contains { CaptionLanguage.bcp47($0) == CaptionLanguage.bcp47(locale) }
    }
    static func modelURL(_ model: SealModel) -> URL? {
        switch model {
        case .parakeetUltra: parakeetModelURL
        case .hebrewZipformer: hebrewModelURL
        }
    }
    /// The caption language she chose (#37). English runs Parakeet, Hebrew the zipformer, the rest Apple's engine.
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
                               availableMemory: availableMemory,
                               modelPresent: SealModel.forLanguage(language).flatMap(modelURL) != nil)
    }

    /// The recognizer a plan asks for, Apple's if its model isn't in the app.
    static func recognizer(for plan: CaptionEnginePlan) -> SpeechRecognizerSetup {
        switch plan.sealModel {
        case .parakeetUltra?: parakeetModelURL.map { .parakeet(modelURL: $0) } ?? .apple
        case .hebrewZipformer?: hebrewModelURL.map { .zipformer(modelURL: $0) } ?? .apple
        case nil: .apple
        }
    }

    /// What this app may still allocate. The simulator has no per-app limit and reports 0, which read as "memory is
    /// short" and kept every simulator run on Apple's engine; there it is the Mac's memory.
    static var availableMemory: UInt64 {
        let available = UInt64(os_proc_available_memory())
        #if targetEnvironment(simulator)
        if available == 0 { return ProcessInfo.processInfo.physicalMemory }
        #endif
        return available
    }

    static func selection(now: Date = Date()) -> EngineSelection { plan(now: now).selection }

    /// One-way captions in the caption language, or (#208, one half of the split picked) in `locale`.
    static func make(micMode: MicMode, locale: Locale? = nil) throws -> TranscriptionEngine {
        guard let speakerModel = speakerModelURL else {
            throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
        }
        let plan = Self.plan(for: locale ?? captionLocale)
        let selection = plan.selection
        let recognizer = Self.recognizer(for: plan)
        var source: AudioSource?
        #if DEBUG
        source = DemoMode.audioFile.map { FileAudioSource(url: $0) }
        #endif
        let engine = TranscriptionEngine(locale: plan.locale, micMode: micMode, diarizerModelURL: speakerModel,
                                         recognizer: recognizer, startReason: selection.reason, audioSource: source)
        engine.onFallback = { _ in
            var history = EngineFallbackHistory()
            history.record(Date(), now: Date())
        }
        return engine
    }

    /// #60 face to face: one engine per half, each in its half's language (ADR 0025 picks the recognizer per language:
    /// Parakeet for English, the zipformer for Hebrew, Apple's engine for the rest). Since #208 each half's language is the one its list picked.
    /// No engine loaded ahead is used: it was made for one-way captions.
    static func makeFaceToFace(micMode: MicMode, ownerLocale: Locale, partnerLocale: Locale) throws -> TranscriptionEngine {
        guard let speakerModel = speakerModelURL else {
            throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
        }
        func recognizer(_ locale: Locale) -> SpeechRecognizerSetup { Self.recognizer(for: plan(for: locale)) }
        let setup = FaceToFaceSetup(ownerLocale: ownerLocale, ownerRecognizer: recognizer(ownerLocale),
                                    partnerLocale: partnerLocale, partnerRecognizer: recognizer(partnerLocale))
        return TranscriptionEngine(locale: partnerLocale, micMode: micMode, diarizerModelURL: speakerModel, faceToFace: setup)
    }

    /// First run: Core ML compiles Parakeet for this phone once (35 s on a Mac), so it happens here and not behind
    /// the first Start. Skipped when this launch would not use Parakeet anyway.
    static func warmUpSpeechModel() async throws {
        guard plan().sealModel == .parakeetUltra, let url = parakeetModelURL else { return }
        try await TranscriptionEngine.warmUp(parakeetModelURL: url)
    }
}

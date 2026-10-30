import CaptionCore
import Foundation
import Speech

/// The caption language (#37), shared by first run, Settings, the language list and the engine. Choosing a language
/// that isn't on the device downloads it with real progress; captions keep the old language until it's there.
@MainActor
final class CaptionLanguageCenter: ObservableObject {
    static let shared = CaptionLanguageCenter()

    @Published private(set) var change: CaptionLanguageSwitch
    /// Nothing picked yet: captions follow the device's language.
    @Published private(set) var followsDevice: Bool
    /// First run asks (#37): the device's language doesn't settle it and she hasn't picked one.
    @Published private(set) var needsChoice = false
    /// The engine's languages, read on this device; empty until the first `refresh()`.
    @Published private(set) var supported: [Locale] = []

    var current: Locale { change.current }

    /// What the engine is made with, readable from any thread (engine factories aren't on the main actor).
    nonisolated static var engineLocale: Locale { box.value }
    private nonisolated static let box = LocaleBox()

    private let store: CaptionLanguageStore
    private let preferred: [String]

    init(store: CaptionLanguageStore = CaptionLanguageStore(), preferred: [String] = Locale.preferredLanguages) {
        self.store = store
        self.preferred = preferred
        var saved = store.captionLanguage
        #if DEBUG
        if let id = DemoMode.language { saved = Locale(identifier: id) }
        #endif
        let start = saved ?? Locale(identifier: Locale(identifier: preferred.first ?? "en-US").identifier(.bcp47))
        change = CaptionLanguageSwitch(current: start)
        followsDevice = saved == nil
        Self.box.set(start)
    }

    /// Reads the engine's languages and settles the caption language. Called at launch and by first run.
    func refresh() async {
        let list = CaptionLanguage.adding(CaptionEngineFactory.bundledLanguages, to: await SpeechTranscriber.supportedLocales)
        supported = list
        switch CaptionLanguage.resolve(saved: followsDevice ? nil : current, preferred: preferred, supported: list) {
        case .use(let locale):
            needsChoice = false
            if CaptionLanguage.bcp47(locale) != CaptionLanguage.bcp47(current) { set(locale, chosen: !followsDevice) }
        case .ask:
            needsChoice = followsDevice
        }
        #if DEBUG
        if DemoMode.asksLanguage && followsDevice { needsChoice = true }
        #endif
    }

    /// Settings, the language list or first run picked a language.
    func choose(_ locale: Locale) async {
        let installed = CaptionEngineFactory.isBundled(locale) ? true : await SpeechModelInstaller.isInstalled(locale: locale)
        let before = current
        guard let download = change.choose(locale, installed: installed) else {
            if CaptionLanguage.bcp47(current) != CaptionLanguage.bcp47(before) || followsDevice { set(current, chosen: true) }
            return
        }
        let outcome = await SpeechDownload.language(download).run { p in
            Task { @MainActor in self.change.progress(p, for: download) }
        }
        change.finished(outcome, for: download)
        if CaptionLanguage.bcp47(current) == CaptionLanguage.bcp47(download) { set(current, chosen: true) }
    }

    /// First run's pick (#37): saved now, downloaded by first run's own download screen next.
    func pick(_ locale: Locale) {
        change = CaptionLanguageSwitch(current: locale)
        set(locale, chosen: true)
    }

    private func set(_ locale: Locale, chosen: Bool) {
        if chosen {
            store.captionLanguage = locale
            followsDevice = false
            needsChoice = false
        }
        Self.box.set(locale)
        // Translation starts from the caption language (#53): its session follows.
        TranslationCenter.shared.captionLanguageChanged()
        // An engine loaded ahead of Start was made for the old language.
        Task { await EngineWarmupHost.shared.release(); EngineWarmupHost.shared.prepareIfAllowed() }
        objectWillChange.send()
    }

    private final class LocaleBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = Locale(identifier: "en-US")
        func set(_ l: Locale) { lock.withLock { stored = l } }
        var value: Locale { lock.withLock { stored } }
    }
}

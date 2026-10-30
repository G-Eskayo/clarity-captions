import AVFoundation
import CaptionCore
import CaptionUI
import Speech
import SwiftUI
import Translation
import UIKit

@MainActor
final class CaptionModel: ObservableObject {
    @Published var state: CaptionState = .idle
    @Published var stream = CaptionStream()
    @Published var lag: Double?
    @Published var diag = ""
    @Published var startup = ""
    @Published var micMode: MicMode = .standard
    /// Developer panel only (ADR 0025, no setting for users): which recognizer the next session uses.
    @Published var engineChoice = CaptionEngineChoice.stored(developerBuild: CaptionEngineFactory.developerBuild) {
        didSet {
            UserDefaults.standard.set(engineChoice.rawValue, forKey: CaptionEngineChoice.key)
            var history = EngineFallbackHistory()
            history.clear()   // picked on purpose: an earlier fallback must not pin Apple during the phone checks
            Task { @MainActor in
                await EngineWarmupHost.shared.release()   // the warm engine was made for the other choice
                EngineWarmupHost.shared.prepareIfAllowed(micMode: micMode)
            }
        }
    }
    @Published var style: CaptionStyle = CaptionStyleStore().load() {
        didSet { CaptionStyleStore().save(style) }
    }
    @Published var latencyReport: String?
    @Published var speakerNames = SpeakerNames()
    @Published var activity: ListeningActivity?
    @Published var roomLevelDBFS: Double?
    /// Only used by the developer latency measurement below.
    private var task: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    private var controller: CaptionSessionController!
    var store: SavedConversationStoring?
    /// The conversation on screen, kept across pauses until [ New ]; saved only when she taps [ Save ] (#102).
    @Published var session = ConversationSession()
    /// The dim over a paused conversation, with [ Save ] and [ New ].
    @Published var veil = PauseVeil()
    /// [ ✔ ] shows briefly between [ Save ] and [ Saved ].
    @Published var showingSaveCheck = false
    /// [ New ] with unsaved changes asks first.
    /// [ New ]'s one question, asked in place of [ Save ] / [ New ] (#118, mock-up round2/03), never an alert.
    @Published var newQuestion = InPlaceQuestion<NewConversationQuestion>()
    /// The how-to-use tour on the real screen (#108). The real actions below report to it.
    @Published var tour = HowToUseTour()
    /// The tour's example line, shown when the room is quiet. Text only; never written to the saved list on its own.
    private(set) var tourExampleIDs: Set<Int> = []
    /// The on-screen conversation, written to the phone while she's in another app.
    private var currentStore: CurrentConversationStore?
    private var tracker = ListeningActivityTracker()
    /// ADR 0019: read by the controller on every tick, so a change in Settings applies mid-session.
    @Published var idleStop: IdleStopSetting = IdleStopStore().load() {
        didSet { IdleStopStore().save(idleStop) }
    }
    private let screenAwake = ScreenAwakeKeeper(apply: { UIApplication.shared.isIdleTimerDisabled = $0 })
    /// #60: the face-to-face split is open. From the Face to face button until Stop (only Stop leaves it, owner
    /// 2026-10-29; captions that stop on their own leave it paused, #208).
    @Published private(set) var faceToFace = false
    /// #208: each half's language, what captions run in, which half each settled line belongs to, paused or not.
    @Published private(set) var split = FaceToFaceSplit()
    /// The languages each half's list offers (`FaceToFaceLanguageList`), read when the split opens.
    @Published private(set) var faceToFaceDownloaded: [Locale] = []
    /// Each voice's language, and so its half, as the engine last reported it.
    @Published private(set) var speakerLanguages = SpeakerLanguages()
    /// The split's captions with each language as the engines know it, for the next engine made.
    private var splitEngine: FaceToFaceSplit.Captions?
    /// The split's starts, restarts and Stop, one after another: a quick second tap waits for the first.
    private(set) var splitTask: Task<Void, Never>?
    /// Debug demos only: the stand-in for the split's engines (`runSplitDemo`), and how many sessions it has played.
    var demoSplitPlayer: Task<Void, Never>?
    var demoSplitRound = 0
    /// Set while the split itself stops captions (a new pick, Stop), so that stop isn't taken for one on their own.
    private var splitStopping = false
    /// Beta testers' ratings and measurements (ADR 0023). Every call is a no-op in an App Store install.
    let beta = BetaFeedbackCenter.shared
    /// A cold launch brought back a conversation; the beta card may be due once StoreKit has answered.
    private var restoredOnColdLaunch = false

    init() {
        controller = CaptionSessionController(makeEngine: { [weak self] in
            guard let self else { throw CancellationError() }
            if self.faceToFace {
                switch self.splitEngine {
                case .one(_, let locale): return try CaptionEngineFactory.make(micMode: self.micMode, locale: locale)
                case .both(let owner, let partner):
                    return try CaptionEngineFactory.makeFaceToFace(micMode: self.micMode, ownerLocale: owner, partnerLocale: partner)
                case nil: throw CancellationError()
                }
            }
            // Loaded during the launch (or after the last pause), so Start is instant (#119).
            if let warm = EngineWarmupHost.shared.take(micMode: self.micMode) { return warm }
            return try CaptionEngineFactory.make(micMode: self.micMode)
        }, idleStopSetting: { [weak self] in self?.idleStop ?? .default })

        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let conversationsDir = appSupportURL.appendingPathComponent("SavedConversations")
            self.store = try? SavedConversationStore(directory: conversationsDir)
            Task { try? await self.store?.purgeExpired(now: Date()) }
            currentStore = try? CurrentConversationStore(directory: appSupportURL.appendingPathComponent("CurrentConversation"))
            // A cold launch: bring back a conversation she was in the middle of, paused (Decision "coldlaunch").
            if let restored = currentStore?.restoreOnColdLaunch(now: Date())?.restore() {
                stream = restored.stream
                speakerNames = restored.names
                session = restored.session
                restoredOnColdLaunch = true
            }
        }

        controller.onStateChange = { [weak self] in self?.handleCaptionStateChange($0) }
        controller.onStartup = { [weak self] in self?.startup = $0 }
        controller.onSoundLabel = { [weak self] in self?.stream.insertSoundLabel($0) }
        controller.onAudioLevel = { [weak self] level in
            guard let self else { return }
            self.roomLevelDBFS = level
            self.beta.audioLevel(self.session, level)
        }
        controller.onUpdate = { [weak self] u in
            guard let self else { return }
            var range: ClosedRange<Double>?
            if let a = u.startSeconds, let b = u.endSeconds, a <= b { range = a...b }
            self.stream.apply(text: u.text, isFinal: u.isFinal, speaker: u.speaker, range: range, lane: u.lane)
            if let languages = u.languages { self.speakerLanguages = languages }
            if let l = u.lagSeconds { self.lag = l }
            self.diag = u.diagnostics
            if !u.text.trimmingCharacters(in: .whitespaces).isEmpty {
                self.tracker.recordSpeech(at: Date())
                if u.isFinal { self.reportCaptionShown() }
            }
            // After the caption is on screen: measurements never sit in front of it (ADR 0015).
            self.beta.captionUpdate(self.session, u)
        }
    }

    /// Once StoreKit has answered: a conversation a cold launch brought back may be due its rating card.
    func betaResolved() {
        guard restoredOnColdLaunch else { return }
        restoredOnColdLaunch = false
        beta.restoredAfterColdLaunch(session, hasConversation: hasConversation)
    }

    func handleCaptionStateChange(_ newState: CaptionState) {
        state = newState
        screenAwake.update(state: newState)

        switch newState {
        case .preparing:
            // Resuming continues the same conversation, on a new line.
            session.captioningStarted(at: Date())
            veil.captioningStarted()
            stream.breakLine()
        case .listening:
            startActivityLoop()
            beta.captioningStarted(session)
        case .idle, .failed, .pausedQuiet:
            if faceToFace {
                // #208: the session's lines keep their halves. Captions that stopped on their own (the quiet stop, an
                // error) leave the split open, paused, with Start in her half; only Stop leaves it.
                endSplitSession()
                if !splitStopping { split.stoppedOnTheirOwn() }
            }
            // Pausing keeps the conversation on screen; nothing is saved until she taps [ Save ].
            stopActivityLoop()
            beta.captioningStopped(session, state: newState)
            // The next Start is instant too (#119); not in the split, whose engines are made for its languages.
            if !faceToFace { EngineWarmupHost.shared.prepareIfAllowed(micMode: micMode) }
        }
    }

    private func startActivityLoop() {
        activityTask?.cancel()
        activityTask = Task {
            while !Task.isCancelled && state == .listening {
                let newActivity = tracker.activity(now: Date(), roomLevelDBFS: roomLevelDBFS)
                if activity != newActivity {
                    activity = newActivity
                }
                controller.tick()
                beta.tick(session)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopActivityLoop() {
        activityTask?.cancel()
        activityTask = nil
        activity = nil
        roomLevelDBFS = nil
    }

    var hasConversation: Bool { ConversationSession.hasContent(stream.lines) }

    /// [ Save ]: writes the conversation to the saved list (kept 30 days). Saving again updates the same one.
    func save() {
        let before = session
        guard let conversation = session.makeSaved(lines: stream.lines, names: speakerNames, now: Date()) else { return }
        tour.did(.tappedSave)
        showingSaveCheck = true
        // Practising on the tour's example alone: the same [ ✔ ] → [ Saved ], but nothing goes in the saved list.
        let practice = TourExample.isOnlyExample(lines: stream.lines, exampleIDs: tourExampleIDs)
        Task {
            do {
                if !practice {
                    try await store?.save(conversation)
                    try await store?.purgeExpired(now: Date())
                }
            } catch {
                session = before
                diag = "Save failed: \(error)"
            }
            try? await Task.sleep(for: .seconds(FluidTiming.saveCheckHold))
            // [ ✔ ] eases into [ Saved ]; before the fluidity pass it snapped (owner, 2026-10-20).
            withAnimation(Fluid.saveMorph(UIAccessibility.isReduceMotionEnabled)) { showingSaveCheck = false }
            // The tour's "Saved." waits until [ ✔ ] → [ Saved ] has played out (#121).
            try? await Task.sleep(for: .seconds(FluidTiming.saveMoment - FluidTiming.saveCheckHold))
            tour.did(.saveMomentFinished)
        }
    }

    /// [ New ]: asks first if the conversation isn't saved as it stands.
    func requestNew() {
        let unsaved = session.hasUnsavedChanges(lines: stream.lines, names: speakerNames)
        if NewConversationQuestion.request(hasUnsavedChanges: unsaved, question: &newQuestion) == .startNow { startNew() }
    }

    /// [ New ], after its question if it asked. In a beta install the rating card may come first (ADR 0023).
    func startNew() {
        beta.newTapped(session, hasConversation: hasConversation) { [weak self] in self?.resetConversation() }
    }

    func rate(_ value: Int, note: String?) { beta.rate(session, value: value, note: note) }
    func skipRating() { beta.skip(session) }

    private func resetConversation() {
        stream = CaptionStream()
        speakerNames = SpeakerNames()
        session = ConversationSession()
        veil = PauseVeil()
        showingSaveCheck = false
        tourExampleIDs = []
        currentStore?.delete()
    }

    // MARK: the how-to-use tour (#108)

    /// The quiet-room example: two voices (round3/01, step 2), added the way the engine adds captions.
    func showTourExample() {
        let before = Set(stream.lines.map(\.id))
        for line in TourExample.lines { stream.apply(text: line.text, isFinal: true, speaker: line.speaker) }
        tourExampleIDs.formUnion(Set(stream.lines.map(\.id)).subtracting(before))
        reportCaptionShown()
    }

    /// Words appeared. Tour v3 doesn't move on by itself (#137); kept so the tour hears it.
    private func reportCaptionShown() {
        guard tour.step == .captions else { return }
        tour.did(.captionShown)
    }

    /// After the tour: a conversation that is nothing but the example goes, so it never lingers or gets kept.
    func tourEnded() {
        if TourExample.isOnlyExample(lines: stream.lines, exampleIDs: tourExampleIDs) { startNew() }
        tourExampleIDs = []
    }

    /// Leaving for another app: keep the conversation on the phone in case iOS closes Seal meanwhile. Back on
    /// screen it's in memory again, so the file goes.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if state == .listening { beta.leftApp(session) }
            if hasConversation {
                try? currentStore?.save(CurrentConversationSnapshot(lines: stream.lines, names: speakerNames, session: session, leftAt: Date()))
            } else {
                currentStore?.delete()
            }
        case .active:
            currentStore?.delete()
            beta.returned(session, hasConversation: hasConversation, isCaptioning: state == .listening || state == .preparing)
        default:
            break
        }
    }

    /// The app left or returned to the screen: the screen-awake flag follows, and time away isn't counted as quiet.
    func appActiveChanged(_ isActive: Bool) {
        screenAwake.update(appIsActive: isActive)
        if isActive { controller.noteResumed() }
    }

    func perform(_ action: PrimaryControl.Action) {
        switch action {
        case .start:
            tour.did(.tappedStart)
            beta.startPressed(session)
            controller.start()
        case .stop: tour.did(.tappedStop); controller.stop()
        case .none: break
        }
    }

    /// The Face to face button (#60): one-way captions stop and the split opens with each half's language list (#208).
    /// Nothing captions until a half picks; Stop is in her half from the start, and leaves.
    func startFaceToFace() {
        guard !faceToFace else { return }
        inSplitOrder {
            await self.stopSplitCaptions()
            await EngineWarmupHost.shared.release()   // made for one-way captions; two engines need the memory
            self.faceToFaceDownloaded = await FaceToFaceLanguageList.load()
            self.speakerLanguages = SpeakerLanguages()
            self.split = FaceToFaceSplit(opening: self.stream.lines)
            self.faceToFace = true
        }
    }

    /// A language tapped in a half's list: that half starts (or, with both picked, both restart in the new pair).
    func pickFaceToFace(_ locale: Locale, for half: FaceToFaceHalf) {
        guard faceToFace, split.pick(locale, for: half) else { return }
        restartSplitCaptions()
    }

    /// A half's language name tapped at the middle line: its list again. Captions carry on.
    func openFaceToFaceList(_ half: FaceToFaceHalf) {
        guard faceToFace else { return }
        split.openList(half)
    }

    /// Her half's control in the split: Stop leaves it; Start (paused) carries on with both halves' languages.
    func performInSplit(_ control: FaceToFaceSplit.Control) {
        switch control {
        case .start:
            guard split.resume() else { return }
            restartSplitCaptions()
        case .stop:
            tour.did(.tappedStop)
            inSplitOrder {
                await self.stopSplitCaptions()
                guard self.faceToFace else { return }
                self.endSplitSession()
                self.endFaceToFace()
            }
        }
    }

    /// Ends the split's running captions, if any, and starts them in what the halves picked now.
    private func restartSplitCaptions() {
        inSplitOrder {
            await self.stopSplitCaptions()
            guard self.faceToFace else { return }
            self.endSplitSession()
            guard !self.split.isPaused, let captions = self.split.captions else { return }
            self.splitEngine = await Self.engineLocales(captions)
            self.speakerLanguages = SpeakerLanguages()
            self.split.sessionStarted()
            self.tour.did(.tappedStart)
            self.beta.startPressed(self.session)
            #if DEBUG
            if DemoMode.isOn { self.runSplitDemo(captions); return }
            #endif
            self.controller.start()
        }
    }

    /// Stops the split's captions and waits, without the stop counting as one on their own.
    private func stopSplitCaptions() async {
        splitStopping = true
        defer { splitStopping = false }
        #if DEBUG
        if DemoMode.isOn { demoStopSplit(); return }
        #endif
        await controller.stopAndWait()
    }

    private func inSplitOrder(_ work: @escaping @MainActor () async -> Void) {
        let previous = splitTask
        splitTask = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// The picked languages as the speech engines name them ("es-ES" for "es").
    private static func engineLocales(_ captions: FaceToFaceSplit.Captions) async -> FaceToFaceSplit.Captions {
        func resolved(_ l: Locale) async -> Locale { await SpeechTranscriber.supportedLocale(equivalentTo: l) ?? l }
        switch captions {
        case .one(let half, let l): return .one(half, await resolved(l))
        case .both(let o, let p): return .both(owner: await resolved(o), partner: await resolved(p))
        }
    }

    /// The split's session ended: its lines keep their halves, and the other engine's try at the same words goes.
    private func endSplitSession() {
        let gone = split.sessionEnded(stream.lines, languages: speakerLanguages)
        if !gone.isEmpty { stream.removeLines { gone.contains($0.id) } }
    }

    /// Leaving the split keeps exactly the lines it showed: each voice in its own language's engine's words, never the
    /// other engine's try at the same speech.
    private func endFaceToFace() {
        stream.removeLines { !split.isShown($0, languages: speakerLanguages) }
        faceToFace = false
        split = FaceToFaceSplit()
        splitEngine = nil
        EngineWarmupHost.shared.prepareIfAllowed(micMode: micMode)
    }

    /// The lines the split shows.
    var faceToFaceLines: [CaptionLine] { split.shown(stream.lines, languages: speakerLanguages) }

    /// The half a line belongs to in the split.
    func faceToFaceHalf(of line: CaptionLine) -> FaceToFaceHalf? { split.half(of: line, languages: speakerLanguages) }

    /// Debug only (`-ClarityDemoFaceToFaceLive`): one engine's words for a voice, applied the way the engine's updates
    /// are: into that engine's caption lane, and as evidence of the voice's language.
    func demoFaceToFaceHeard(_ words: [String], speaker: Int, lane: FaceToFaceHalf, at start: Double, isFinal: Bool, pair: LanguagePair) {
        let timed = words.enumerated().map { TimedWord(text: $0.element, start: start + Double($0.offset) * 0.4, end: start + Double($0.offset) * 0.4 + 0.3) }
        stream.apply(text: words.joined(separator: " "), isFinal: isFinal, speaker: speaker,
                     range: start...(timed.last?.end ?? start), lane: lane)
        speakerLanguages.heard(speaker: speaker, lane: lane, words: timed, isFinal: isFinal, classify: pair.probabilities)
    }

    func measureLatency() {
        guard let modelURL = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc"),
              let fixtureURL = Bundle.main.url(forResource: "latency-fixture", withExtension: "wav") else {
            latencyReport = "Fixture or model missing"
            return
        }
        task = Task {
            do {
                // Warm up model once.
                try await TranscriptionEngine.warmUp(diarizerModelURL: modelURL)

                // The engine picked in the developer panel, so check C2 can run both on the same build (ADR 0025).
                let recognizer: SpeechRecognizerSetup = engineChoice == .parakeet
                    ? CaptionEngineFactory.parakeetModelURL.map { .parakeet(modelURL: $0) } ?? .apple : .apple

                // Throwaway pass.
                let warmupEngine = TranscriptionEngine(diarizerModelURL: modelURL, recognizer: recognizer)
                for try await _ in try await warmupEngine.startReplaying(fileURL: fixtureURL) {}

                // Measured pass.
                let engine = TranscriptionEngine(diarizerModelURL: modelURL, recognizer: recognizer)
                var lagSamples: [Double] = []
                var firstCaptionTime: TimeInterval?
                let startTime = Date()

                for try await update in try await engine.startReplaying(fileURL: fixtureURL) {
                    if firstCaptionTime == nil && !update.text.isEmpty {
                        firstCaptionTime = Date().timeIntervalSince(startTime)
                    }
                    if let lag = update.lagSeconds {
                        lagSamples.append(lag)
                    }
                }

                let report = CaptionLatencyReport(lagSamples: lagSamples, timeToFirstCaption: firstCaptionTime)
                latencyReport = engine.engineName + " " + String(format: "Median: %.3f s, P95: %.3f s, First: %.3f s",
                                                                 report.medianLagSeconds,
                                                                 report.p95LagSeconds,
                                                                 report.timeToFirstCaptionSeconds ?? 0)
                    + (engine.decodeSeconds.map { String(format: ", decode p50 %.2f s / p95 %.2f s", $0.p50, $0.p95) } ?? "")
                    + (engine.fallbackReason.map { ", fell back: \($0.rawValue)" } ?? "")
            } catch {
                latencyReport = "Error: \(error)"
            }
            task = nil
        }
    }
}

struct ContentView: View {
    @StateObject private var model = CaptionModel()
    @ObservedObject private var beta = BetaFeedbackCenter.shared
    /// Developer-only tools (mic mode, diagnostics). Long-press the status text to toggle; never shown by default.
    @State private var developerTools = false
    /// Debug only (DemoMode `-ClarityDemoFlow start`): presses the Start pill without a finger.
    @State private var demoPressingStart = false
    /// Round 2 (#118): the app is one screen. Which page shows; the page actually drawn (it changes at the midpoint of
    /// the fade, so the current page fades out before the next fades in); and the fade itself.
    @State private var nav = ScreenNavigator()
    /// #37: the caption language, shared with first run and the engine.
    @ObservedObject private var languages = CaptionLanguageCenter.shared
    /// #53: live translation, its purchase, and each line's translated text.
    @ObservedObject private var translation = TranslationCenter.shared
    /// #233: the translation spoken into her headphones, and the line it's saying.
    @ObservedObject private var ear = EarCenter.shared
    /// #37 / #53: caption language and translation, as Settings and the language list show them.
    private var language: LanguageSettingsState { .current(languages: languages, translation: translation, ear: ear) }
    /// Height of the soft fade under the status row (#117 topedge); the first caption line starts below it (#137).
    static let captionsTopFade: CGFloat = 56
    @State private var shownScreen: AppScreen = .captions
    @State private var pageOpacity: Double = 1
    /// The page fading out while the next fades in (fluidity pass): both are drawn for a moment, never a blank screen.
    @State private var leavingScreen: AppScreen?
    @State private var leavingOpacity: Double = 0
    @State private var position = ScrollPosition(edge: .bottom)
    /// Following the newest caption. Stops only when the user drags away; resumes at the bottom or via "Jump to latest".
    @State private var following = true
    @State private var userDragging = false
    /// Where each caption's words are, so a press-and-hold can tell empty space from words.
    @State private var textFrames = TextFrames()
    /// "Hold on empty space to bring back Save and New": shown the first few times the dim is cleared.
    @State private var showingVeilHint = false
    /// The caption text selected for copying (#107), or nil.
    @State private var selection: CaptionSelection?
    /// When the Copy button shows: half a second after the selection stops changing.
    @State private var copyTiming = CopyButtonTiming()
    /// Where each caption's characters are, recorded as they draw, so a selection can cross lines.
    @State private var glyphs = CaptionGlyphs()
    /// While a handle is dragged: the other end, which stays put.
    @State private var dragAnchor: CaptionPosition?
    /// Which handle the finger went down on, decided before the drag moves it.
    @State private var draggingEdge: SelectionHandle.Edge?
    /// Follows scrolling while something is selected, so the handles and Copy stay on the words.
    @State private var selectionScroll: CGFloat = 0
    /// The tour's "Too quiet? Show an example", offered after a quiet stretch on the captions step (#108).
    @State private var tourOffersExample = false
    @Environment(\.launchCovering) private var launchCovering
    /// Debug demos only: a scripted tap on the rating card (simctl can't tap).
    @State private var demoRatingTap: Int?
    /// #60: the split is open (from the Face to face button until Stop, #208).
    private var faceToFace: Bool { model.faceToFace }
    /// The window's size, which decides whether the screen is big enough to offer the face-to-face split.
    @State private var windowSize: CGSize = .zero
    /// Debug demos only: flips an invisible pixel so screen recordings keep writing frames (see runDemoPause).
    @State private var demoFlushTick = 0

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var style: CaptionStyle { model.style }
    private var control: PrimaryControl { PrimaryControl.for(model.state) }
    private var screenLayout: ScreenLayout {
        let width: WidthClass = horizontalSizeClass == .regular ? .regular : .compact
        let height: HeightClass = verticalSizeClass == .compact ? .compact : .regular
        return ScreenLayout.for(width: width, height: height)
    }
    private var landscape: Bool { screenLayout == .wide }
    private var deviceClass: CaptionDeviceClass {
        UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
    }

    var body: some View {
        ZStack {
            style.background.color.ignoresSafeArea()
            // The captions stay alive under the other pages (their scroll position and a held selection survive a trip
            // to Settings); only the drawn page takes touches and is read by VoiceOver.
            Group {
                if faceToFace && offersFaceToFace { faceToFaceSplit }
                else { landscape ? AnyView(landscapeLayout) : AnyView(portraitLayout) }
            }
                .padding()
                .opacity(opacity(of: .captions))
                .allowsHitTesting(shownScreen == .captions)
                .accessibilityHidden(shownScreen != .captions)
            // Keyed by screen, so the page that's leaving keeps its state while it fades.
            ForEach([leavingScreen, shownScreen].compactMap { $0 }.filter { $0 != .captions }, id: \.self) { screen in
                page(screen)
                    .padding(.top, 8)
                    .opacity(opacity(of: screen))
                    .allowsHitTesting(screen == shownScreen)
                    .accessibilityHidden(screen != shownScreen)
                    .zIndex(screen == shownScreen ? 1 : 0)
            }
            // Beta installs only (ADR 0023): the rating question after a conversation, and the one-time notice. Since
            // round 2 (mock-up round2/04) their words sit straight on the dim, no card, and they only fade.
            if beta.showingCard && shownScreen == .captions {
                ZStack {
                    style.background.color.opacity(0.86).ignoresSafeArea()
                    RatingCardView(style: style, onRate: { value, note in withAnimation(veilAnimation) { model.rate(value, note: note) } },
                                   onSkip: { withAnimation(veilAnimation) { model.skipRating() } },
                                   demoSelected: DemoMode.betaNote ? 8 : nil,
                                   demoNote: DemoMode.betaNote ? "Lost it when the waiter talked fast" : nil,
                                   demoTap: demoRatingTap)
                }
                .transition(.opacity)
                .zIndex(2)
            }
            if beta.showingNotice {
                ZStack {
                    style.background.color.opacity(0.86).ignoresSafeArea()
                    BetaNoticeView(style: style) { withAnimation(veilAnimation) { beta.dismissNotice() } }
                }
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Debug recordings only (demoFlushTick stays 0 otherwise): one corner point, too faint to see.
            if demoFlushTick > 0 {
                (demoFlushTick.isMultiple(of: 2) ? Color.black : Color.white).opacity(0.05)
                    .frame(width: 1, height: 1).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
        .animation(veilAnimation, value: faceToFace)
        .animation(veilAnimation, value: beta.showingCard)
        .animation(veilAnimation, value: beta.showingNotice)
        .task {
            await beta.ensureResolved()
            model.betaResolved()
        }
        // One look for the whole app: background, text, controls and the system's own chrome all follow it.
        .foregroundStyle(style.text.color)
        .tint(style.text.color)
        .preferredColorScheme(style.background.isDark ? .dark : .light)
        .animation(.snappy, value: control.presentation)
        .overlayPreferenceValue(TourTargetKey.self) { anchors in tourLayer(anchors) }
        .onAppear { maybeStartTour() }
        .onChange(of: launchCovering) { maybeStartTour() }
        .onChange(of: model.tour) { old, new in tourChanged(from: old, to: new) }
        .onChange(of: scenePhase) { _, phase in
            ear.foregroundChanged(phase == .active)
            model.appActiveChanged(phase == .active)
            model.scenePhaseChanged(phase)
        }
        // #37: settle the caption language from the engine's list (first run already did, on a first launch).
        .task { await languages.refresh() }
        // #53: what she owns, the price, and Apple's Translation session for the pair while translation is on.
        .task { await translation.start(); translation.linesChanged(model.stream.lines) }
        .translationTask(translation.configuration) { session in await translation.run(session) }
        // #60: the second direction, her words into the other person's language, while the split is open.
        .translationTask(translation.reverseConfiguration) { session in await translation.runReverse(session) }
        .onChange(of: model.stream.lines) { _, _ in translationLinesChanged() }
        .onChange(of: model.speakerLanguages) { _, _ in translationLinesChanged() }
        .onChange(of: faceToFace) { _, on in translation.faceToFaceChanged(on, pair: model.split.languagePair); translationLinesChanged() }
        .onChange(of: model.split) { _, split in translation.faceToFaceChanged(faceToFace, pair: split.languagePair); translationLinesChanged() }
        .task {
            guard DemoMode.isOn else { return }
            model.demoApplyPreset()
            if DemoMode.tour != nil { await runDemoTour(); return }
            if DemoMode.landscape, let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
            if DemoMode.seedsSaved { await seedDemoSaved() }
            model.runDemo()
            if DemoMode.faceToFace { Task { await model.runFaceToFaceFlow() } }
            if DemoMode.opensDeveloperPanel { developerTools = true }
            if DemoMode.opensSettings || DemoMode.settingsPush != nil {
                // Debug only: open straight on Settings (or one of its pages) for screenshots, no fade.
                nav.gearTapped()
                switch DemoMode.settingsPush {
                case "saved", "deleteall": nav.open(.saved)
                case "conversation":   // #139: one saved conversation, for the [ Share ] screenshot
                    nav.open(.saved)
                    if let newest = try? await model.store?.all().max(by: { $0.savedAt < $1.savedAt }) {
                        nav.open(.savedConversation(newest.id))
                    }
                case "credits": nav.open(.credits)
                case "language": nav.open(.captionLanguage)   // #37 / #53: the caption language list
                case "license": nav.open(.credits); nav.open(.licenseText)
                default: break
                }
                shownScreen = nav.current
            }
            await runDemoPause()
        }
        .onChange(of: model.state) { _, newState in
            UIAccessibility.post(notification: .announcement, argument: StatusWords.announcement(for: newState))
            handleStateChange(newState)
            if model.tour.step == .captions { scheduleExampleOffer() }
        }
    }

    /// Getting ready after Start is said where the status is (#117 "preparing" A, mock-up round2/05): the status row
    /// and the Start pill both say "Getting ready…" and the row switches to Listening when it is. Nothing covers the
    /// screen; the launch animation covers getting ready when the app opens.
    private func handleStateChange(_ newState: CaptionState) {
        if newState == .preparing { showingVeilHint = false }
    }

    // MARK: one screen (#118)

    /// Changes the page: the next page starts fading in while the current one fades out, so the screen is never blank
    /// (fluidity pass, owner 2026-10-20; round 2 faded fully out, then in). Fades only.
    private func go(_ change: (inout ScreenNavigator) -> Void) {
        var next = nav
        change(&next)
        guard next != nav else { return }
        nav = next
        let t = FluidTiming.page(reduceMotion: reduceMotion)
        leavingScreen = shownScreen
        leavingOpacity = pageOpacity
        shownScreen = nav.current
        pageOpacity = 0
        let leaving = leavingScreen
        // The swap above must draw before the fades start; in the same update SwiftUI merges them and the old page
        // snaps out (measured: a blank ~150 ms gap in the recording).
        DispatchQueue.main.async {
            withAnimation(Fluid.curve(t.out, reduceMotion)) { leavingOpacity = 0 }
            withAnimation(Fluid.curve(t.in, reduceMotion).delay(t.inDelay)) { pageOpacity = 1 }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(t.total + 0.05))
            if leavingScreen == leaving { leavingScreen = nil }
        }
    }

    private func opacity(of screen: AppScreen) -> Double {
        if screen == shownScreen { return pageOpacity }
        if screen == leavingScreen { return leavingOpacity }
        return 0
    }

    @ViewBuilder
    private func page(_ screen: AppScreen) -> some View {
        switch screen {
        case .captions:
            EmptyView()
        case .settings:
            SettingsPage(style: $model.style, idleStop: $model.idleStop, store: model.store,
                         canShowTour: TourGate.canReplay(state: model.state),
                         onShowTour: {
                             // "Show how to use Seal": back to the captions, then the tour starts there.
                             go { $0.close() }
                             Task { @MainActor in
                                 try? await Task.sleep(for: .seconds(FluidTiming.page(reduceMotion: reduceMotion).total))
                                 withAnimation(veilAnimation) { model.tour.begin() }
                             }
                         },
                         onGear: {
                             model.tour.did(.closedSettings)
                             go { $0.gearTapped() }
                         },
                         onOpen: { screen in go { $0.open(screen) } },
                         language: language,
                         onChooseCaptionLanguage: { go { $0.open(.captionLanguage) } },
                         onTranslation: { translation.setOn($0) },
                         onChooseTranslationTarget: { go { $0.open(.translationTarget) } },
                         onEar: { ear.setOn($0) },
                         onBuyTranslation: { Task { await translation.unlock() } },
                         onRestorePurchases: { Task { await translation.restore() } })
        case .translationTarget:
            TranslationTargetPage(style: style, language: language, onBack: { go { $0.back() } },
                                  onChoose: { locale in translation.setTarget(locale); go { $0.back() } })
                .padding(.horizontal, 16)
        case .captionLanguage:
            CaptionLanguagePage(style: style, language: language, onBack: { go { $0.back() } },
                                onChoose: { locale in Task { await languages.choose(locale) } })
                .padding(.horizontal, 16)
        case .saved:
            if let store = model.store {
                SavedConversationsPage(backTitle: nav.savedOpenedFromCaptions ? String(localized: "Captions") : String(localized: "Settings"),
                                       store: store, style: style, onBack: { go { $0.back() } },
                                       onOpen: { id in go { $0.open(.savedConversation(id)) } })
                    .padding(.horizontal, 16)
            }
        case .savedConversation(let id):
            if let store = model.store {
                SavedConversationPage(store: store, id: id, style: style, onBack: { go { $0.back() } })
                    .padding(.horizontal, 16)
            }
        case .credits:
            CreditsPage(style: style, onBack: { go { $0.back() } }, onLicenseText: { go { $0.open(.licenseText) } })
                .padding(.horizontal, 16)
        case .licenseText:
            LicenseTextPage(style: style, onBack: { go { $0.back() } })
                .padding(.horizontal, 16)
        case .feedbackPreview:
            FeedbackPreviewPage(style: style, idleStop: model.idleStop, beta: beta, onClose: { go { $0.back() } },
                                demoAutoContinue: DemoMode.flow == "feedback")
                .padding(.horizontal, 16)
        }
    }

    /// Portrait: the gear and the status share the top row, so captions start right under it. Start captions sits at
    /// the bottom middle; while captioning, Stop is a small circle at the bottom right (#102, mock-up 01/02).
    private var portraitLayout: some View {
        VStack(spacing: 12) {
            topRow
            if developerTools { developerPanel }
            // The control floats over the bottom edge; the scroll content keeps a margin so the newest line never
            // sits under it.
            captions(bottomReserve: 72 + 24)
        }
        .overlay(alignment: .bottom) { controlBar(pillWidth: nil) }
    }

    /// Landscape: the same top row, captions across the full width, Start captions at the bottom middle and Stop in
    /// the bottom-right corner.
    private var landscapeLayout: some View {
        VStack(spacing: 8) {
            topRow
            captions(bottomReserve: 72 + 16)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { geo in controlBar(pillWidth: min(geo.size.width * 0.47, 440)) }
        }
        .overlay(alignment: .bottomLeading) { if developerTools { developerPanel.frame(maxWidth: 360).padding(.bottom, 80) } }
    }

    /// The single bottom control. The Start pill is centered; Stop shrinks into the bottom-right corner and grows
    /// back out. `pillWidth` nil means the full row (portrait).
    private func controlBar(pillWidth: CGFloat?) -> some View {
        GeometryReader { geo in
            MorphingControl(control: control, fullWidth: pillWidth ?? geo.size.width,
                            fill: style.text, label: style.background, forcePressed: demoPressingStart) {
                model.perform(control.action)
            }
            .tourTarget(control.presentation == .compact ? .stop : .start)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: control.presentation == .compact ? .bottomTrailing : .bottom)
        }
        .frame(height: 72)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// The gear on the left (icon only, no label or background) with the status centered on the same row.
    private var topRow: some View {
        VStack(spacing: 2) {
            ZStack {
                statusLine
                HStack {
                    settingsButton
                    Spacer()
                    if offersFaceToFace { faceToFaceButton }
                    savedButton
                }
            }
            if let detail = statusDetail {
                Text(detail).font(.footnote).opacity(0.7).multilineTextAlignment(.center)
            }
        }
        .onChange(of: model.activity) { _, newActivity in
            if let activity = newActivity {
                UIAccessibility.post(notification: .announcement, argument: StatusWords.announcement(for: model.state, activity: activity))
            }
        }
    }

    /// Each theme's own gear color (design #96, image 6); colors from an older build fall back to the text color.
    private var gearColor: Color { style.gear.color }

    private var settingsButton: some View {
        Button {
            model.tour.did(.openedSettings)
            go { $0.gearTapped() }
        } label: {
            Image(systemName: "gearshape")
                .font(.title2)
                .foregroundStyle(gearColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableIconStyle(tint: gearColor))
        .tourTarget(.gear)
        .accessibilityLabel(String(localized: "Settings"))
    }

    /// #60: the split is offered on a screen big enough for two halves (iPad, the unfolded Duo) with translation on, in
    /// the top row (owner, 2026-10-29).
    private var offersFaceToFace: Bool {
        FaceToFace.offersSplit(width: windowSize.width, height: windowSize.height, translationOn: translation.isActive)
    }

    private var faceToFaceButton: some View {
        RetroWords(word: String(localized: "Face to face"), color: gearColor, background: style.background.color,
                   size: .body, label: String(localized: "Face to face")) {
            model.startFaceToFace()
        }
    }

    /// The half a line belongs to: settled when an earlier session in the split ended, else from the running one.
    private func faceToFaceHalf(_ line: CaptionLine) -> FaceToFaceHalf? { model.faceToFaceHalf(of: line) }

    /// A line's words in the language of the half that reads them: the other person's into hers, hers into theirs (the
    /// second direction, #60). The simulator has no Translation languages: demos fill in their own stand-ins.
    private func faceToFaceTranslation(_ line: CaptionLine, into half: FaceToFaceHalf) -> String? {
        half == .owner ? translation.translations.translation(for: line) : translation.reverseTranslations.translation(for: line)
    }

    /// Live translation follows the conversation: one-way, every line into her language; in the split, each half's
    /// lines into the other half's language.
    private func translationLinesChanged() {
        guard faceToFace else { translation.linesChanged(model.stream.lines); return }
        let shown = model.faceToFaceLines
        translation.linesChanged(FaceToFace.lines(saidOn: .partner, in: shown, half: faceToFaceHalf),
                                 reverse: FaceToFace.lines(saidOn: .owner, in: shown, half: faceToFaceHalf))
    }

    /// #208: each half shows its list until it picks (the language the other half picked left out), then its lines.
    private var faceToFaceSplit: some View {
        let split = model.split, lines = model.faceToFaceLines
        func choices(_ half: FaceToFaceHalf) -> [Locale]? {
            split.showsList(half) ? split.choices(for: half, downloaded: model.faceToFaceDownloaded, name: \.nameInItself) : nil
        }
        let ownerChoices = choices(.owner), partnerChoices = choices(.partner)
        let control = PrimaryControl.inSplit(split.control)
        return FaceToFaceView(
            style: style, device: deviceClass,
            owner: FaceToFace.entries(for: .owner, lines: lines, half: faceToFaceHalf, translation: faceToFaceTranslation),
            partner: FaceToFace.entries(for: .partner, lines: lines, half: faceToFaceHalf, translation: faceToFaceTranslation),
            ownerLanguage: split.language(of: .owner)?.nameInItself ?? "",
            partnerLanguage: split.language(of: .partner)?.nameInItself ?? "",
            ownerLanguageID: split.language(of: .owner)?.identifier, partnerLanguageID: split.language(of: .partner)?.identifier,
            translatedLook: DemoMode.translatedLook,
            ownerChoices: ownerChoices?.map(\.nameInItself), partnerChoices: partnerChoices?.map(\.nameInItself),
            choose: { half, i in
                guard let list = half == .owner ? ownerChoices : partnerChoices, list.indices.contains(i) else { return }
                model.pickFaceToFace(list[i], for: half)
            },
            pickAgain: { model.openFaceToFaceList($0) },
            control: {
                MorphingControl(control: control, fullWidth: min(windowSize.width * 0.47, 440),
                                fill: style.text, label: style.background) { model.performInSplit(split.control) }
                    .frame(maxWidth: .infinity, alignment: control.presentation == .compact ? .trailing : .center)
            })
    }

    /// Option A (#137, approved 2026-10-15): Saved conversations one tap away, opposite the gear, same color and size.
    private var savedButton: some View {
        Button {
            go { $0.openSavedFromCaptions() }
        } label: {
            Image(systemName: "list.bullet")
                .font(.title2)
                .foregroundStyle(gearColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableIconStyle(tint: gearColor))
        .tourTarget(.savedList)
        .accessibilityLabel(String(localized: "Saved conversations"))
    }

    private var statusHeadline: String {
        if let activity = model.activity { return StatusWords.headline(for: model.state, activity: activity) }
        return StatusWords.headline(for: model.state, hasConversation: model.hasConversation)
    }

    private var statusDetail: String? {
        if let activity = model.activity { return StatusWords.secondLine(for: model.state, activity: activity) }
        return StatusWords.detail(for: model.state)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            if let activity = model.activity, case .listening = model.state {
                renderStatusDot(StatusDot.select(state: model.state, activity: activity, roomLevelDBFS: model.roomLevelDBFS))
            }
            // Each status word is its own view, so a change fades out then in, in one spot, instead of morphing
            // letter by letter ("Listening" into "Paused" smeared; fluidity pass). The ZStack keeps both in that spot.
            ZStack {
                Text(statusHeadline)
                    .id(statusHeadline)
                    .transition(Fluid.wordSwap(reduceMotion))
            }
            .font(.subheadline.weight(.semibold))
            .opacity(0.8)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .modifier(DeveloperHold { developerTools.toggle() })
        }
        .padding(.horizontal, 52)   // never under the gear
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func renderStatusDot(_ dot: StatusDot) -> some View {
        switch dot {
        case .pulsing(let level):
            ListeningLightView(background: style.background, roomLevelDBFS: level)
        case .flatAmber:
            Circle()
                .fill(Color(red: 1, green: 0.68, blue: 0))
                .frame(width: 8, height: 8)
        case .hidden:
            EmptyView()
        }
    }

    private func captions(bottomReserve: CGFloat = 0) -> some View {
        let palette = SpeakerPalette.colors(on: style.background, text: style.text).map(\.color)
        let placeholderColor = SpeakerPalette.placeholderColor(on: style.background, text: style.text).color
        let lines = model.stream.lines
        let resolved = selection?.resolved(in: lines)
        let lineIndex = resolved == nil ? [:] : Dictionary(uniqueKeysWithValues: lines.enumerated().map { ($1.id, $0) })
        let highlight = SelectionColors.highlight(on: style.background).color
        // #233: the line the voice is saying.
        let earSpeaking = translation.isActive ? ear.speaking : nil
        let newestSpokenLineID = lines.last(where: { !$0.isSoundLabel && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })?.id
        func selected(_ line: CaptionLine) -> Range<Int>? {
            guard let resolved, let i = lineIndex[line.id] else { return nil }
            return resolved.range(forLineAt: i, length: line.text.utf16.count)
        }
        return ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // The first line starts below the top fade (#137: "Speaker 1 needs top padding").
                    Color.clear.frame(height: Self.captionsTopFade - 16).accessibilityHidden(true)
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            let labelState = SpeakerLabeling.state(for: line)
                            if labelState != .none {
                                speakerLabelRow(for: labelState, speaker: line.speaker, palette: palette, placeholderColor: placeholderColor)
                                    .trackWords(in: textFrames, key: "label-\(line.id)")
                            }
                            // Selection is ours, not the system's (#107): it crosses lines and shows only Copy.
                            let renderer = SelectableCaptionRenderer(lineID: line.id, length: line.text.utf16.count,
                                                                     selected: selected(line), highlight: highlight, glyphs: glyphs)
                            if line.isSoundLabel {
                                Text(line.text).font(style.font(for: SystemTextSizeCategory(dynamicTypeSize), device: deviceClass).italic()).opacity(line.isFinal ? 1 : style.volatileOpacity)
                                    .textRenderer(renderer)
                                    .accessibilityLabel(line.soundLabel.map { soundLabelA11yLabel(for: $0) } ?? "")
                                    .trackWords(in: textFrames, key: "text-\(line.id)")
                            } else if let look = DemoMode.translatedLook, translation.isActive,
                                      let translated = translation.translations.translation(for: line) ?? ear.spokenTranslations[line.id] {
                                // #246 mock-up (debug demo flag only): the same line drawn in one of the options.
                                let speaking = earSpeaking.flatMap { $0.lineID == line.id ? $0 : nil }
                                TranslatedCaptionView(look: look, translated: translated, said: line.text, saidLanguage: DemoMode.language,
                                                      speakingFirm: speaking.map {
                                                          EarProgress.firmWords(shown: translated.split(separator: " ").count,
                                                                                lineWords: line.text.split(separator: " ").count,
                                                                                phrase: $0.words, share: $0.share)
                                                      },
                                                      font: style.font(for: SystemTextSizeCategory(dynamicTypeSize), device: deviceClass),
                                                      text: style.text.color, muted: mutedColor(style), mark: style.gear.color,
                                                      volatileOpacity: style.volatileOpacity,
                                                      startsOpen: line.id == lines.dropLast().last(where: { !$0.isSoundLabel })?.id)
                            } else if translation.isActive,
                                      let translated = translation.translations.translation(for: line) ?? ear.spokenTranslations[line.id] {
                                // #53 (owner, PR #171): the translation is the line that's read, on top at caption size
                                // behind a translate mark; what was said stays, smaller, underneath. Selection and Copy
                                // work on what was said. #233: until a line's own translation lands, what the voice said
                                // for it shows.
                                if let earSpeaking, earSpeaking.lineID == line.id {
                                    let shown = translated.split(separator: " ").count
                                    EarSpeakingLine(translated: translated,
                                                    firm: EarProgress.firmWords(shown: shown, lineWords: line.text.split(separator: " ").count,
                                                                                phrase: earSpeaking.words, share: earSpeaking.share),
                                                    font: style.font(for: SystemTextSizeCategory(dynamicTypeSize), device: deviceClass),
                                                    mark: style.gear.color, text: style.text.color, volatileOpacity: style.volatileOpacity)
                                } else {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Image(systemName: "translate").font(.subheadline.bold()).foregroundStyle(mutedColor(style))
                                        Text(translated).font(style.font(for: SystemTextSizeCategory(dynamicTypeSize), device: deviceClass))
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(String(localized: "Translated: ") + translated)
                                }
                                Text(line.text).font(.body).foregroundStyle(mutedColor(style))
                                    .textRenderer(renderer)
                                    .trackWords(in: textFrames, key: "text-\(line.id)")
                                    .accessibilityLabel(String(localized: "Said: ") + line.text)
                            } else {
                                Text(line.text).font(style.font(for: SystemTextSizeCategory(dynamicTypeSize), device: deviceClass)).opacity(line.isFinal ? 1 : style.volatileOpacity)
                                    .textRenderer(renderer)
                                    .trackWords(in: textFrames, key: "text-\(line.id)")
                            }
                        }
                        .onDisappear { glyphs.remove(line.id) }
                        .modifier(TourTargetIf(target: .captions, active: line.id == newestSpokenLineID))
                        .accessibilityElement(children: .contain)
                        .accessibilityAction(named: String(localized: "Copy")) { copyLine(line) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                }
            }
            .coordinateSpace(.named(TextFrames.space))
            // Captions scrolling up under the status row fade out softly instead of being cut in half (#117 topedge).
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Self.captionsTopFade)
                    Rectangle()
                }
            }
            // Press and hold on caption words selects them for copying (#107), captioning or paused. Paused with the
            // dim cleared, press and hold on empty space (not on words) brings back the dim and [ Save ] / [ New ].
            .gesture(HoldLocationGesture { location in
                if let hit = textFrames.captionLine(at: location) {
                    beginSelection(lineID: hit.id, at: CGPoint(x: location.x - hit.frame.minX, y: location.y - hit.frame.minY))
                    return
                }
                guard PauseVeil.isPaused(model.state), model.hasConversation, !textFrames.contains(location) else { return }
                clearSelection()
                bringBackVeil()
            })
            .gesture(SelectionHandleGesture(canBegin: { point in
                guard let edge = handle(near: point) else { return false }
                draggingEdge = edge
                return true
            }, onDrag: dragHandle))
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                if selection != nil, handle(near: tap.location) == nil { clearSelection() }
            })
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                if selection != nil { selectionScroll = y }
            }
            .scrollPosition($position)
            // Opens on the newest line (a restored conversation too), clear of the control.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .contentMargins(.bottom, bottomReserve, for: .scrollContent)
            .onScrollPhaseChange { _, phase in userDragging = (phase == .interacting || phase == .decelerating) }
            .onScrollGeometryChange(for: Bool.self) { g in
                AutoScroll.shouldFollow(offsetY: g.contentOffset.y, viewportHeight: g.containerSize.height, contentHeight: g.contentSize.height)
            } action: { _, atBottom in
                if atBottom { following = true } else if userDragging { following = false }
            }
            .onChange(of: model.stream.lines) {
                // A selection whose words are gone (a new conversation) goes too; while one is held, new captions
                // don't scroll the words out from under her finger.
                if let selection, selection.resolved(in: model.stream.lines) == nil { clearSelection() }
                if AutoScroll.followsNewCaptions(following: following, selecting: selection != nil) { position.scrollTo(edge: .bottom) }
            }
            .overlay(alignment: .bottom) {
                // Approved in #120 as A: retro words, [ ↓ Latest ], fading in and out like everything else.
                ZStack {
                    if AutoScroll.showsJumpToLatest(following: following) {
                        RetroWords(word: AutoScroll.jumpToLatestWord, color: style.text.color, background: style.background.color,
                                   size: .title3, label: String(localized: "Jump to latest")) {
                            following = true
                            withAnimation { position.scrollTo(edge: .bottom) }
                        }
                        .frame(minHeight: 48)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                    }
                }
                .animation(Fluid.fade(reduceMotion), value: following)
            }

            if selection != nil { selectionChrome }

            pauseVeil

            if showingVeilHint {
                Text(String(localized: "Hold on empty space to bring back Save and New"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(style.background.color)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(style.text.color, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, bottomReserve + 8)   // just above Start, which floats over the captions' bottom
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

        }
        .animation(veilAnimation, value: model.veil.isVisible(state: model.state, hasConversation: model.hasConversation))
        .accessibilityAction(named: String(localized: "Show Save and New")) { bringBackVeil() }
        .tourTarget(.captionArea)   // step 6: holding an empty spot here brings the dim back
    }

    /// Debug only (DemoMode): the paused states and flows #102's screenshots and recordings show.
    private func runDemoPause() async {
        func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        UserDefaults.standard.removeObject(forKey: Self.veilHintKey)   // every demo shows the hint as a first time would
        // The demo adds its whole conversation at once, right after appearing; land on the newest line as live use does.
        await wait(0.3); position.scrollTo(edge: .bottom)
        await wait(0.7); position.scrollTo(edge: .bottom)   // again once the rows have measured themselves
        if DemoMode.paused { model.demoSetState(.idle) }
        if DemoMode.saved { model.save() }
        if DemoMode.veilCleared { clearVeil() }
        if DemoMode.betaCard {
            model.demoSetState(.idle)
            await BetaFeedbackCenter.shared.ensureResolved()
            BetaFeedbackCenter.shared.demoShowCard()
        }
        if DemoMode.select, let from = demoPosition("free for"), let to = demoPosition("own colour", end: true) {
            await wait(0.4)
            setSelection(CaptionSelection(anchor: from, focus: to))
        }
        switch DemoMode.flow {
        case "save":
            await wait(2); model.demoSetState(.idle)
            await wait(2); withAnimation(Fluid.saveMorph(reduceMotion)) { model.save() }
            await wait(3); model.demoSetState(.preparing); model.demoSetState(.listening)
            await wait(1); model.demoSay("Then let's go Saturday at seven.", speaker: 1)
            await wait(2); model.demoSetState(.idle)
        case "clear":
            model.demoSetState(.idle)
            await wait(2); clearVeil()
            await wait(3); bringBackVeil()
        case "copy":
            // simctl can't touch, so the hold and the handle drag are scripted through the same paths a finger takes.
            model.demoSetState(.idle)
            await wait(1); clearVeil()
            await wait(1.5)
            if let p = demoPosition("anyone"), let line = model.stream.lines.first(where: { $0.id == p.lineID }),
               let word = CaptionSelection.word(at: p.offset + 1, in: line) {
                showingVeilHint = false
                setSelection(word)
            }
            await wait(1.2)                                   // Copy appears half a second after the hold
            if let to = demoPosition("own colour", end: true) { await demoExtend(to: to) }
            await wait(1.8)
            if let to = demoPosition("Each of us", end: true) { await demoExtend(to: to) }   // resize back; Copy follows
            await wait(1.8); copySelection()
        case "start":
            // simctl can't tap: press the Start pill, let go, then start captioning so it sweeps into Stop.
            model.demoSetState(.idle)
            await wait(2); demoPressingStart = true
            await wait(0.35); demoPressingStart = false
            // Getting ready shows in the status row and on the pill only (round 2), then Listening.
            await wait(0.25); model.demoSetState(.preparing)
            await wait(2); model.demoSetState(.listening)
            await wait(3); model.demoSetState(.idle)
        case "rate":
            // ADR 0023: [ New ] on a paused conversation brings the card; one tap on 8 rates it and the card fades.
            await BetaFeedbackCenter.shared.ensureResolved()
            model.demoSetState(.listening)
            await wait(1.5); model.demoSetState(.idle)
            await wait(2); model.save()
            await wait(2); withAnimation(veilAnimation) { model.startNew() }
            await wait(2.5); demoRatingTap = 8
        case "settings":
            // Round 2 (#118): the gear fades the captions out and Settings in; the gear takes her back.
            model.demoSetState(.listening)
            await wait(2); go { $0.gearTapped() }
            await wait(3); go { $0.gearTapped() }
            await wait(2)
        case "saved", "delete":
            // Round 2: Settings, then the saved list fades in; "‹ Settings" fades back (the delete flow asks in place).
            await wait(1.5); go { $0.gearTapped() }
            await wait(2); go { $0.open(.saved) }
            if DemoMode.flow == "saved" { await wait(3); go { $0.back() }; await wait(2) }
        case "feedback":
            await BetaFeedbackCenter.shared.ensureResolved()
            await wait(1.5); go { $0.gearTapped() }
        case "new":
            model.demoSetState(.idle)
            await wait(2); model.requestNew()
            await wait(3); withAnimation(veilAnimation) { if model.newQuestion.confirm() != nil { model.startNew() } }
        default:
            break
        }
        // Debug only: simctl's recorder stops writing frames once the screen goes still, so a recording ends mid-fade.
        // A few invisible pixel changes after a flow keep it writing until the last fade has settled.
        if ["settings", "saved", "delete", "new", "start"].contains(DemoMode.flow ?? "") {
            for _ in 0..<20 { await wait(0.35); demoFlushTick += 1 }
        }
        // The UI audit (2026-10-10): one state each, as she'd meet it.
        switch DemoMode.show {
        case "preparing": model.demoSetState(.preparing)
        case "confirmnew": model.demoSetState(.idle); await wait(1); model.requestNew()
        case "jump": following = false
        case "canthear": model.demoSetState(.listening); model.activity = .cantHearAnything
        case "listening":
            // A pretend room for the Listening light (#180): someone talks, pauses, talks louder.
            model.demoSetState(.listening); model.activity = .activelyListening
            Task { @MainActor in
                for level in Array(repeating: AliveDemoView.roomLevels, count: 20).joined() {
                    model.roomLevelDBFS = level
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
        case "failed": model.demoSetState(.failed(String(localized: "The microphone stopped. Tap Start captions to try again.")))
        case "quiet": model.demoSetState(.pausedQuiet(minutes: 5))
        case "savedfromcaptions":
            // The list icon at the top right (#137, option A): Saved opens straight from the captions.
            await wait(1); go { $0.openSavedFromCaptions() }
        case "savebeta":
            // A beta install (Xcode counts), no tour: pause, [ Save ], then [ New ].
            await BetaFeedbackCenter.shared.ensureResolved()
            model.demoSetState(.listening)
            await wait(1); model.demoSetState(.idle)
            await wait(2); withAnimation(Fluid.saveMorph(reduceMotion)) { model.save() }
            await wait(3); model.requestNew()
        default: break
        }
    }

    /// Debug only: the three saved conversations of mock-up round2/02.
    private func seedDemoSaved() async {
        guard let store = model.store else { return }
        try? await store.deleteAll()
        let cal = Calendar.current
        let today = Date()
        func at(_ day: Date, _ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day }
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let items: [(Date, String)] = [
            (at(yesterday, 19, 12), "Speaker 1: So we finally tried the new place on Fifth, Luigi's.\nSpeaker 2: Oh, how was it? I heard the pasta is homemade."),
            (at(today, 8, 55), "Speaker 2: It's catching every word, even from across the table.\nSpeaker 1: That's the idea."),
            (at(today, 8, 56), "Speaker 1: Happy birthday, Mom. Watch the screen while we talk.\nSpeaker 2: Oh, I can read all of it!"),
        ]
        for (when, text) in items {
            try? await store.save(SavedConversation(startedAt: when, savedAt: when, transcript: text))
        }
    }

    /// Debug only: where a phrase of the demo conversation sits.
    private func demoPosition(_ phrase: String, end: Bool = false) -> CaptionPosition? {
        for line in model.stream.lines {
            let r = (line.text as NSString).range(of: phrase)
            if r.location != NSNotFound { return CaptionPosition(lineID: line.id, offset: end ? NSMaxRange(r) : r.location) }
        }
        return nil
    }

    /// Debug only: moves the selection's end toward `target` a few letters at a time, the way a dragged handle does.
    private func demoExtend(to target: CaptionPosition) async {
        let lines = model.stream.lines
        guard let selection, var li = lines.firstIndex(where: { $0.id == selection.focus.lineID }),
              let ti = lines.firstIndex(where: { $0.id == target.lineID }) else { return }
        var offset = selection.focus.offset
        let forward = (li, offset) < (ti, target.offset)
        while (li, offset) != (ti, target.offset) {
            offset += forward ? 3 : -3
            if forward, li < ti, offset >= lines[li].text.utf16.count { li += 1; offset = 0 }
            if !forward, li > ti, offset <= 0 { li -= 1; offset = lines[li].text.utf16.count }
            if li == ti { offset = forward ? min(offset, target.offset) : max(offset, target.offset) }
            setSelection(CaptionSelection(anchor: selection.anchor, focus: CaptionPosition(lineID: lines[li].id, offset: offset)))
            try? await Task.sleep(for: .milliseconds(45))
        }
    }

    private var veilAnimation: Animation { Fluid.fade(reduceMotion) }

    /// The dim over a paused conversation: the captions fade toward the theme's own background (about 86%, mock-up
    /// 02) and [ Save ] sits over [ New ], centered, each on a plain patch of background so faded words never show
    /// through the letters. One tap on the dim clears it to scroll and copy.
    private var veilShowing: Bool { model.veil.isVisible(state: model.state, hasConversation: model.hasConversation) }

    private var pauseVeil: some View {
        DimLayer(visible: veilShowing,
                 color: style.background.color, reduceMotion: reduceMotion, onTap: { clearVeil() }) { pauseVeilWords }
    }

    /// What sits on the dim: [ Save ] over [ New ], or [ New ]'s question in their place.
    private var pauseVeilWords: some View {
        ZStack {
            // The tour finds the dim and [ Save ] only while they're showing (the dim is always in the tree now).
            Color.clear
                .modifier(TourTargetIf(target: .veil, active: veilShowing))
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Paused conversation"))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(String(localized: "Double tap to show the conversation"))
                .accessibilityAction { clearVeil() }
                .allowsHitTesting(false)
            if model.newQuestion.isAsking {
                InPlaceQuestionView(style: style,
                                    title: String(localized: "Start a new conversation?"),
                                    message: String(localized: "This one isn't saved."),
                                    yes: String(localized: "Start new"), yesIsDestructive: false,
                                    no: String(localized: "Keep it"), stacked: true,
                                    onYes: {
                                        withAnimation(veilAnimation) {
                                            if model.newQuestion.confirm() != nil { model.startNew() }
                                        }
                                    },
                                    onNo: { withAnimation(veilAnimation) { model.newQuestion.keep() } })
                    .transition(.opacity)
            } else if !beta.showingCard {
                // While the rating question shows over a paused conversation, [ Save ] / [ New ] step aside so its
                // words sit on a plain dim (round2/04), not over ghosted buttons.
                VStack(spacing: 24) {
                    saveButton.modifier(TourTargetIf(target: .save, active: veilShowing))
                    retroButton(String(localized: "New"), color: style.text.color,
                                label: String(localized: "Start a new conversation")) { withAnimation(veilAnimation) { model.requestNew() } }
                }
                .transition(.opacity)
            }
        }
    }

    /// [ Save ] → [ ✔ ] → [ Saved ] is one view whose word changes: the brackets ease narrower for ✔ and wider for
    /// Saved while the word fades out and in (fluidity pass); three separate views swapped whole and looked choppy.
    @ViewBuilder
    private var saveButton: some View {
        let green = SavedGreen.color(on: style.background).color
        let words = [String(localized: "Save"), Self.checkMark, String(localized: "Saved")]
        let button = model.session.saveButton(lines: model.stream.lines, names: model.speakerNames)
        if model.showingSaveCheck || button != .unavailable {
            let save = !model.showingSaveCheck && button == .save
            RetroWords(word: model.showingSaveCheck ? Self.checkMark : save ? words[0] : words[2],
                       color: save ? style.text.color : green, background: style.background.color,
                       label: save ? String(localized: "Save conversation")
                                   : model.showingSaveCheck ? String(localized: "Saved") : String(localized: "Conversation saved"),
                       action: save ? { withAnimation(Fluid.saveMorph(reduceMotion)) { model.save() } } : nil)
        }
    }

    /// The retro, literal-text buttons: [ Save ], [ ✔ ], [ Saved ], [ New ] (shared with every page, OneScreenPieces).
    private func retroButton(_ word: String, color: Color, label: String, action: (() -> Void)?) -> some View {
        RetroWords(word: word, color: color, background: style.background.color, label: label, action: action)
    }

    private static let checkMark = "✔"
    private static let veilHintLimit = 3
    private static let veilHintKey = "pauseVeilHintCount"

    private func clearVeil() {
        // A tap on the dim while [ New ] is asking answers it like [ Keep it ]: nothing is lost.
        withAnimation(veilAnimation) {
            model.newQuestion.keep()
            model.veil.tap(state: model.state)
            model.tour.did(.clearedDim)
        }
        // The tour's step 6 says this itself ("Hold an empty spot."), so the hint stays away while it runs.
        guard !model.tour.isRunning else { return }
        let shown = UserDefaults.standard.integer(forKey: Self.veilHintKey)
        guard shown < Self.veilHintLimit else { return }
        UserDefaults.standard.set(shown + 1, forKey: Self.veilHintKey)
        withAnimation(veilAnimation) { showingVeilHint = true }
    }

    private func bringBackVeil() {
        withAnimation(veilAnimation) {
            model.veil.holdOnEmptySpace(state: model.state)
            showingVeilHint = false
            model.tour.did(.restoredDim)
        }
    }

    // MARK: the how-to-use tour (#108)

    @ViewBuilder
    private func tourLayer(_ anchors: [TourSpot: Anchor<CGRect>]) -> some View {
        if model.tour.isRunning {
            TourOverlay(tour: model.tour,
                        anchors: anchors,
                        style: style,
                        offersExample: tourOffersExample,
                        onBack: { withAnimation(veilAnimation) { model.tour.back() } },
                        onSkip: { withAnimation(veilAnimation) { model.tour.skip() } },
                        onDone: { withAnimation(veilAnimation) { model.tour.did(.tappedDone) } },
                        onNext: { withAnimation(veilAnimation) { model.tour.did(.tappedNext) } },
                        onExample: { withAnimation { model.showTourExample() } })
                .transition(.opacity)
        }
    }

    /// The one automatic run: after first run, once the launch animation has gone, on an empty idle screen.
    private func maybeStartTour() {
        guard !DemoMode.isOn, !model.tour.isRunning else { return }
        let store = TourStore()
        guard TourGate.startsByItself(hasSeen: store.hasSeen, state: model.state, hasConversation: model.hasConversation,
                                      launchCovering: launchCovering) else { return }
        store.markSeen()   // it runs once, even if Seal is closed partway; Settings replays it
        withAnimation(veilAnimation) { model.tour.begin() }
    }

    /// Step or phase changed: say the new words, wait out a follow-up's reading beat, and after Back set the screen up
    /// so the step's real action can be done again.
    private func tourChanged(from old: HowToUseTour, to new: HowToUseTour) {
        guard let step = new.step else {
            tourOffersExample = false
            if old.step != nil { withAnimation(veilAnimation) { model.tourEnded() } }
            return
        }
        if new.step != old.step || new.phase != old.phase, new.showsWords {
            UIAccessibility.post(notification: .announcement, argument: new.words.title)
        }
        if new.step != old.step { tourOffersExample = false }
        if let previous = old.step, step.rawValue < previous.rawValue { prepareAfterBack(for: step) }
        if step == .captions && old.step != .captions {
            // Next without starting (#137): show the two-voice example so step 2 has words to point at.
            let captioning = model.state == .listening || model.state == .preparing
            if !captioning && !model.hasConversation { withAnimation { model.showTourExample() } } else { scheduleExampleOffer() }
        }
    }

    /// Back to a step whose action already happened: put the screen back the way that step needs it, using the same
    /// calls the real controls make (the tour ignores them, since they aren't the step's own action).
    private func prepareAfterBack(for step: TourStep) {
        let listening = model.state == .listening || model.state == .preparing
        switch step {
        case .start:
            if listening { model.perform(.stop) }
        case .captions:
            if !listening && !model.hasConversation { model.showTourExample() }
        case .pause, .done:
            break
        }
    }

    /// A quiet room: after a few seconds of captioning with nothing to show, step 2 offers [ Show an example ].
    private func scheduleExampleOffer() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(TourExample.quietSeconds))
            guard model.tour.step == .captions, !model.hasConversation else { return }
            let captioning = model.state == .listening || model.state == .preparing
            withAnimation { tourOffersExample = TourExample.offersExample(secondsWithoutCaption: TourExample.quietSeconds, isCaptioning: captioning) }
        }
    }

    /// Debug only (`-ClarityDemoTour flow` plays the whole tour; `-ClarityDemoTour <1-8>` pins one step,
    /// `-ClarityDemoTour 2b` / `4b` its follow-up). simctl can't tap, so a scripted user does each step's real action
    /// through the same calls the real controls make; only starting and stopping the engine is pretended, since the
    /// simulator has no speech engine.
    private func runDemoTour() async {
        func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        func start() { model.tour.did(.tappedStart); model.demoSetState(.preparing); model.demoSetState(.listening) }
        func stop() { model.tour.did(.tappedStop); model.demoSetState(.idle) }
        await wait(0.6)
        if let pin = DemoMode.tour, pin != "flow" {
            guard let n = Int(pin.filter(\.isNumber)), let target = TourStep(rawValue: n - 1) else { return }
            // A still of one step (1-4), with the screen set up the way she'd reach it.
            if target.rawValue >= TourStep.captions.rawValue { model.demoSetState(.preparing); model.demoSetState(.listening); model.showTourExample() }
            if target == .done { model.demoSetState(.idle) }
            await wait(1.6)
            model.tour = HowToUseTour(step: target)
            return
        }
        model.tour.begin()
        await wait(3)
        start()                                                    // 1: Start captions
        await wait(2.5)
        withAnimation { model.showTourExample() }                  // 2: words appear; she reads, then Next
        await wait(4)
        withAnimation(veilAnimation) { model.tour.did(.tappedNext) }
        await wait(3)
        stop()                                                     // 3: the X pauses (and moves on)
        await wait(4)
        withAnimation(veilAnimation) { model.tour.did(.tappedDone) } // 4: [ Done ]
    }

    // MARK: copying (#107)

    /// Press and hold on a caption's words: select the word under the finger.
    private func beginSelection(lineID: Int, at local: CGPoint) {
        guard let line = model.stream.lines.first(where: { $0.id == lineID }),
              let offset = glyphs.offset(at: local, lineID: lineID),
              let word = CaptionSelection.word(at: offset, in: line) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        showingVeilHint = false
        setSelection(word)
    }

    private func setSelection(_ new: CaptionSelection) {
        selection = new
        showingVeilHint = false   // the hint is about the dim; while selecting it would sit on her words
        copyTiming.selectionChanged(at: Date(), isEmpty: new.isEmpty(in: model.stream.lines))
        // Copy shows once the selection has rested for half a second; a later change just moves it.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(CopyButtonTiming.settle + 0.02))
            withAnimation(Fluid.quick(reduceMotion)) { _ = copyTiming.update(now: Date()) }
        }
    }

    private func clearSelection() {
        guard selection != nil else { return }
        // The highlight, handles and [ Copy ] fade together; before the fluidity pass they vanished at once.
        withAnimation(Fluid.quick(reduceMotion)) {
            selection = nil
            copyTiming.selectionChanged(at: Date(), isEmpty: true)
        }
        dragAnchor = nil
        if following { position.scrollTo(edge: .bottom) }   // catch up on what arrived while selecting
    }

    private func copySelection() {
        guard let selection else { return }
        UIPasteboard.general.string = selection.copyText(lines: model.stream.lines, speakerNames: model.speakerNames)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        clearSelection()
    }

    /// VoiceOver's "Copy" on a caption: the whole line, with its speaker, as the transcript export writes it.
    private func copyLine(_ line: CaptionLine) {
        UIPasteboard.general.string = TranscriptFormatter.speakerPrefix(for: line, speakerNames: model.speakerNames) + line.text
    }

    /// The two ends of the selection as carets in the caption viewport, or nil while either is off screen.
    private func selectionEnds() -> (start: CGRect, end: CGRect)? {
        let lines = model.stream.lines
        guard let selection, let r = selection.resolved(in: lines) else { return nil }
        func caret(_ index: Int, _ offset: Int) -> CGRect? {
            let line = lines[index]
            guard let frame = textFrames.captionFrame(line.id),
                  let caret = glyphs.caret(at: min(offset, line.text.utf16.count), lineID: line.id) else { return nil }
            return caret.offsetBy(dx: frame.minX, dy: frame.minY)
        }
        guard let start = caret(r.startLine, r.startOffset), let end = caret(r.endLine, r.endOffset) else { return nil }
        return (start, end)
    }

    /// Which handle a finger at this point is on, with a generous target (44 pt, the minimum for a touch target).
    private func handle(near point: CGPoint) -> SelectionHandle.Edge? {
        guard let ends = selectionEnds() else { return nil }
        func target(_ caret: CGRect, _ edge: SelectionHandle.Edge) -> CGRect {
            let knob = SelectionHandle.knob
            let tall = CGRect(x: caret.minX, y: edge == .start ? caret.minY - knob : caret.minY,
                              width: 0, height: caret.height + knob)
            return tall.insetBy(dx: -22, dy: -12)
        }
        if target(ends.end, .end).contains(point) { return .end }
        if target(ends.start, .start).contains(point) { return .start }
        return nil
    }

    /// Dragging a handle: the other end stays put and this one follows the finger, across lines.
    private func dragHandle(_ location: CGPoint, finished: Bool) {
        let lines = model.stream.lines
        if finished { dragAnchor = nil; draggingEdge = nil; return }
        guard let selection, let r = selection.resolved(in: lines) else { return }
        if dragAnchor == nil {
            let start = CaptionPosition(lineID: lines[r.startLine].id, offset: r.startOffset)
            let end = CaptionPosition(lineID: lines[r.endLine].id, offset: r.endOffset)
            dragAnchor = draggingEdge == .start ? end : start
        }
        guard let anchor = dragAnchor, let hit = textFrames.nearestCaptionLine(to: location),
              let offset = glyphs.offset(at: CGPoint(x: location.x - hit.frame.minX, y: location.y - hit.frame.minY), lineID: hit.id)
        else { return }
        let moved = CaptionSelection(anchor: anchor, focus: CaptionPosition(lineID: hit.id, offset: offset))
        if moved != selection, !moved.isEmpty(in: lines) { setSelection(moved) }
    }

    /// The handles at both ends and, once the selection has rested, one Copy button above it (mock-up 05).
    private var selectionChrome: some View {
        GeometryReader { geo in
            let _ = selectionScroll   // re-place on scroll
            if let ends = selectionEnds() {
                let handleColor = SelectionColors.handle(on: style.background).color
                SelectionHandle(edge: .start, caret: ends.start, color: handleColor)
                SelectionHandle(edge: .end, caret: ends.end, color: handleColor)
                if copyTiming.isShown {
                    // Above the first selected line (mock-up 05). If that's scrolled away, at the top of the visible
                    // selection: never below it, where it would cover words she hasn't selected.
                    let y = max(36, ends.start.minY - 46)
                    Button(action: copySelection) {
                        Label(String(localized: "Copy"), systemImage: "doc.on.doc")
                            .font(.title3.bold())
                            .padding(.horizontal, 26).padding(.vertical, 12)
                    }
                    .buttonStyle(GummyButtonStyle(style: style))
                    .accessibilityHint(String(localized: "Copies the selected words"))
                    .position(x: geo.size.width / 2, y: y)
                    .transition(.opacity)
                }
            }
        }
        .clipped()   // a handle on a line scrolled half away stays within the captions, never over the gear
    }

    private func speakerLabelRow(for state: SpeakerLabelState, speaker: Int?, palette: [Color], placeholderColor: Color) -> some View {
        switch state {
        case .none:
            return AnyView(EmptyView())
        case .pending:
            return AnyView(
                Text(String(localized: "Speaker"))
                    .font(.headline)
                    .foregroundStyle(placeholderColor)
            )
        case .resolved(let sp):
            let displayText = model.speakerNames.name(for: sp) ?? String(localized: "Speaker \(sp + 1)")
            return AnyView(
                Text(displayText)
                    .font(.headline)
                    .foregroundStyle(palette[sp % palette.count])
                    .accessibilityLabel(displayText)
            )
        case .unknown:
            return AnyView(
                Text(String(localized: "Speaker unknown"))
                    .font(.headline)
                    .foregroundStyle(placeholderColor)
            )
        }
    }

    private func soundLabelA11yLabel(for label: SoundLabelKind) -> String {
        switch label {
        case .laughter: "Laughter sound"
        case .applause: "Applause sound"
        case .doorbell: "Doorbell sound"
        case .phoneRinging: "Phone ringing sound"
        case .knock: "Knock sound"
        }
    }

    private var developerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mic", selection: $model.micMode) {
                Text("Raw").tag(MicMode.raw)
                Text("Standard").tag(MicMode.standard)
                Text("Voice").tag(MicMode.voiceProcessing)
            }
            .pickerStyle(.segmented)
            .disabled(model.state == .listening || model.state == .preparing)
            Picker("Engine", selection: $model.engineChoice) {
                Text("Parakeet").tag(CaptionEngineChoice.parakeet)
                Text("Apple").tag(CaptionEngineChoice.apple)
            }
            .pickerStyle(.segmented)
            .disabled(model.state == .listening || model.state == .preparing)
            if model.micMode == .voiceProcessing {
                Button("System mic modes (Voice Isolation)…") { AVCaptureDevice.showSystemUserInterface(.microphoneModes) }
                    .font(.footnote)
            }
            Button("Measure latency") { model.measureLatency() }
                .font(.footnote)
                .disabled(model.state == .listening || model.state == .preparing)
            if let lag = model.lag { Text("lag \(String(format: "%.1f", lag))s").font(.caption2) }
            if !model.startup.isEmpty { Text("startup: \(model.startup)").font(.caption2) }
            if let report = model.latencyReport { Text("LATENCY \(report)").font(.caption2) }
            if !model.diag.isEmpty { Text(model.diag).font(.caption2).opacity(0.7) }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Marks one caption (the newest spoken line) as the tour's caption target.
private struct TourTargetIf: ViewModifier {
    let target: TourSpot
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.tourTarget(target) } else { content }
    }
}

/// Holding the status word for 1.5 s opens the developer panel, in Xcode (debug) builds only: TestFlight and App Store
/// users can never open it (owner, PR #155). The panel pushes the captions down only while it's open.
private struct DeveloperHold: ViewModifier {
    let toggle: () -> Void

    func body(content: Content) -> some View {
        #if DEBUG
        content.onLongPressGesture(minimumDuration: 1.5, perform: toggle)
        #else
        content
        #endif
    }
}

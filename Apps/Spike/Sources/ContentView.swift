import AVFoundation
import CaptionCore
import SwiftUI
import UIKit

@MainActor
final class CaptionModel: ObservableObject {
    @Published var state: CaptionState = .idle
    @Published var stream = CaptionStream()
    @Published var lag: Double?
    @Published var diag = ""
    @Published var startup = ""
    @Published var micMode: MicMode = .standard
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
    /// Beta testers' ratings and measurements (ADR 0023). Every call is a no-op in an App Store install.
    let beta = BetaFeedbackCenter.shared
    /// A cold launch brought back a conversation; the beta card may be due once StoreKit has answered.
    private var restoredOnColdLaunch = false

    init() {
        controller = CaptionSessionController(makeEngine: { [weak self] in
            guard let self else { throw CancellationError() }
            // Loaded during the launch (or after the last pause), so Start is instant (#119).
            if let warm = EngineWarmupHost.shared.take(micMode: self.micMode) { return warm }
            guard let url = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") else {
                throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
            }
            let rawText = VocabularyStore().loadRawText()
            let vocabulary = VocabularyList(rawText: rawText).entries
            return TranscriptionEngine(micMode: self.micMode, diarizerModelURL: url, contextualStrings: vocabulary)
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
            self.stream.apply(text: u.text, isFinal: u.isFinal, speaker: u.speaker, range: range)
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
            // Pausing keeps the conversation on screen; nothing is saved until she taps [ Save ].
            stopActivityLoop()
            beta.captioningStopped(session, state: newState)
            EngineWarmupHost.shared.prepareIfAllowed(micMode: micMode) // the next Start is instant too (#119)
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
            try? await Task.sleep(nanoseconds: 700_000_000)
            showingSaveCheck = false
            // The tour's "Saved." waits until [ ✔ ] → [ Saved ] has played out (#121).
            try? await Task.sleep(nanoseconds: 350_000_000)
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

    /// Step 2's "That's you." comes a beat after the first caption, so she sees her words first.
    private var captionBeatPending = false
    private func reportCaptionShown() {
        guard tour.step == .captions, !captionBeatPending else { return }
        captionBeatPending = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(TourTiming.captionSeenSeconds))
            captionBeatPending = false
            tour.did(.captionShown)
        }
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

                // Throwaway pass.
                let warmupEngine = TranscriptionEngine(diarizerModelURL: modelURL)
                for try await _ in try await warmupEngine.startReplaying(fileURL: fixtureURL) {}

                // Measured pass.
                let engine = TranscriptionEngine(diarizerModelURL: modelURL)
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
                latencyReport = String(format: "Median: %.3f s, P95: %.3f s, First: %.3f s",
                                       report.medianLagSeconds,
                                       report.p95LagSeconds,
                                       report.timeToFirstCaptionSeconds ?? 0)
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
    @State private var shownScreen: AppScreen = .captions
    @State private var pageOpacity: Double = 1
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
            Group { landscape ? AnyView(landscapeLayout) : AnyView(portraitLayout) }
                .padding()
                .opacity(shownScreen == .captions ? pageOpacity : 0)
                .allowsHitTesting(shownScreen == .captions)
                .accessibilityHidden(shownScreen != .captions)
            if shownScreen != .captions {
                page(shownScreen)
                    .padding(.top, 8)
                    .opacity(pageOpacity)
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
            model.appActiveChanged(phase == .active)
            model.scenePhaseChanged(phase)
        }
        .task {
            guard DemoMode.isOn else { return }
            model.demoApplyPreset()
            if DemoMode.tour != nil { await runDemoTour(); return }
            if DemoMode.landscape, let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
            if DemoMode.seedsSaved { await seedDemoSaved() }
            model.runDemo()
            if DemoMode.opensSettings || DemoMode.settingsPush != nil {
                // Debug only: open straight on Settings (or one of its pages) for screenshots, no fade.
                nav.gearTapped()
                switch DemoMode.settingsPush {
                case "saved", "deleteall": nav.open(.saved)
                case "credits": nav.open(.credits)
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

    /// Changes the page: the current page fades out, then the next fades in (about 0.25 s each, spec "Round 2").
    private func go(_ change: (inout ScreenNavigator) -> Void) {
        var next = nav
        change(&next)
        guard next != nav else { return }
        nav = next
        let half = PageFade.half(reduceMotion: reduceMotion)
        withAnimation(.easeInOut(duration: half)) { pageOpacity = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(half))
            shownScreen = nav.current
            withAnimation(.easeInOut(duration: half)) { pageOpacity = 1 }
        }
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
                                 try? await Task.sleep(for: .seconds(PageFade.half(reduceMotion: reduceMotion) * 2))
                                 withAnimation(veilAnimation) { model.tour.begin() }
                             }
                         },
                         onGear: {
                             model.tour.did(.closedSettings)
                             go { $0.gearTapped() }
                         },
                         onOpen: { screen in go { $0.open(screen) } })
        case .saved:
            if let store = model.store {
                SavedConversationsPage(store: store, style: style, onBack: { go { $0.back() } },
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
                HStack { settingsButton; Spacer() }
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
        .buttonStyle(.plain)
        .tourTarget(.gear)
        .accessibilityLabel(String(localized: "Settings"))
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
            Text(statusHeadline)
                .font(.subheadline.weight(.semibold))
                .opacity(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .onLongPressGesture(minimumDuration: 1.5) { developerTools.toggle() }
        }
        .padding(.horizontal, 52)   // never under the gear
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func renderStatusDot(_ dot: StatusDot) -> some View {
        switch dot {
        case .pulsing(let level):
            let opacity = (level + 60) / 30.0
            Circle()
                .fill(style.text.color)
                .opacity(opacity * 0.8)
                .frame(width: 8, height: 8)
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
        let newestSpokenLineID = lines.last(where: { !$0.isSoundLabel && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })?.id
        func selected(_ line: CaptionLine) -> Range<Int>? {
            guard let resolved, let i = lineIndex[line.id] else { return nil }
            return resolved.range(forLineAt: i, length: line.text.utf16.count)
        }
        return ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
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
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 56)
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
                .animation(.easeInOut(duration: 0.25), value: following)
            }

            if selection != nil { selectionChrome }

            if model.veil.isVisible(state: model.state, hasConversation: model.hasConversation) {
                pauseVeil.transition(.opacity)
            }

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
            await wait(2); withAnimation(.easeInOut(duration: 0.2)) { model.save() }
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
        case "failed": model.demoSetState(.failed(String(localized: "The microphone stopped. Tap Start captions to try again.")))
        case "quiet": model.demoSetState(.pausedQuiet(minutes: 5))
        case "tour4save":
            // [ Save ] while the tour is on step 4: [ ✔ ] → [ Saved ] plays out, then "Saved." fades in (#121).
            model.demoSetState(.idle)
            model.tour = HowToUseTour(step: .save)
            await wait(2.5); withAnimation(.easeInOut(duration: 0.2)) { model.save() }
        case "savebeta":
            // A beta install (Xcode counts), no tour: pause, [ Save ], then [ New ].
            await BetaFeedbackCenter.shared.ensureResolved()
            model.demoSetState(.listening)
            await wait(1); model.demoSetState(.idle)
            await wait(2); withAnimation(.easeInOut(duration: 0.2)) { model.save() }
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

    private var veilAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.2 : 0.35) }

    /// The dim over a paused conversation: the captions fade toward the theme's own background (about 86%, mock-up
    /// 02) and [ Save ] sits over [ New ], centered, each on a plain patch of background so faded words never show
    /// through the letters. One tap on the dim clears it to scroll and copy.
    private var pauseVeil: some View {
        ZStack {
            style.background.color.opacity(0.86)
                .contentShape(Rectangle())
                .onTapGesture { clearVeil() }
                .tourTarget(.veil)
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Paused conversation"))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(String(localized: "Double tap to show the conversation"))
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
                    saveButton.tourTarget(.save)
                    retroButton(String(localized: "New"), color: style.text.color,
                                label: String(localized: "Start a new conversation")) { withAnimation(veilAnimation) { model.requestNew() } }
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        let green = SavedGreen.color(on: style.background).color
        if model.showingSaveCheck {
            retroButton(Self.checkMark, color: green, label: String(localized: "Saved"), action: nil)
        } else {
            switch model.session.saveButton(lines: model.stream.lines, names: model.speakerNames) {
            case .save:
                retroButton(String(localized: "Save"), color: style.text.color, label: String(localized: "Save conversation")) {
                    withAnimation(.easeInOut(duration: 0.2)) { model.save() }
                }
            case .saved:
                retroButton(String(localized: "Saved"), color: green, label: String(localized: "Conversation saved"), action: nil)
            case .unavailable:
                EmptyView()
            }
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
        if step == .captions && new.phase == .waiting && old.step != .captions { scheduleExampleOffer() }
        if new.phase == .followUp && (old.phase != .followUp || old.step != step) {
            let phaseStep = step
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(TourTiming.followUpSeconds(for: phaseStep)))
                guard model.tour.step == phaseStep, model.tour.phase == .followUp else { return }
                withAnimation(veilAnimation) { model.tour.did(.followUpRead) }
            }
        }
    }

    /// Back to a step whose action already happened: put the screen back the way that step needs it, using the same
    /// calls the real controls make (the tour ignores them, since they aren't the step's own action).
    private func prepareAfterBack(for step: TourStep) {
        let listening = model.state == .listening || model.state == .preparing
        switch step {
        case .start:
            if listening { model.perform(.stop) }
        case .captions, .pause:
            if !listening { model.perform(.start) }
        case .save, .clearDim:
            if !model.veil.isVisible(state: model.state, hasConversation: model.hasConversation) { bringBackVeil() }
            if step == .save, model.session.saveButton(lines: model.stream.lines, names: model.speakerNames) == .saved {
                model.tour.alreadySaved()
            }
        case .holdBack:
            if model.veil.isVisible(state: model.state, hasConversation: model.hasConversation) { clearVeil() }
        case .gear, .done:
            break
        }
    }

    /// A quiet room: after a few seconds of captioning with nothing to show, step 2 offers [ Show an example ].
    private func scheduleExampleOffer() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(TourExample.quietSeconds))
            guard model.tour.step == .captions, model.tour.phase == .waiting, !model.hasConversation else { return }
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
            let followUp = pin.hasSuffix("b")
            guard let n = Int(pin.filter(\.isNumber)), let target = TourStep(rawValue: n - 1) else { return }
            // A still of one step, with the screen set up the way she'd reach it.
            if target.rawValue >= TourStep.captions.rawValue { model.demoSetState(.preparing); model.demoSetState(.listening) }
            if target.rawValue > TourStep.captions.rawValue || (target == .captions && followUp) { model.showTourExample() }
            if target.rawValue >= TourStep.save.rawValue { model.demoSetState(.idle) }
            if target.rawValue > TourStep.save.rawValue || (target == .save && followUp) { model.save() }
            await wait(1.6)
            if target == .holdBack { clearVeil() }
            if target == .gear { showingVeilHint = false }
            let phase: TourPhase = followUp ? .followUp : .waiting
            model.tour = HowToUseTour(step: target, phase: phase)
            return
        }
        model.tour.begin()
        await wait(3)
        start()                                                    // 1: Start captions
        await wait(2.5)
        withAnimation { model.showTourExample() }                  // 2: words appear, then "That's you."
        await wait(TourTiming.captionSeenSeconds + TourTiming.followUpSeconds(for: .captions) + 0.6)
        stop()                                                     // 3: the X pauses
        await wait(3)
        withAnimation(.easeInOut(duration: 0.2)) { model.save() }  // 4: [ Save ] -> [ Saved ], then "Saved."
        await wait(1.2 + TourTiming.followUpSeconds(for: .save) + 0.6)
        clearVeil()                                                // 5: a tap on the dim clears it
        await wait(3)
        bringBackVeil()                                            // 6: holding an empty spot brings it back
        await wait(3)
        model.tour.did(.openedSettings); go { $0.gearTapped() }    // 7: the gear, Settings fades in...
        await wait(3)
        model.tour.did(.closedSettings); go { $0.gearTapped() }    //    ...and the gear again comes back
        await wait(4.5)
        withAnimation(veilAnimation) { model.tour.did(.tappedDone) } // 8: [ Done ]
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
            withAnimation(.easeOut(duration: 0.2)) { _ = copyTiming.update(now: Date()) }
        }
    }

    private func clearSelection() {
        guard selection != nil else { return }
        selection = nil
        dragAnchor = nil
        copyTiming.selectionChanged(at: Date(), isEmpty: true)
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

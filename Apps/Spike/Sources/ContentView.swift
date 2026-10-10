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
    @Published var confirmingNew = false
    /// The on-screen conversation, written to the phone while she's in another app.
    private var currentStore: CurrentConversationStore?
    private var tracker = ListeningActivityTracker()
    /// ADR 0019: read by the controller on every tick, so a change in Settings applies mid-session.
    @Published var idleStop: IdleStopSetting = IdleStopStore().load() {
        didSet { IdleStopStore().save(idleStop) }
    }
    private let screenAwake = ScreenAwakeKeeper(apply: { UIApplication.shared.isIdleTimerDisabled = $0 })

    init() {
        controller = CaptionSessionController(makeEngine: { [weak self] in
            guard let self else { throw CancellationError() }
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
            }
        }

        controller.onStateChange = { [weak self] in self?.handleCaptionStateChange($0) }
        controller.onStartup = { [weak self] in self?.startup = $0 }
        controller.onSoundLabel = { [weak self] in self?.stream.insertSoundLabel($0) }
        controller.onAudioLevel = { [weak self] level in
            self?.roomLevelDBFS = level
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
            }
        }
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
        case .idle, .failed, .pausedQuiet:
            // Pausing keeps the conversation on screen; nothing is saved until she taps [ Save ].
            stopActivityLoop()
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
        showingSaveCheck = true
        Task {
            do {
                try await store?.save(conversation)
                try await store?.purgeExpired(now: Date())
            } catch {
                session = before
                diag = "Save failed: \(error)"
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            showingSaveCheck = false
        }
    }

    /// [ New ]: asks first if the conversation isn't saved as it stands.
    func requestNew() {
        if session.hasUnsavedChanges(lines: stream.lines, names: speakerNames) { confirmingNew = true } else { startNew() }
    }

    func startNew() {
        stream = CaptionStream()
        speakerNames = SpeakerNames()
        session = ConversationSession()
        veil = PauseVeil()
        showingSaveCheck = false
        currentStore?.delete()
    }

    /// Leaving for another app: keep the conversation on the phone in case iOS closes Seal meanwhile. Back on
    /// screen it's in memory again, so the file goes.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if hasConversation {
                try? currentStore?.save(CurrentConversationSnapshot(lines: stream.lines, names: speakerNames, session: session, leftAt: Date()))
            } else {
                currentStore?.delete()
            }
        case .active:
            currentStore?.delete()
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
        case .start: controller.start()
        case .stop: controller.stop()
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
    /// Developer-only tools (mic mode, diagnostics). Long-press the status text to toggle; never shown by default.
    @State private var developerTools = false
    /// Debug only (DemoMode `-ClarityDemoFlow start`): presses the Start pill without a finger.
    @State private var demoPressingStart = false
    @State private var showingSettings = false
    @State private var position = ScrollPosition(edge: .bottom)
    /// Following the newest caption. Stops only when the user drags away; resumes at the bottom or via "Jump to latest".
    @State private var following = true
    @State private var userDragging = false
    /// Tracks when the preparing state began, for the animation minimum-duration overlay.
    @State private var preparingStartTime: Date?
    /// Controls the animation overlay visibility after leaving the preparing state.
    @State private var showPreparingAnimation = false
    /// Bumped on every state change so a pending "show the animation" can tell it has been overtaken.
    @State private var preparingToken = 0
    @State private var animationShownAt: Date?
    /// Show the one-time speaker explanation banner.
    @State private var showingSpeakerBanner = false
    /// Speaker index currently being renamed, or nil if no rename dialog is open.
    @State private var renamingSpeaker: Int?
    /// Draft name being edited in the rename dialog.
    @State private var nameDraft: String = ""
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
            Group { landscape ? AnyView(landscapeLayout) : AnyView(portraitLayout) }
                .padding()
            if showPreparingAnimation {
                ZStack {
                    style.background.color.ignoresSafeArea()
                    LaunchAnimationView()
                }
                .transition(.opacity)
            }
        }
        // One look for the whole app: background, text, controls and the system's own chrome all follow it.
        .foregroundStyle(style.text.color)
        .tint(style.text.color)
        .preferredColorScheme(style.background.isDark ? .dark : .light)
        .animation(.snappy, value: control.presentation)
        .onChange(of: scenePhase) { _, phase in
            model.appActiveChanged(phase == .active)
            model.scenePhaseChanged(phase)
        }
        .alert(String(localized: "Start a new conversation?"), isPresented: $model.confirmingNew) {
            Button(String(localized: "Start new"), role: .destructive) { withAnimation(veilAnimation) { model.startNew() } }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This conversation isn't saved."))
        }
        .sheet(isPresented: $showingSettings) { SettingsSheet(style: $model.style, idleStop: $model.idleStop, stream: model.stream, speakerNames: model.speakerNames, store: model.store) }
        .task {
            guard DemoMode.isOn else { return }
            model.demoApplyPreset()
            if DemoMode.landscape, let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
            model.runDemo()
            if DemoMode.opensSettings { showingSettings = true }
            await runDemoPause()
        }
        .onChange(of: model.state) { _, newState in
            UIAccessibility.post(notification: .announcement, argument: StatusWords.announcement(for: newState))
            handleStateChange(newState)
        }
    }

    /// The branded animation only appears if getting ready is genuinely slow (a cold start, a download); a quick
    /// start is just the control morphing, so there is no flash. Once shown it never flickers.
    private func handleStateChange(_ newState: CaptionState) {
        preparingToken += 1
        let token = preparingToken
        switch newState {
        case .preparing:
            showingVeilHint = false
            preparingStartTime = Date()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(LaunchAnimationGate.showDelay * 1_000_000_000))
                guard token == preparingToken, model.state == .preparing else { return }   // it started fast: never show it
                animationShownAt = Date()
                withAnimation(.easeInOut(duration: 0.25)) { showPreparingAnimation = true }
            }
        case .listening, .idle, .failed, .pausedQuiet:
            preparingStartTime = nil
            guard showPreparingAnimation else { return }
            let shown = animationShownAt.map { Date().timeIntervalSince($0) } ?? LaunchAnimationGate.minimumDuration
            let wait = LaunchAnimationGate.remainingDelay(elapsed: shown)
            Task {
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                withAnimation(.easeInOut(duration: 0.25)) { showPreparingAnimation = false }
                animationShownAt = nil
            }
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
        Button { showingSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.title2)
                .foregroundStyle(gearColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                                    .onAppear {
                                        if labelState == .pending && !showingSpeakerBanner && !SpeakerExplanationStore().hasSeen {
                                            showingSpeakerBanner = true
                                        }
                                    }
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
                        .accessibilityElement(children: .contain)
                        .accessibilityAction(named: String(localized: "Copy")) { copyLine(line) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                }
            }
            .coordinateSpace(.named(TextFrames.space))
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
                if !following {
                    Button {
                        following = true
                        withAnimation { position.scrollTo(edge: .bottom) }
                    } label: { Label("Jump to latest", systemImage: "arrow.down.circle.fill").font(.title3.bold()).padding(.horizontal, 8).frame(minHeight: 48) }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(style.background.color)
                        .padding(.bottom, 8)
                }
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

            if showingSpeakerBanner {
                VStack(spacing: 12) {
                    Text(SpeakerExplanation.sentence)
                        .font(.callout)
                    HStack {
                        Button("Got it") {
                            SpeakerExplanationStore().markSeen()
                            showingSpeakerBanner = false
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(style.text.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .padding()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(veilAnimation, value: model.veil.isVisible(state: model.state, hasConversation: model.hasConversation))
        .accessibilityAction(named: String(localized: "Show Save and New")) { bringBackVeil() }
        .alert(String(localized: "Name this speaker"), isPresented: Binding(
            get: { renamingSpeaker != nil },
            set: { if !$0 { renamingSpeaker = nil; nameDraft = "" } }
        )) {
            TextField(String(localized: "Speaker name"), text: $nameDraft)
            Button(String(localized: "Save")) {
                if let sp = renamingSpeaker {
                    model.speakerNames.apply(nameDraft, to: sp)
                    renamingSpeaker = nil
                    nameDraft = ""
                }
            }
            Button(String(localized: "Clear Name")) {
                if let sp = renamingSpeaker {
                    model.speakerNames.clear(speaker: sp)
                    renamingSpeaker = nil
                    nameDraft = ""
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                renamingSpeaker = nil
                nameDraft = ""
            }
        } message: {
            Text(String(localized: "Enter a custom name for this speaker"))
        }
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
            await wait(0.25); model.demoSetState(.preparing); model.demoSetState(.listening)
            await wait(3); model.demoSetState(.idle)
        case "new":
            model.demoSetState(.idle)
            await wait(2); model.requestNew()
            await wait(3); model.confirmingNew = false; withAnimation(veilAnimation) { model.startNew() }
        default:
            break
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
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Paused conversation"))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(String(localized: "Double tap to show the conversation"))
            VStack(spacing: 24) {
                saveButton
                retroButton(String(localized: "New"), color: style.text.color,
                            label: String(localized: "Start a new conversation")) { model.requestNew() }
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

    /// The retro, literal-text buttons: [ Save ], [ ✔ ], [ Saved ], [ New ]. A nil action shows the state only.
    /// Without an action it's plain text, not a disabled button: a disabled button is dimmed, and [ Saved ] must
    /// stay solid green on a solid patch.
    @ViewBuilder
    private func retroButton(_ word: String, color: Color, label: String, action: (() -> Void)?) -> some View {
        // The brackets are the retro frame, not words; the word inside is already localized.
        let text = Text(verbatim: "[ \(word) ]")
            .font(.system(.title, design: .monospaced).bold())
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(style.background.color)
            .contentShape(Rectangle())
            .contentTransition(.opacity)
        if let action {
            Button(action: action) { text }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
        } else {
            text.accessibilityLabel(label)
        }
    }

    private static let checkMark = "✔"
    private static let veilHintLimit = 3
    private static let veilHintKey = "pauseVeilHintCount"

    private func clearVeil() {
        withAnimation(veilAnimation) { model.veil.tap(state: model.state) }
        let shown = UserDefaults.standard.integer(forKey: Self.veilHintKey)
        guard shown < Self.veilHintLimit else { return }
        UserDefaults.standard.set(shown + 1, forKey: Self.veilHintKey)
        withAnimation(veilAnimation) { showingVeilHint = true }
    }

    private func bringBackVeil() {
        withAnimation(veilAnimation) {
            model.veil.holdOnEmptySpace(state: model.state)
            showingVeilHint = false
        }
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
                    .onTapGesture {
                        renamingSpeaker = sp
                        nameDraft = model.speakerNames.name(for: sp) ?? ""
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(displayText)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(String(localized: "Double tap to name this speaker"))
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

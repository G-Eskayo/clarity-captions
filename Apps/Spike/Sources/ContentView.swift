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
    private var sessionStartedAt: Date?
    private var tracker = ListeningActivityTracker()

    init() {
        controller = CaptionSessionController(makeEngine: { [weak self] in
            guard let self else { throw CancellationError() }
            guard let url = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") else {
                throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
            }
            let rawText = VocabularyStore().loadRawText()
            let vocabulary = VocabularyList(rawText: rawText).entries
            return TranscriptionEngine(micMode: self.micMode, diarizerModelURL: url, contextualStrings: vocabulary)
        })

        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let conversationsDir = appSupportURL.appendingPathComponent("SavedConversations")
            self.store = try? SavedConversationStore(directory: conversationsDir)
            Task { try? await self.store?.purgeExpired(now: Date()) }
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

    private func handleCaptionStateChange(_ newState: CaptionState) {
        state = newState

        switch newState {
        case .preparing:
            sessionStartedAt = Date()
        case .listening:
            startActivityLoop()
        case .idle, .failed:
            stopActivityLoop()
            saveSessionIfNeeded()
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

    private func saveSessionIfNeeded() {
        let action = CaptionSessionLifecycle.action(for: state, sessionStartedAt: sessionStartedAt, lines: stream.lines, speakerNames: speakerNames)

        Task {
            switch action {
            case .save(let conversation):
                do {
                    try await store?.save(conversation)
                    try await store?.purgeExpired(now: Date())
                } catch {
                    diag = "Save failed: \(error)"
                }
            case .discard:
                break
            case .none:
                break
            }
            resetSession()
        }
    }

    private func resetSession() {
        stream = CaptionStream()
        speakerNames = SpeakerNames()
        sessionStartedAt = nil
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

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .sheet(isPresented: $showingSettings) { SettingsSheet(style: $model.style, stream: model.stream, speakerNames: model.speakerNames, store: model.store) }
        .task {
            guard DemoMode.isOn else { return }
            model.runDemo()
            if DemoMode.opensSettings { showingSettings = true }
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
            preparingStartTime = Date()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(LaunchAnimationGate.showDelay * 1_000_000_000))
                guard token == preparingToken, model.state == .preparing else { return }   // it started fast: never show it
                animationShownAt = Date()
                withAnimation(.easeInOut(duration: 0.25)) { showPreparingAnimation = true }
            }
        case .listening, .idle, .failed:
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

    /// Portrait: Settings sits in the top row; while captioning, Stop is a small circle at the bottom right,
    /// and the bottom button row only exists when it is a big Start / Try again, so captions get the space.
    private var portraitLayout: some View {
        VStack(spacing: 20) {
            HStack {
                settingsButton
                Spacer()
            }
            status(font: .largeTitle)
            if developerTools { developerPanel }
            // Captions use the full height. The one morphing control floats over the bottom edge, and the scroll
            // content keeps a margin below the newest line so it never sits under the control.
            captions(bottomReserve: 72 + 24)
        }
        .overlay(alignment: .bottom) { controlBar(pillWidth: nil) }
    }

    /// Landscape: a thin top bar (state in the middle, Settings at the right), captions across everything
    /// below it, and the stop / start control in the bottom-right corner, so text gets the most room.
    private var landscapeLayout: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                ZStack {
                    status(font: .title3)
                    HStack { Spacer(); settingsButton }
                }
                // Leave the corner free so the control never sits on top of text.
                captions().padding(.trailing, control.presentation == .compact ? PrimaryControl.compactDiameter + 16 : 236)
            }
            controlBar(pillWidth: 220)
        }
        .overlay(alignment: .bottomLeading) { if developerTools { developerPanel.frame(maxWidth: 360) } }
    }

    /// The single bottom control, right-aligned so it shrinks toward the bottom-right corner and grows back out.
    /// `pillWidth` nil means the full row (portrait).
    private func controlBar(pillWidth: CGFloat?) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                MorphingControl(control: control, fullWidth: pillWidth ?? geo.size.width,
                                fill: style.text.color, label: style.background.color) {
                    model.perform(control.action)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 72)
    }

    private var settingsButton: some View {
        Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape").font(.headline) }
            .buttonStyle(.bordered)
    }

    private func status(font: Font) -> some View {
        let headline: String
        let detail: String?
        if let activity = model.activity {
            headline = StatusWords.headline(for: model.state, activity: activity)
            detail = StatusWords.secondLine(for: model.state, activity: activity)
        } else {
            headline = StatusWords.headline(for: model.state)
            detail = StatusWords.detail(for: model.state)
        }

        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(headline)
                    .font(font.bold())
                    .onLongPressGesture(minimumDuration: 1.5) { developerTools.toggle() }
                if let activity = model.activity, case .listening = model.state {
                    let dot = StatusDot.select(state: model.state, activity: activity, roomLevelDBFS: model.roomLevelDBFS)
                    renderStatusDot(dot)
                }
                Spacer()
            }
            if let detail {
                Text(detail).font(.footnote).opacity(0.7)
            }
        }
        .accessibilityElement(children: .combine)
        .onChange(of: model.activity) { _, newActivity in
            if let activity = newActivity {
                UIAccessibility.post(notification: .announcement, argument: StatusWords.announcement(for: model.state, activity: activity))
            }
        }
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
        return ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.stream.lines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            let labelState = SpeakerLabeling.state(for: line)
                            if labelState != .none {
                                speakerLabelRow(for: labelState, speaker: line.speaker, palette: palette, placeholderColor: placeholderColor)
                                    .onAppear {
                                        if labelState == .pending && !showingSpeakerBanner && !SpeakerExplanationStore().hasSeen {
                                            showingSpeakerBanner = true
                                        }
                                    }
                            }
                            if line.isSoundLabel {
                                Text(line.text).font(style.font(for: SystemTextSizeCategory(dynamicTypeSize), device: deviceClass).italic()).opacity(line.isFinal ? 1 : CaptionLine.volatileOpacity)
                                    .accessibilityLabel(line.soundLabel.map { soundLabelA11yLabel(for: $0) } ?? "")
                            } else {
                                Text(line.text).font(style.font(for: SystemTextSizeCategory(dynamicTypeSize), device: deviceClass)).opacity(line.isFinal ? 1 : CaptionLine.volatileOpacity)
                                    .textSelection(.enabled)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                }
            }
            .scrollPosition($position)
            .contentMargins(.bottom, bottomReserve, for: .scrollContent)
            .onScrollPhaseChange { _, phase in userDragging = (phase == .interacting || phase == .decelerating) }
            .onScrollGeometryChange(for: Bool.self) { g in
                AutoScroll.shouldFollow(offsetY: g.contentOffset.y, viewportHeight: g.containerSize.height, contentHeight: g.contentSize.height)
            } action: { _, atBottom in
                if atBottom { following = true } else if userDragging { following = false }
            }
            .onChange(of: model.stream.lines) { if following { position.scrollTo(edge: .bottom) } }
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

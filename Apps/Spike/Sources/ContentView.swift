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
    /// Only used by the developer latency measurement below.
    private var task: Task<Void, Never>?
    private var controller: CaptionSessionController!

    init() {
        controller = CaptionSessionController(makeEngine: { [weak self] in
            guard let self else { throw CancellationError() }
            guard let url = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") else {
                throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
            }
            return TranscriptionEngine(micMode: self.micMode, diarizerModelURL: url)
        })
        controller.onStateChange = { [weak self] in self?.state = $0 }
        controller.onStartup = { [weak self] in self?.startup = $0 }
        controller.onSoundLabel = { [weak self] in self?.stream.insertSoundLabel($0) }
        controller.onUpdate = { [weak self] u in
            guard let self else { return }
            var range: ClosedRange<Double>?
            if let a = u.startSeconds, let b = u.endSeconds, a <= b { range = a...b }
            self.stream.apply(text: u.text, isFinal: u.isFinal, speaker: u.speaker, range: range)
            if let l = u.lagSeconds { self.lag = l }
            self.diag = u.diagnostics
        }
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

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var style: CaptionStyle { model.style }
    private var control: PrimaryControl { PrimaryControl.for(model.state) }
    private var landscape: Bool { verticalSizeClass == .compact }

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
        .sheet(isPresented: $showingSettings) { SettingsSheet(style: $model.style) }
        .onChange(of: model.state) { _, newState in
            UIAccessibility.post(notification: .announcement, argument: StatusWords.announcement(for: newState))
            handleStateChange(newState)
        }
    }

    private func handleStateChange(_ newState: CaptionState) {
        switch newState {
        case .preparing:
            preparingStartTime = Date()
            showPreparingAnimation = true
        case .listening:
            if let startTime = preparingStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                let delay = LaunchAnimationGate.remainingDelay(elapsed: elapsed)
                if delay > 0 {
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        withAnimation { showPreparingAnimation = false }
                    }
                } else {
                    showPreparingAnimation = false
                }
            }
            preparingStartTime = nil
        case .idle, .failed:
            showPreparingAnimation = false
            preparingStartTime = nil
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
            // Captions use the full height; the stop circle floats at the bottom right, and the scroll content
            // keeps a margin below the newest line so it never sits under the circle.
            captions(bottomReserve: control.presentation == .compact ? PrimaryControl.compactDiameter + 20 : 0)
                .overlay(alignment: .bottomTrailing) { if control.presentation == .compact { compactStop } }
            if developerTools { developerPanel }
            if control.presentation == .large { largeButton }
        }
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
            if control.presentation == .compact { compactStop } else { largeButton.frame(width: 220) }
        }
        .overlay(alignment: .bottomLeading) { if developerTools { developerPanel.frame(maxWidth: 360) } }
    }

    /// The small circle with an X that Stop becomes while captioning.
    private var compactStop: some View {
        Button { model.perform(.stop) } label: {
            Image(systemName: "xmark")
                .font(.title2.bold())
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(.white)
                .frame(width: PrimaryControl.compactDiameter, height: PrimaryControl.compactDiameter)
                .background(Color(red: 0.80, green: 0.12, blue: 0.12), in: Circle())
        }
        .accessibilityLabel(control.accessibilityLabel)
        .transition(.scale.combined(with: .opacity))
    }

    private var settingsButton: some View {
        Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape").font(.headline) }
            .buttonStyle(.bordered)
    }

    private func status(font: Font) -> some View {
        VStack(spacing: 4) {
            Text(StatusWords.headline(for: model.state))
                .font(font.bold())
                .onLongPressGesture(minimumDuration: 1.5) { developerTools.toggle() }
            if let detail = StatusWords.detail(for: model.state) {
                Text(detail).font(.footnote).opacity(0.7)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func captions(bottomReserve: CGFloat = 0) -> some View {
        let palette = SpeakerPalette.colors(on: style.background, text: style.text).map(\.color)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(model.stream.lines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        if let sp = line.speaker {
                            Text(String(localized: "Speaker \(sp + 1)")).font(.headline).foregroundStyle(palette[sp % palette.count])
                        }
                        if line.isSoundLabel {
                            Text(line.text).font(style.font(for: SystemTextSizeCategory(dynamicTypeSize)).italic()).opacity(line.isFinal ? 1 : CaptionLine.volatileOpacity)
                                .accessibilityLabel(line.soundLabel.map { soundLabelA11yLabel(for: $0) } ?? "")
                        } else {
                            Text(line.text).font(style.font(for: SystemTextSizeCategory(dynamicTypeSize))).opacity(line.isFinal ? 1 : CaptionLine.volatileOpacity)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
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

    /// The big Start / Try again / Getting ready button (Stop is the compact circle while captioning).
    private var largeButton: some View {
        Button { model.perform(control.action) } label: {
            Text(control.title)
                .font(.title.bold())
                .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.borderedProminent)
        // Filled in the text color with the label in the background color keeps the look's 7:1 contrast.
        .tint(style.text.color)
        .foregroundStyle(style.background.color)
        .disabled(!control.isEnabled)
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

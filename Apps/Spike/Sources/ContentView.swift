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
    private var engine: TranscriptionEngine?
    private var task: Task<Void, Never>?

    func perform(_ action: PrimaryControl.Action) {
        switch action {
        case .start: start()
        case .stop: stop()
        case .none: break
        }
    }

    private func start() {
        state = .preparing
        guard let modelURL = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") else {
            state = .failed("The speaker-labeling model is missing from this build.")
            return
        }
        let engine = TranscriptionEngine(micMode: micMode, diarizerModelURL: modelURL)
        self.engine = engine
        task = Task {
            do {
                let updates = try await engine.start()
                startup = engine.startupReport
                state = .listening
                for try await u in updates {
                    var range: ClosedRange<Double>?
                    if let a = u.startSeconds, let b = u.endSeconds, a <= b { range = a...b }
                    stream.apply(text: u.text, isFinal: u.isFinal, speaker: u.speaker, range: range)
                    if let l = u.lagSeconds { lag = l }
                    diag = u.diagnostics
                }
                state = .idle
            } catch {
                state = .failed(String(describing: error))
            }
            task = nil
        }
    }

    private func stop() {
        task?.cancel()
        Task { await engine?.stop(); state = .idle; task = nil }
    }
}

struct ContentView: View {
    @StateObject private var model = CaptionModel()
    /// Developer-only tools (mic mode, diagnostics). Long-press the status text to toggle; never shown by default.
    @State private var developerTools = false
    @State private var showingLook = false
    @State private var position = ScrollPosition(edge: .bottom)
    /// Following the newest caption. Stops only when the user drags away; resumes at the bottom or via "Jump to latest".
    @State private var following = true
    @State private var userDragging = false

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var style: CaptionStyle { model.style }
    private var control: PrimaryControl { PrimaryControl.for(model.state) }
    private var landscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            style.background.color.ignoresSafeArea()
            Group { landscape ? AnyView(landscapeLayout) : AnyView(portraitLayout) }
                .padding()
        }
        // One look for the whole app: background, text, controls and the system's own chrome all follow it.
        .foregroundStyle(style.text.color)
        .tint(style.text.color)
        .preferredColorScheme(style.background.isDark ? .dark : .light)
        .animation(.snappy, value: control.presentation)
        .sheet(isPresented: $showingLook) { LookSheet(style: $model.style) }
        .onChange(of: model.state) { _, newState in
            UIAccessibility.post(notification: .announcement, argument: StatusWords.announcement(for: newState))
        }
    }

    /// Portrait: Change look sits in the top row; while captioning, Stop is a small circle at the bottom right,
    /// and the bottom button row only exists when it is a big Start / Try again, so captions get the space.
    private var portraitLayout: some View {
        VStack(spacing: 20) {
            HStack {
                lookButton
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

    /// Landscape: a thin top bar (state in the middle, Change look at the right), captions across everything
    /// below it, and the stop / start control in the bottom-right corner, so text gets the most room.
    private var landscapeLayout: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                ZStack {
                    status(font: .title3)
                    HStack { Spacer(); lookButton }
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

    private var lookButton: some View {
        Button { showingLook = true } label: { Label("Change look", systemImage: "textformat.size").font(.headline) }
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
                            Text("Speaker \(sp + 1)").font(.headline).foregroundStyle(palette[sp % palette.count])
                        }
                        Text(line.text).font(style.font()).opacity(line.isFinal ? 1 : CaptionLine.volatileOpacity)
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
            if let lag = model.lag { Text("lag \(String(format: "%.1f", lag))s").font(.caption2) }
            if !model.startup.isEmpty { Text("startup: \(model.startup)").font(.caption2) }
            if !model.diag.isEmpty { Text(model.diag).font(.caption2).opacity(0.7) }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

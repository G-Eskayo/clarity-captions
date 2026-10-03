import AVFoundation
import CaptionCore
import SwiftUI

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
                    stream.apply(text: u.text, isFinal: u.isFinal, speaker: u.speaker)
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

    private var style: CaptionStyle { model.style }

    var body: some View {
        ZStack {
            style.background.color.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack { Spacer(); lookButton }
                status
                captions
                if developerTools { developerPanel }
                primaryButton
            }
            .padding()
        }
        // One look for the whole app: background, text, controls and the system's own chrome all follow it.
        .foregroundStyle(style.text.color)
        .tint(style.text.color)
        .preferredColorScheme(style.background.isDark ? .dark : .light)
        .sheet(isPresented: $showingLook) { LookSheet(style: $model.style) }
    }

    private var lookButton: some View {
        Button { showingLook = true } label: { Label("Change look", systemImage: "textformat.size").font(.headline) }
            .buttonStyle(.bordered)
    }

    private var status: some View {
        VStack(spacing: 4) {
            Text(StatusWords.headline(for: model.state))
                .font(.largeTitle.bold())
                .onLongPressGesture(minimumDuration: 1.5) { developerTools.toggle() }
            if let detail = StatusWords.detail(for: model.state) {
                Text(detail).font(.footnote).opacity(0.7)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var captions: some View {
        let palette = SpeakerPalette.colors(on: style.background, text: style.text).map(\.color)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(model.stream.lines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        if let sp = line.speaker {
                            Text("Speaker \(sp + 1)").font(.headline).foregroundStyle(palette[sp % palette.count])
                        }
                        Text(line.text).font(style.font()).opacity(line.isFinal ? 1 : 0.6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .scrollPosition($position)
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

    private var primaryButton: some View {
        let control = PrimaryControl.for(model.state)
        let stop = control.action == .stop
        return Button { model.perform(control.action) } label: {
            Text(control.title)
                .font(.title.bold())
                .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.borderedProminent)
        // Filled in the text color with label in the background color keeps the 7:1 contrast of the look; Stop is red with white.
        .tint(stop ? Color(red: 0.80, green: 0.12, blue: 0.12) : style.text.color)
        .foregroundStyle(stop ? Color.white : style.background.color)
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

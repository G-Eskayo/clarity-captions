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

    var body: some View {
        VStack(spacing: 20) {
            status
            captions
            if developerTools { developerPanel }
            primaryButton
        }
        .padding()
    }

    private var status: some View {
        VStack(spacing: 4) {
            Text(StatusWords.headline(for: model.state))
                .font(.largeTitle.bold())
                .foregroundStyle(statusColor)
                .onLongPressGesture(minimumDuration: 1.5) { developerTools.toggle() }
            if let detail = StatusWords.detail(for: model.state) {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var captions: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(model.stream.lines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        if let sp = line.speaker {
                            Text("Speaker \(sp + 1)").font(.headline).foregroundStyle(Self.color(for: sp))
                        }
                        Text(line.text).font(.title).opacity(line.isFinal ? 1 : 0.6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var primaryButton: some View {
        let control = PrimaryControl.for(model.state)
        return Button { model.perform(control.action) } label: {
            Text(control.title)
                .font(.title.bold())
                .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.borderedProminent)
        .tint(control.action == .stop ? .red : .accentColor)
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
            if !model.diag.isEmpty { Text(model.diag).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch model.state {
        case .failed: .red
        case .listening: .green
        default: .primary
        }
    }

    private static func color(for speaker: Int) -> Color {
        [Color.blue, .orange, .purple, .teal][speaker % 4]
    }
}

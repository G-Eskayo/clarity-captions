import AVFoundation
import CaptionCore
import SwiftUI

@MainActor
final class CaptionModel: ObservableObject {
    enum State: Equatable { case idle, preparing, listening, failed(String) }
    @Published var state: State = .idle
    @Published var stream = CaptionStream()
    @Published var lag: Double?
    @Published var diag = ""
    @Published var micMode: MicMode = .standard
    private var engine = TranscriptionEngine()
    private var task: Task<Void, Never>?

    func toggle() {
        if task != nil { stop() } else { start() }
    }

    private func start() {
        state = .preparing
        engine = TranscriptionEngine(micMode: micMode)
        task = Task {
            do {
                let updates = try await engine.start()
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
        Task { await engine.stop(); state = .idle; task = nil }
    }
}

struct ContentView: View {
    @StateObject private var model = CaptionModel()

    var body: some View {
        VStack(spacing: 16) {
            // A frozen screen must never look like a crashed app: state is always visible.
            Text(label).font(.headline).foregroundStyle(color)
            if !model.diag.isEmpty { Text(model.diag).font(.caption2).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.stream.lines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            if let sp = line.speaker {
                                Text("Speaker \(sp + 1)").font(.caption.bold()).foregroundStyle(Self.color(for: sp))
                            }
                            Text(line.text).font(.title).opacity(line.isFinal ? 1 : 0.6)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
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
            Button(model.state == .idle || isFailed ? "Start" : "Stop") { model.toggle() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }.padding()
    }

    private static func color(for speaker: Int) -> Color {
        [Color.blue, .orange, .purple, .teal][speaker % 4]
    }

    private var isFailed: Bool { if case .failed = model.state { true } else { false } }
    private var label: String {
        switch model.state {
        case .idle: "Not listening"
        case .preparing: "Getting ready…"
        case .listening: model.lag.map { "Listening · lag \(String(format: "%.1f", $0))s" } ?? "Listening"
        case .failed(let m): "Stopped: \(m)"
        }
    }
    private var color: Color { isFailed ? .red : (model.state == .listening ? .green : .secondary) }
}

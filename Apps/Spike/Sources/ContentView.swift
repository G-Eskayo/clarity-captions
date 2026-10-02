import CaptionCore
import SwiftUI

@MainActor
final class CaptionModel: ObservableObject {
    enum State: Equatable { case idle, preparing, listening, failed(String) }
    @Published var state: State = .idle
    @Published var stream = CaptionStream()
    private let engine = TranscriptionEngine()
    private var task: Task<Void, Never>?

    func toggle() {
        if task != nil { stop() } else { start() }
    }

    private func start() {
        state = .preparing
        task = Task {
            do {
                let updates = try await engine.start()
                state = .listening
                for try await u in updates { stream.apply(text: u.text, isFinal: u.isFinal) }
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.stream.lines) { line in
                        Text(line.text).font(.title).opacity(line.isFinal ? 1 : 0.6)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(model.state == .idle || isFailed ? "Start" : "Stop") { model.toggle() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }.padding()
    }

    private var isFailed: Bool { if case .failed = model.state { true } else { false } }
    private var label: String {
        switch model.state {
        case .idle: "Not listening"
        case .preparing: "Getting ready…"
        case .listening: "Listening"
        case .failed(let m): "Stopped: \(m)"
        }
    }
    private var color: Color { isFailed ? .red : (model.state == .listening ? .green : .secondary) }
}

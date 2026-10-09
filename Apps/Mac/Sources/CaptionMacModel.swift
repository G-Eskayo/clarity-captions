import Foundation
import SwiftUI
import CaptionCore

@MainActor
final class CaptionMacModel: ObservableObject {
    @Published var state: CaptionState = .idle
    @Published var stream = CaptionStream()
    @Published var style: CaptionStyle = CaptionStyleStore().load() {
        didSet { CaptionStyleStore().save(style) }
    }
    @Published var speakerNames = SpeakerNames()

    private var controller: CaptionSessionController!
    private var task: Task<Void, Never>?

    init() {
        controller = CaptionSessionController(makeEngine: { [weak self] in
            guard let self else { throw CancellationError() }
            guard let url = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") else {
                throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
            }
            let rawText = VocabularyStore().loadRawText()
            let vocabulary = VocabularyList(rawText: rawText).entries
            return TranscriptionEngine(micMode: .standard, diarizerModelURL: url, contextualStrings: vocabulary)
        })

        controller.onStateChange = { [weak self] in self?.state = $0 }
        controller.onSoundLabel = { [weak self] in self?.stream.insertSoundLabel($0) }
        controller.onUpdate = { [weak self] u in
            guard let self else { return }
            var range: ClosedRange<Double>?
            if let a = u.startSeconds, let b = u.endSeconds, a <= b { range = a...b }
            self.stream.apply(text: u.text, isFinal: u.isFinal, speaker: u.speaker, range: range)
        }
    }

    func start() {
        task = Task {
            try await controller.start()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        Task {
            await controller.stop()
        }
    }
}

import Foundation
import SwiftUI
import CaptionCore

/// What the window captions (#172). Until Gil picks the pop-up design (draft PR Decisions) there is no control for it:
/// `defaults write com.gileskayo.captions listenTo room|call|facetime`. Default: the call, as the ticket asks.
enum ListenTo: String {
    /// Every sound the Mac plays except Seal Speak's own: FaceTime, a Continuity phone call, Zoom, anything.
    case call
    /// Only FaceTime and its call service (narrower; which process plays the far side is unverified on a live call).
    case facetime
    /// The Mac's microphone, as before #172.
    case room

    static var current: ListenTo { ListenTo(rawValue: UserDefaults.standard.string(forKey: "listenTo") ?? "") ?? .call }

    func audioSource() -> AudioSource {
        switch self {
        case .call: ProcessTapAudioSource(target: .allSystemAudio)
        case .facetime: ProcessTapAudioSource(target: .apps(bundleIDs: CallApps.faceTime))
        case .room: MicAudioSource()
        }
    }
}

@MainActor
final class CaptionMacModel: ObservableObject {
    @Published var state: CaptionState = .idle
    @Published var stream = CaptionStream()
    @Published var style: CaptionStyle = CaptionStyleStore().load() {
        didSet { CaptionStyleStore().save(style) }
    }
    @Published var speakerNames = SpeakerNames()
    /// The pop-up stays above other windows (#172).
    @Published var pinned = true

    /// The caption lines as the pop-up draws them.
    var popupLines: [CallPopupView.Line] {
        stream.lines.map { line in
            var speaker: Int?
            if case .resolved(let s) = SpeakerLabeling.state(for: line) { speaker = s }
            return CallPopupView.Line(id: line.id, speaker: speaker, name: speaker.flatMap { speakerNames.name(for: $0) },
                                      text: line.text, volatile: !line.isFinal)
        }
    }

    private var controller: CaptionSessionController!

    init() {
        controller = CaptionSessionController(makeEngine: {
            guard let url = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") else {
                throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
            }
            return TranscriptionEngine(diarizerModelURL: url, audioSource: ListenTo.current.audioSource())
        })

        controller.onStateChange = { [weak self] in self?.state = $0 }
        controller.onSoundLabel = { [weak self] in self?.stream.insertSoundLabel($0) }
        controller.onUpdate = { [weak self] u in
            guard let self else { return }
            var range: ClosedRange<Double>?
            if let a = u.startSeconds, let b = u.endSeconds, a <= b { range = a...b }
            self.stream.apply(text: u.text, isFinal: u.isFinal, speaker: u.speaker, range: range, wordEmphasis: u.wordEmphasis)
        }
    }

    func start() { controller.start() }

    func stop() { controller.stop() }
}

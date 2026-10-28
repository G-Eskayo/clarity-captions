import Foundation
import SwiftUI
import CaptionCore

/// What the window captions (#172). Design A has no control for it; for testing:
/// `defaults write com.gileskayo.captions listenTo both|call|facetime|room` (sandboxed builds: the container's prefs).
enum ListenTo: String {
    /// The call plus a microphone, in one stream, each voice with its own speaker label. Without headphones the mic is the
    /// room's; with headphones that have a mic, only the wearer's; headphones without a mic, the call alone. Default.
    case both
    /// Every sound the Mac plays except Seal Speak's own: FaceTime, a Continuity phone call, Zoom, anything.
    case call
    /// Only FaceTime and its call service (narrower; which process plays the far side is unverified on a live call).
    case facetime
    /// The Mac's microphone, as before #172.
    case room
    /// The room alone, the mic following the headphones as in `.both`: #178's mode while no call is being captioned.
    case roomOnly

    static var current: ListenTo { ListenTo(rawValue: UserDefaults.standard.string(forKey: "listenTo") ?? "") ?? .both }

    func audioSource() -> AudioSource {
        switch self {
        // Echo cancelled on the mic, so a call coming out of the speakers isn't heard twice over.
        case .both:
            // The tap's private device leaves the speakers out, so it isn't tied to whichever output is current (headphones
            // come and go mid-call).
            let call = ProcessTapAudioSource(target: .allSystemAudio)
            call.usesOutputDevice = false
            // The mic follows the headphones (owner, ~10 a.m.): none → the room; with a mic → that mic only.
            return MixedAudioSource([RoomMicSource(), call])
        case .call: return ProcessTapAudioSource(target: .allSystemAudio)
        case .facetime: return ProcessTapAudioSource(target: .apps(bundleIDs: CallApps.faceTime))
        case .room: return MicAudioSource()
        case .roomOnly: return RoomMicSource()
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
    /// What to caption instead of `ListenTo.current`, while a call arriving is handled (#178).
    var listenOverride: ListenTo?
    private(set) lazy var calls = CallFlow(model: self)

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
        controller = CaptionSessionController(makeEngine: { [weak self] in
            guard let url = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") else {
                throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
            }
            return TranscriptionEngine(diarizerModelURL: url, audioSource: (self?.listenOverride ?? ListenTo.current).audioSource())
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

    func stopAndWait() async { await controller.stopAndWait() }
}

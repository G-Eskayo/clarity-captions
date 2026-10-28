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
        }
    }
}

@MainActor
final class CaptionMacModel: ObservableObject {
    @Published var state: CaptionState = .idle
    @Published var stream = CaptionStream()
    @Published var style: CaptionStyle = CaptionStyleStore().load() {
        didSet { if !MarvinScene.isOn { CaptionStyleStore().save(style) } }
    }
    @Published var speakerNames = SpeakerNames()
    /// The pop-up stays above other windows (#172).
    @Published var pinned = true

    // iPhone parity (#172, owner ~10:10): the same conversation, Save / New, Settings and Saved as the iPhone app.
    /// Which page the pop-up shows: the captions, Settings, Saved, credits.
    @Published var nav = ScreenNavigator()
    /// Saved conversations, kept 30 days (ADR 0022), in the app's own folder.
    private(set) var store: SavedConversationStoring?
    /// The conversation on screen, kept across pauses until [ New ]; saved only on [ Save ].
    @Published var session = ConversationSession()
    /// The dim over a paused conversation, with [ Save ] and [ New ].
    @Published var veil = PauseVeil()
    /// [ ✔ ] shows briefly between [ Save ] and [ Saved ].
    @Published var showingSaveCheck = false
    /// [ New ]'s one question, asked in place when the conversation isn't saved.
    @Published var newQuestion = InPlaceQuestion<NewConversationQuestion>()
    /// ADR 0019, read by the controller on every tick.
    @Published var idleStop: IdleStopSetting = IdleStopStore().load() {
        didSet { IdleStopStore().save(idleStop) }
    }
    private var tickTask: Task<Void, Never>?

    var hasConversation: Bool { ConversationSession.hasContent(stream.lines) }
    var veilShowing: Bool { veil.isVisible(state: state, hasConversation: hasConversation) }

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
        }, idleStopSetting: { [weak self] in self?.idleStop ?? .default })

        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            // Screenshot scenes write to a folder of their own, never the real saved list.
            let dir = MarvinScene.storeDirectory ?? support.appendingPathComponent("SavedConversations")
            store = try? SavedConversationStore(directory: dir)
            Task { [store] in try? await store?.purgeExpired(now: Date()) }
        }

        controller.onStateChange = { [weak self] in self?.handle($0) }
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

    /// As on the iPhone: resuming continues the same conversation on a new line; pausing keeps it on screen.
    private func handle(_ newState: CaptionState) {
        state = newState
        switch newState {
        case .preparing:
            session.captioningStarted(at: Date())
            veil.captioningStarted()
            stream.breakLine()
        case .listening:
            tickTask?.cancel()
            tickTask = Task { [weak self] in
                while !Task.isCancelled, self?.state == .listening {
                    self?.controller.tick()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        case .idle, .failed, .pausedQuiet:
            tickTask?.cancel()
        }
    }

    /// Moves between the pop-up's pages with the iPhone's fade.
    func go(_ change: (inout ScreenNavigator) -> Void) {
        withAnimation(Fluid.fade(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) { change(&nav) }
    }

    /// [ Save ]: writes the conversation to the saved list (kept 30 days). Saving again updates the same one.
    func save() {
        let before = session
        guard let conversation = session.makeSaved(lines: stream.lines, names: speakerNames, now: Date()) else { return }
        showingSaveCheck = true
        Task {
            do {
                try await store?.save(conversation)
                try await store?.purgeExpired(now: Date())
            } catch {
                session = before
            }
            try? await Task.sleep(nanoseconds: UInt64(FluidTiming.saveCheckHold * 1e9))
            withAnimation(Fluid.saveMorph(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) { showingSaveCheck = false }
        }
    }

    /// [ New ]: asks first if the conversation isn't saved as it stands.
    func requestNew() {
        let unsaved = session.hasUnsavedChanges(lines: stream.lines, names: speakerNames)
        if NewConversationQuestion.request(hasUnsavedChanges: unsaved, question: &newQuestion) == .startNow { startNew() }
    }

    /// [ New ], after its question if it asked.
    func startNew() {
        stream = CaptionStream()
        speakerNames = SpeakerNames()
        session = ConversationSession()
        veil = PauseVeil()
        showingSaveCheck = false
    }
}

extension ScreenNavigator {
    /// ⌘, on the Mac: Settings from wherever the pop-up is.
    mutating func openSettings() {
        for _ in 0..<4 where current != .settings {
            if current == .captions { gearTapped() } else { back() }
        }
    }
}

import CaptionCore
import Foundation
import SwiftUI

/// A call arriving mid-conversation on the Mac (#178): watches for calls, shows the banner, and carries out
/// `CallArrival`'s effects on the model one after another (each waits for the engine to stop before the next starts).
///
/// The room is captioned from the microphone; [ Caption call ] switches to the call format (#172: call and room
/// together). Off when `listenTo` has been set by hand (`defaults write com.gileskayo.captions listenTo both`), which
/// keeps #172's behavior exactly.
@MainActor
final class CallFlow: ObservableObject {
    @Published private(set) var arrival = CallArrival()

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: "listenTo") == nil }

    private unowned let model: CaptionMacModel
    private let watcher = CallWatcher()
    @Published private var pausedRoom: (stream: CaptionStream, names: SpeakerNames)?
    var hasPausedRoom: Bool { pausedRoom != nil }
    private var callStartedAt = Date()
    private var queue: Task<Void, Never>?
    private lazy var store: SavedConversationStore? = {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return try? SavedConversationStore(directory: dir.appendingPathComponent("SavedConversations"))
    }()

    init(model: CaptionMacModel) { self.model = model }

    /// Called once the window is up, before captioning starts.
    func start() {
        guard Self.isEnabled else { return }
        model.listenOverride = .room
        watcher.onChange = { [weak self] live in self?.send(live ? .callStarted : .callEnded) }
        watcher.start()
    }

    func send(_ event: CallArrival.Event) {
        let captioning = model.state == .listening || model.state == .preparing
        let effects = arrival.handle(event, captioning: captioning)
        guard !effects.isEmpty else { return }
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            for effect in effects { await self?.perform(effect) }
        }
    }

    /// The pop-up's top-bar words while #178 is running; nil keeps #172's own.
    func statusWords(for state: CaptionState) -> String? {
        guard Self.isEnabled else { return nil }
        switch arrival.step {
        case .call: return nil
        case .ended: return String(localized: "Call ended")
        case .room, .ringing, .declined: return state == .listening ? String(localized: "Captioning the room") : nil
        }
    }

    private func perform(_ effect: CallArrival.Effect) async {
        switch effect {
        case .pauseRoom:
            await model.stopAndWait()
            pausedRoom = (model.stream, model.speakerNames)
        case .startCall:
            model.stream = CaptionStream()
            model.speakerNames = SpeakerNames()
            callStartedAt = Date()
            model.listenOverride = .both
            model.start()
        case .stopCall:
            await model.stopAndWait()
            model.listenOverride = .room
        case .saveCall:
            let lines = model.stream.lines
            if SessionRetention.shouldSave(lines: lines) {
                try? await store?.save(SavedConversation.from(sessionStart: callStartedAt, lines: lines, speakerNames: model.speakerNames))
            }
            finishCall()
        case .resumeRoom:
            finishCall()
            model.start()
        }
    }

    /// Puts the room's conversation back (or an empty one, if the call interrupted nothing).
    private func finishCall() {
        let room = pausedRoom
        pausedRoom = nil
        model.stream = room?.stream ?? CaptionStream()
        model.speakerNames = room?.names ?? SpeakerNames()
        model.listenOverride = .room
    }
}

/// Under the pop-up: the banner while ringing or after the call, the paused note during it.
struct CallBannerSlot: View {
    @ObservedObject var calls: CallFlow
    let style: CaptionStyle

    var body: some View {
        Group {
            switch calls.arrival.banner {
            case .ringing:
                CallBannerView(kind: .ringing, style: style, onPrimary: { calls.send(.captionCall) }, onSecondary: { calls.send(.notNow) })
            case .ended:
                CallBannerView(kind: .ended, style: style, onPrimary: { calls.send(.saveTranscript) }, onSecondary: { calls.send(.dontSave) })
            case nil:
                if calls.arrival.step == .call && calls.hasPausedRoom { PausedConversationNote(style: style) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, calls.arrival.banner == nil && !(calls.arrival.step == .call && calls.hasPausedRoom) ? 0 : 10)
    }
}

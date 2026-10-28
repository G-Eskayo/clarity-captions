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
        model.listenOverride = .roomOnly
        watcher.onChange = { [weak self] live in self?.send(live ? .callStarted : .callEnded) }
        watcher.start()
        #if DEBUG
        runFakeCallIfRequested()
        #endif
    }

    func send(_ event: CallArrival.Event) {
        let captioning = model.state == .listening || model.state == .preparing
        let effects = arrival.handle(event, captioning: captioning)
        NSLog("[calls] %@ while %@ -> %@ %@", "\(event)", captioning ? "captioning" : "not captioning", "\(arrival.step)", "\(effects)")
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

    /// The empty window's words while the room is captioned; nil keeps #172's "Captions start when your call does."
    func emptyWords(for state: CaptionState) -> String? {
        guard Self.isEnabled, arrival.step != .call, state == .listening else { return nil }
        return String(localized: "Captions show up here when someone speaks.")
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
            NSLog("[calls] call engine starting")
            model.start()
        case .stopCall:
            await model.stopAndWait()
            model.listenOverride = .roomOnly
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
        model.listenOverride = .roomOnly
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

#if DEBUG
import AppKit
import os

/// DEBUG only: drives a pretend call through the real app, so the whole flow can be run and captured without a phone.
/// `-SealFakeCall 8,30` starts a call 8 s after launch and ends it at 30 s; `-SealFakeChoice caption|notnow` and
/// `-SealFakeSave yes|no` answer the banners 2 s after they show; `-SealFakeShots <dir>` saves the live window at each
/// step (no Screen Recording permission needed).
extension CallFlow {
    static let log = Logger(subsystem: "com.gileskayo.captions", category: "calls")

    func runFakeCallIfRequested() {
        let defaults = UserDefaults.standard
        guard let spec = defaults.string(forKey: "SealFakeCall") else { return }
        let times = spec.split(separator: ",").compactMap { Double($0) }
        guard times.count == 2 else { return }
        let choice: CallArrival.Event = defaults.string(forKey: "SealFakeChoice") == "notnow" ? .notNow : .captionCall
        let save: CallArrival.Event = defaults.string(forKey: "SealFakeSave") == "no" ? .dontSave : .saveTranscript
        let shots = defaults.string(forKey: "SealFakeShots")
        let at = { (seconds: Double, work: @escaping @MainActor () -> Void) in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { work() } }
        }
        let shot = { (name: String) in if let shots { Self.snapshotWindow(to: URL(fileURLWithPath: shots).appendingPathComponent("\(name).png")) } }
        at(times[0] - 1) { shot("0-room") }
        at(times[0]) { self.send(.callStarted) }
        at(times[0] + 1.2) { shot("1-ringing") }
        at(times[0] + 2) { self.send(choice) }
        at(times[1] - 1) { shot("2-call") }
        at(times[1]) { self.send(.callEnded) }
        at(times[1] + 1.5) { shot("3-ended") }
        at(times[1] + 3) { self.send(save) }
        at(times[1] + 10) { shot("4-resumed") }
    }

    static func snapshotWindow(to url: URL) {
        guard let view = NSApplication.shared.windows.first(where: { $0.title == CaptionMacApp.windowTitle })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        log.info("snapshot \(url.lastPathComponent, privacy: .public)")
    }
}
#endif

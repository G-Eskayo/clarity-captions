import CaptionCore
import Foundation
import SwiftUI

/// A call arriving mid-conversation on the Mac (#178): watches for calls, shows the banner, and carries out
/// `CallArrival`'s effects on the model one after another (each waits for the engine to stop before the next starts).
///
/// The room is captioned from the microphone; [ Caption call ] switches to the call format (#172: call and room
/// together). Off when `listenTo` has been set by hand (`defaults write com.gileskayo.captions.mac listenTo both`), which
/// keeps #172's behavior exactly.
@MainActor
final class CallFlow: ObservableObject {
    @Published private(set) var arrival = CallArrival()
    /// Changes whenever the window switches conversation (room -> call, call -> room), so the captions fade across.
    @Published private(set) var conversationToken = 0
    /// The call app in a call right now ("FaceTime", "Zoom"), from the call watcher; nil when there's no call.
    @Published private(set) var callApp: String?

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: "listenTo") == nil }

    private unowned let model: CaptionMacModel
    private let watcher = CallWatcher()
    private let notifier = CallNotifier()
    /// Stack of paused conversations, mirroring CallArrival's paused stack: rooms and held calls.
    @Published private var pausedFrames: [(stream: CaptionStream, names: SpeakerNames, session: ConversationSession, frame: CallArrival.Frame, startedAt: Date?)] = []
    /// A conversation with words was set aside for a call (an empty window has nothing to come back to).
    var hasPausedRoom: Bool {
        // True if there's a paused room frame (not a heldCall) with content
        for paused in pausedFrames {
            if case .room = paused.frame {
                return ConversationSession.hasContent(paused.stream.lines)
            }
        }
        return false
    }
    private var callStartedAt = Date()
    private var previousCallApp: String?
    private var queue: Task<Void, Never>?
    init(model: CaptionMacModel) { self.model = model }

    /// Called once the window is up. The watcher always runs, so the top bar can name a call app that is really in a
    /// call; the call-arriving flow only when #178 is on.
    func start() {
        if Self.isEnabled {
            model.listenOverride = .roomOnly
            notifier.onCaption = { [weak self] in self?.send(.captionCall) }
            notifier.onNotNow = { [weak self] in self?.send(.notNow) }
            notifier.onHoldAndAccept = { [weak self] _ in
                guard let self, let heldApp = self.previousCallApp else { return }
                self.send(.holdAndAccept(heldApp: heldApp))
            }
            notifier.onEndAndAccept = { [weak self] in self?.send(.endAndAccept) }
            notifier.setUp()
        }
        watcher.onChange = { [weak self] app in
            guard let self else { return }
            let wasLive = self.callApp != nil
            self.previousCallApp = self.callApp  // Save before updating
            self.callApp = app
            guard Self.isEnabled else { return }
            if app != nil, wasLive, app != self.previousCallApp {
                // A different call app is now live (second call scenario)
                self.send(.secondCallStarted(app: app))
            } else if app != nil, !wasLive {
                // A call started (first call)
                self.send(.callStarted)
            } else if app == nil, wasLive {
                // Call ended
                self.send(.callEnded)
            }
        }
        watcher.start()
        #if DEBUG
        runFakeCallIfRequested()
        #endif
    }

    func send(_ event: CallArrival.Event) {
        let captioning = model.state == .listening || model.state == .preparing
        let wasRinging = arrival.banner == .ringing
        let effects = arrival.handle(event, captioning: captioning)
        // Announcements (first call and second call) always go through notifications.
        if arrival.banner == .ringing, !wasRinging { notifier.show(detail: ringingDetail) }
        if wasRinging, arrival.banner != .ringing { notifier.remove() }
        NSLog("[calls] %@ while %@ -> %@ %@", "\(event)", captioning ? "captioning" : "not captioning", "\(arrival.step)", "\(effects)")
        guard !effects.isEmpty else { return }
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            for effect in effects { await self?.perform(effect) }
        }
    }

    /// Whether there's a conversation on screen for a call to pause.
    var hasConversation: Bool { ConversationSession.hasContent(model.stream.lines) }

    /// The ringing banner's question: pausing only makes sense with a conversation on screen.
    var ringingDetail: String {
        hasConversation ? String(localized: "Pause this conversation and caption the call?") : String(localized: "Caption the call?")
    }

    /// The pop-up's top-bar words; nil keeps its own ("Listening", "Captioning"). A call app is named only while its call
    /// is what's being captioned (owner, 2026-10-28).
    func statusWords(for state: CaptionState) -> String? {
        if Self.isEnabled, arrival.step == .ended { return String(localized: "Call ended") }
        let captioningTheCall = !Self.isEnabled || arrival.step == .call
        guard state == .listening, captioningTheCall, let callApp else { return nil }
        return CallSignal.captioningWords(app: callApp)
    }

    static let fade = Animation.easeInOut(duration: 0.6)

    private func perform(_ effect: CallArrival.Effect) async {
        switch effect {
        case .pauseRoom:
            await model.stopAndWait()
            pausedFrames.append((model.stream, model.speakerNames, model.session, .room(captioning: model.state == .listening || model.state == .preparing), nil))
        case .holdCall:
            await model.stopAndWait()
            // The current call is being held; push it onto the stack with its start time
            if let currentApp = callApp {
                pausedFrames.append((model.stream, model.speakerNames, model.session, .heldCall(app: currentApp), callStartedAt))
            }
        case .startCall:
            withAnimation(Self.fade) {
                model.stream = CaptionStream()
                model.speakerNames = SpeakerNames()
                model.session = ConversationSession()
                conversationToken += 1
            }
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
                // Into the same saved list as every conversation (Saved, kept 30 days).
                try? await model.store?.save(SavedConversation.from(sessionStart: callStartedAt, lines: lines, speakerNames: model.speakerNames))
            }
        case .resumeRoom:
            finishCallAndResume()
            model.start()
        case .restoreRoom:
            finishCallAndResume()
        case .resumeHeldCall:
            // Resume a held call from the stack, restoring its start time
            let startedAt = pausedFrames.last?.startedAt ?? Date()
            finishCallAndResume()
            callStartedAt = startedAt
            model.listenOverride = .both
            NSLog("[calls] resuming held call")
            model.start()
        case .announceSecondCall(let app):
            notifier.showSecondCall(app: app)
        }
    }

    /// Pops the last paused frame and restores it (or an empty one if nothing is paused).
    private func finishCallAndResume() {
        let popped = pausedFrames.popLast()
        // The call view fades back to the conversation it interrupted (owner, 2026-10-28).
        withAnimation(Self.fade) {
            model.stream = popped?.stream ?? CaptionStream()
            model.speakerNames = popped?.names ?? SpeakerNames()
            model.session = popped?.session ?? ConversationSession()
            conversationToken += 1
        }
        // If popped frame is a room (or nothing), set roomOnly mode
        if popped == nil {
            model.listenOverride = .roomOnly
        } else if case .room = popped?.frame {
            model.listenOverride = .roomOnly
        }
        // If popped frame is a heldCall, keep .both mode (will be set by resumeHeldCall effect)
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
                // Show in-window ringing banner as fallback when notifications aren't available.
                CallBannerView(kind: .ringing, style: style, detailOverride: calls.ringingDetail, onPrimary: { calls.send(.captionCall) }, onSecondary: { calls.send(.notNow) })
            case .ended:
                CallBannerView(kind: .ended, style: style, onPrimary: { calls.send(.saveTranscript) }, onSecondary: { calls.send(.returnToConversation) })
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
/// `-SealFakeSave yes|no` (no: Return) answer the banners 2 s after they show; `-SealFakeShots <dir>` saves the live window at each
/// step (no Screen Recording permission needed).
extension CallFlow {
    static let log = Logger(subsystem: "com.gileskayo.captions", category: "calls")

    func runFakeCallIfRequested() {
        let defaults = UserDefaults.standard
        guard let spec = defaults.string(forKey: "SealFakeCall") else { return }
        let times = spec.split(separator: ",").compactMap { Double($0) }
        guard times.count == 2 else { return }
        let choice: CallArrival.Event = defaults.string(forKey: "SealFakeChoice") == "notnow" ? .notNow : .captionCall
        let save: CallArrival.Event = defaults.string(forKey: "SealFakeSave") == "no" ? .returnToConversation : .saveTranscript
        let shots = defaults.string(forKey: "SealFakeShots")
        let at = { (seconds: Double, work: @escaping @MainActor () -> Void) in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { work() } }
        }
        let shot = { (name: String) in if let shots { Self.snapshotWindow(to: URL(fileURLWithPath: shots).appendingPathComponent("\(name).png")) } }
        // The app opens with captions off (#188): press Start, as the owner would, unless `-SealFakeStart no`.
        if defaults.string(forKey: "SealFakeStart") != "no" { at(1) { self.model.start() } }
        // `-SealFakeHide yes`: the app hidden (⌘H) when the call comes, so the offer comes as a notification.
        if defaults.string(forKey: "SealFakeHide") == "yes" { at(times[0] - 0.5) { NSApp.hide(nil) } }
        at(times[0] - 1) { shot("0-room") }
        at(times[0]) { self.callApp = "FaceTime"; self.send(.callStarted) }
        at(times[0] + 1.2) { shot("1-ringing") }
        at(times[0] + 2) { if choice == .captionCall { CallNotifier.bringWindowForward() }; self.send(choice) }
        at(times[1] - 1) { shot("2-call") }
        at(times[1]) { self.callApp = nil; self.send(.callEnded) }
        at(times[1] + 1.5) { shot("3-ended") }
        at(times[1] + 3) { self.send(save) }
        at(times[1] + 3.5) { shot("3b-fading") }
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

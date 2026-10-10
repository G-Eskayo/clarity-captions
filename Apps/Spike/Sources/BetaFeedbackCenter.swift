import CaptionCore
import Foundation
import StoreKit
import UIKit

/// Beta-tester feedback and metrics (ADR 0023, #112), for TestFlight installs only. The main screen tells it what
/// happens; it keeps the current conversation's measurements, decides when the rating card shows, and builds the
/// report. In an App Store install every call returns at once and nothing is recorded or shown (fail closed).
@MainActor
final class BetaFeedbackCenter: ObservableObject {
    static let shared = BetaFeedbackCenter()

    /// True only once StoreKit has said this is a TestFlight (or Xcode) install.
    @Published private(set) var isOn = false
    @Published private(set) var environment: BetaEnvironment = .unknown
    /// The rating card is up for the conversation on screen.
    @Published var showingCard = false
    /// The one-time notice on the first beta launch (mock-up 06).
    @Published var showingNotice = false
    @Published private(set) var unsentCount = 0
    /// The launch animation has handed off to the main screen; the notice waits for it.
    @Published private(set) var launchFinished = false

    private(set) var store: FeedbackStore?
    private var recorder: ConversationRecorder?
    /// [ New ] waits for the card, then starts the next conversation.
    private var afterCard: (() -> Void)?
    private var startedThisLaunch = false
    private var launchFacts: ConversationRecorder.LaunchFacts?

    private static let noticeKey = "betaNoticeSeen"

    private init() {
        if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            store = try? FeedbackStore(directory: dir.appendingPathComponent("BetaFeedback"))
        }
    }

    // MARK: TestFlight or not

    private var resolving: Task<Void, Never>?

    /// Resolves once per launch; every caller waits for the same answer.
    func ensureResolved() async {
        if resolving == nil { resolving = Task { await resolveEnvironment() } }
        await resolving?.value
    }

    /// Asks StoreKit once per launch. Only a verified `.sandbox` (TestFlight) or `.xcode` answer turns beta on;
    /// anything else is the App Store behaviour, and anything left from an earlier TestFlight install is deleted.
    private func resolveEnvironment() async {
        let env: BetaEnvironment
        if DemoMode.forcesBeta {
            env = .xcode
        } else {
            switch try? await AppTransaction.shared {
            case .verified(let transaction):
                switch transaction.environment {
                case .sandbox: env = .sandbox
                case .xcode: env = .xcode
                case .production: env = .production
                default: env = .unknown
                }
            default:
                env = .unknown
            }
        }
        environment = env
        isOn = env.featuresOn
        guard isOn else { store?.deleteAll(); unsentCount = 0; return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshCount()
        if DemoMode.betaSeed { seedDemoRecords() }
        maybeShowNotice()
    }

    func launchAnimationFinished(fullDance: Bool, barShown: Bool) {
        if launchFacts == nil { launchFacts = .init(fullDance: fullDance, barShown: barShown) }
        launchFinished = true
        maybeShowNotice()
    }

    private func maybeShowNotice() {
        guard isOn, launchFinished else { return }
        // Demo runs show the notice only when asked for, so other screenshots aren't covered by it.
        if DemoMode.isOn || DemoMode.gummyDemo { if DemoMode.betaNotice { showingNotice = true }; return }
        if !UserDefaults.standard.bool(forKey: Self.noticeKey) { showingNotice = true }
    }

    func dismissNotice() {
        UserDefaults.standard.set(true, forKey: Self.noticeKey)
        showingNotice = false
    }

    // MARK: what happens in a conversation (all no-ops unless beta is on)

    /// The recorder for the conversation on screen, created on first use and picked up again after a cold launch.
    private func current(for session: ConversationSession) -> ConversationRecorder? {
        guard isOn else { return nil }
        if let recorder, recorder.id == session.id { return recorder }
        recorder = store?.recorder(id: session.id) ?? ConversationRecorder(id: session.id)
        return recorder
    }

    private func update(_ session: ConversationSession, persist: Bool = false, _ change: (inout ConversationRecorder) -> Void) {
        guard current(for: session) != nil, recorder != nil else { return }
        change(&recorder!)   // in place: a caption update never copies the histograms
        if persist, let r = recorder { store?.upsert(r, finished: false); refreshCount() }
    }

    func startPressed(_ session: ConversationSession) {
        let sinceLaunch = startedThisLaunch ? nil : Date().timeIntervalSince(LaunchClock.start)
        startedThisLaunch = true
        update(session) { $0.startPressed(at: Date(), sinceLaunch: sinceLaunch, launch: launchFacts) }
    }

    func captioningStarted(_ session: ConversationSession) {
        update(session) { $0.captioningStarted(at: Date(), battery: Self.battery()) }
    }

    func captionUpdate(_ session: ConversationSession, _ u: CaptionUpdate) {
        guard isOn else { return }
        update(session) { $0.captionUpdate(text: u.text, isFinal: u.isFinal, speaker: u.speaker, lagSeconds: u.lagSeconds, at: Date()) }
    }

    func audioLevel(_ session: ConversationSession, _ dbfs: Double) {
        guard isOn else { return }
        update(session) { $0.audioLevel(dbfs) }
    }

    /// About once a second while captioning.
    func tick(_ session: ConversationSession) {
        guard isOn else { return }
        let thermal = Self.thermal()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        update(session) { $0.thermal(thermal); $0.lowPowerMode(lowPower) }
    }

    func captioningStopped(_ session: ConversationSession, state: CaptionState) {
        guard let ending = ConversationEnding.from(state) else { return }
        update(session, persist: true) { $0.captioningStopped(at: Date(), battery: Self.battery(), ending: ending) }
    }

    func leftApp(_ session: ConversationSession) {
        update(session, persist: true) { $0.leftMidConversation() }
    }

    /// A cold launch brought back a conversation: if captions were running when the app closed, that counts as a
    /// pause without her.
    func restoredAfterColdLaunch(_ session: ConversationSession, hasConversation: Bool) {
        update(session, persist: true) { $0.restoredAfterAppClosed(at: Date()) }
        cardIfDue(.returnedToConversation, session: session, hasConversation: hasConversation, isCaptioning: false)
    }

    /// Back from another app with the conversation paused.
    func returned(_ session: ConversationSession, hasConversation: Bool, isCaptioning: Bool) {
        if isCaptioning { update(session) { $0.backWhileCaptioning() }; return }
        cardIfDue(.returnedToConversation, session: session, hasConversation: hasConversation, isCaptioning: isCaptioning)
    }

    /// [ New ] (after its "Start new?" question, if it asked). Runs `startNew` now, or after the card.
    func newTapped(_ session: ConversationSession, hasConversation: Bool, startNew: @escaping () -> Void) {
        let shows = cardIfDue(.newTapped, session: session, hasConversation: hasConversation, isCaptioning: false)
        let finish = { [weak self] in
            if let r = self?.recorder, r.id == session.id { self?.store?.upsert(r, finished: true) }
            self?.recorder = nil
            self?.refreshCount()
            startNew()
        }
        if shows { afterCard = finish } else { finish() }
    }

    @discardableResult
    private func cardIfDue(_ event: RatingCardTiming.Event, session: ConversationSession, hasConversation: Bool, isCaptioning: Bool) -> Bool {
        guard isOn, let r = current(for: session) else { return false }
        let show = RatingCardTiming.shouldShow(event: event, ending: r.ending, leftWhileCaptioning: r.leftWhileCaptioning,
                                               alreadyAsked: r.asked, hasConversation: hasConversation, isCaptioning: isCaptioning)
        if show { showingCard = true }
        return show
    }

    func rate(_ session: ConversationSession, value: Int, note: String?) {
        update(session, persist: true) { $0.rate(value, note: note) }
        closeCard()
    }

    func skip(_ session: ConversationSession) {
        update(session, persist: true) { $0.skipRating() }
        closeCard()
    }

    private func closeCard() {
        showingCard = false
        let next = afterCard
        afterCard = nil
        next?()
    }

    /// Debug only: shows the card for screenshots.
    func demoShowCard() { showingCard = true }

    // MARK: the report

    var recipient: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "SealFeedbackRecipient") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    /// Everything not yet sent: finished conversations plus the one on screen, if it has started.
    func makeReport(style: CaptionStyle, idleStop: IdleStopSetting) -> (report: FeedbackReport, ids: Set<UUID>) {
        var stored = store?.all() ?? []
        if let recorder, recorder.hasData {
            stored.removeAll { $0.recorder.id == recorder.id }
            stored.append(StoredConversation(recorder: recorder, finished: false))
        }
        let now = Date()
        let info = Bundle.main.infoDictionary ?? [:]
        let report = FeedbackReport(
            app: .init(version: info["CFBundleShortVersionString"] as? String ?? "?",
                       build: info["CFBundleVersion"] as? String ?? "?", environment: environment),
            device: .init(model: Self.deviceModel(), os: "iOS " + UIDevice.current.systemVersion,
                          lowPowerModeSeen: stored.contains { $0.recorder.lowPowerModeSeen }),
            settings: .init(theme: style.preset?.id ?? "custom", lettering: style.font.rawValue,
                            textSize: String(describing: style.size), quietStop: idleStop.rawValue),
            sentAt: now,
            conversations: stored.map { $0.recorder.entry(now: now) })
        return (report, Set(stored.map(\.recorder.id)))
    }

    /// Messages (or the share sheet) reported the text went: the finished conversations in it are deleted.
    func markSent(_ ids: Set<UUID>) {
        store?.removeSent(ids: ids)
        refreshCount()
    }

    private func refreshCount() {
        var ids = Set((store?.all() ?? []).map(\.recorder.id))
        if let recorder, recorder.hasData { ids.insert(recorder.id) }
        unsentCount = ids.count
    }

    // MARK: the phone

    private static func battery() -> BatterySample {
        let d = UIDevice.current
        return BatterySample(level: Double(d.batteryLevel), charging: d.batteryState == .charging || d.batteryState == .full)
    }

    private static func thermal() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    /// "iPhone15,4" on a phone; the simulated model in the simulator.
    static func deviceModel() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    // MARK: debug

    /// Debug only (`-ClarityDemoBetaSeed`): the four conversations the mock-ups show, so the preview and the
    /// Settings count can be screenshotted. Measurements only; no caption text exists to seed.
    private func seedDemoRecords() {
        #if DEBUG
        guard let store, store.all().isEmpty else { return }
        let base = Date().addingTimeInterval(-3600 * 30)
        func make(_ offset: Double, minutes: Double, rating: Int?, note: String?, lags: [Double], speakers: [Int],
                  ending: ConversationEnding, drop: Double?, thermal: ThermalLevel) {
            var r = ConversationRecorder(id: UUID())
            let start = base.addingTimeInterval(offset)
            r.startPressed(at: start, sinceLaunch: 2.1, launch: .init(fullDance: false, barShown: false))
            r.captioningStarted(at: start, battery: drop.map { _ in BatterySample(level: 0.8, charging: false) })
            for (i, lag) in lags.enumerated() {
                r.captionUpdate(text: "x", isFinal: true, speaker: speakers[i % speakers.count], lagSeconds: lag,
                                at: start.addingTimeInterval(Double(i) + 1))
            }
            r.thermal(thermal)
            let end = start.addingTimeInterval(minutes * 60)
            r.captioningStopped(at: end, battery: drop.map { BatterySample(level: 0.8 - $0 / 100 * minutes / 30, charging: false) }, ending: ending)
            if let rating { r.rate(rating, note: note) } else { r.skipRating() }
            store.upsert(r, finished: true)
        }
        make(0, minutes: 41, rating: 6, note: nil, lags: [1.1, 1.1, 1.1, 1.0, 1.2, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 3.2],
             speakers: [0, 1], ending: .userStop, drop: nil, thermal: .serious)
        make(3600 * 20, minutes: 8, rating: nil, note: nil, lags: [0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 1.9],
             speakers: [0], ending: .quietStop, drop: nil, thermal: .nominal)
        make(3600 * 24, minutes: 23, rating: 8, note: "Lost it when the waiter talked fast",
             lags: [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 1.5],
             speakers: [0, 1, 2], ending: .userStop, drop: 6.5, thermal: .fair)
        make(3600 * 10, minutes: 12, rating: 9, note: nil, lags: [0.5, 0.6, 0.6, 0.7], speakers: [0, 1],
             ending: .userStop, drop: nil, thermal: .nominal)
        refreshCount()
        #endif
    }
}

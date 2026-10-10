import AVFoundation
import CaptionCore
import SwiftUI
import UIKit

/// What first run asks the system, and the two setup steps it runs. Swappable so the DEBUG launch demo (#104) can run
/// this real flow on a simulator, which has no microphone, speech engine or network.
struct FirstRunSystem {
    var microphone: () -> MicrophoneAccess
    var requestMicrophone: () async -> Void
    var speechModelInstalled: () async -> Bool
    var speechSupport: () async -> SpeechSupport
    var hasSeenWelcome: () -> Bool
    var markWelcomeSeen: () -> Void
    var speakerModelWarm: () -> Bool
    /// Warms the speaker model and remembers it for this build.
    var warmUpSpeakerModel: () async throws -> Void
    var speechDownload: SpeechDownload

    static var live: FirstRunSystem {
        let store = FirstRunStore()
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let buildKey = "\(ProcessInfo.processInfo.operatingSystemVersionString) / \(v)"
        return FirstRunSystem(
            microphone: {
                switch AVAudioApplication.shared.recordPermission {
                case .granted: .granted
                case .denied: .denied
                default: .undetermined
                }
            },
            requestMicrophone: { _ = await AVAudioApplication.requestRecordPermission() },
            speechModelInstalled: { await SpeechModelInstaller.isInstalled() },
            speechSupport: { await SpeechSupport.check() },
            hasSeenWelcome: { store.hasSeenWelcome },
            markWelcomeSeen: { store.markWelcomeSeen() },
            speakerModelWarm: { store.isSpeakerModelWarm(forBuild: buildKey) },
            warmUpSpeakerModel: {
                guard let url = Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") else {
                    throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc"))
                }
                try await TranscriptionEngine.warmUp(diarizerModelURL: url)
                store.markSpeakerModelWarm(forBuild: buildKey)
            },
            speechDownload: SpeechDownload.english())
    }
}

@MainActor
final class FirstRunModel: ObservableObject {
    @Published var step: FirstRunStep = .welcome
    @Published var progress = 0.0
    @Published var problem: String?
    /// Which download failure, when the speech download stopped: one screen, the reason on its second line (#122).
    @Published var downloadProblem: DownloadProblem?
    /// True once there is nothing left to set up, and the main screen can take over.
    @Published var finished = false
    /// True once the facts have been read at least once, so `step` is real rather than the starting guess.
    @Published private(set) var checked = false
    private var sawSetupScreen = false
    private var working = false
    private let system: FirstRunSystem

    init(system: FirstRunSystem = DemoMode.launchDemoSystem ?? .live) { self.system = system }

    /// Re-reads the facts and shows the right screen. Called on launch and whenever the app comes back to the front.
    func refresh() async {
        let facts = FirstRunFacts(
            hasSeenWelcome: system.hasSeenWelcome(),
            microphone: system.microphone(),
            speechModelInstalled: await system.speechModelInstalled(),
            speakerModelWarm: system.speakerModelWarm(),
            speechSupport: await system.speechSupport())
        let next = FirstRun.step(for: facts)
        let previous = step
        step = next
        checked = true
        // Setup that ran behind the launch animation hands off straight to the main screen (#104), as the approved
        // animation does; the "All set!" screen is only for a first run that ends without automatic setup.
        if next == .done && (!sawSetupScreen || previous.isAutomaticSetup) { finished = true; return }
        sawSetupScreen = true
        await runAutomaticStep()
    }

    private func runAutomaticStep() async {
        guard !working else { return }
        switch step {
        case .speechModel:
            working = true; problem = nil; downloadProblem = nil; progress = 0
            let startTime = Date()
            // Always ends: installed, or plain words and Try again -- never a spinner that runs forever (#81).
            switch await system.speechDownload.run(onProgress: { p in Task { @MainActor in self.progress = p } }) {
            case .installed: break
            case .failed(let why): problem = why.message; downloadProblem = why
            case .alreadyRunning: working = false; return
            }
            if problem == nil {
                let elapsed = Date().timeIntervalSince(startTime)
                let delay = LaunchAnimationGate.remainingDelay(elapsed: elapsed)
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            }
            working = false
            if problem == nil { await refresh() }
        case .speakerModel:
            working = true; problem = nil
            let startTime = Date()
            do {
                try await system.warmUpSpeakerModel()
            } catch { problem = "Something went wrong while getting ready. Please try again." }
            if problem == nil {
                let elapsed = Date().timeIntervalSince(startTime)
                let delay = LaunchAnimationGate.remainingDelay(elapsed: elapsed)
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            }
            working = false
            if problem == nil { await refresh() }
        default: break
        }
    }

    func primaryTapped() {
        switch step {
        case .welcome:
            system.markWelcomeSeen()
            Task { await refresh() }
        case .microphone:
            Task { await system.requestMicrophone(); await refresh() }
        case .microphoneDenied:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .done:
            finished = true
        default: break
        }
    }

    func retry() { problem = nil; downloadProblem = nil; Task { await refresh() } }
}

/// First run in the v1 look (#122, approved in #120, mock-up round3/03): the chosen theme's background, plain words,
/// the gummy button only where there's something to do, and a fade from one screen to the next. No icons, no boxes.
struct FirstRunView: View {
    @ObservedObject var model: FirstRunModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let style = CaptionStyleStore().load()

    /// What this screen says: a stopped download gets its own words, with the reason on the second line.
    private var copy: FirstRunCopy {
        if model.step == .speechModel, let why = model.downloadProblem { return FirstRunCopy.downloadStopped(why) }
        return FirstRunCopy.for(model.step)
    }

    /// Changes whenever the words change, so the old screen fades out and the new one fades in.
    private var screenID: String { "\(model.step)-\(model.problem ?? "")" }

    var body: some View {
        let compact = verticalSizeClass == .compact
        ZStack {
            style.background.color.ignoresSafeArea()
            // Scrolls when sideways (landscape is short), and fills the screen otherwise.
            GeometryReader { geo in
                ScrollView {
                    screen(compact: compact)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                        .padding(.horizontal, 24)
                        .id(screenID)
                        .transition(.opacity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(style.text.color)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: screenID)
        .onChange(of: model.step) { _, newStep in
            UIAccessibility.post(notification: .screenChanged, argument: FirstRunCopy.for(newStep).title)
        }
    }

    private func screen(compact: Bool) -> some View {
        let copy = copy
        return VStack(spacing: 0) {
            Spacer(minLength: compact ? 16 : 40)
            VStack(spacing: compact ? 8 : 12) {
                Text(copy.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(copy.message)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(mutedColor(style))
                // A download or warm-up runs behind the launch animation (#104, #119); these only show when nothing
                // covers it, in the theme's colors.
                if model.problem == nil, model.step == .speechModel {
                    ProgressView(value: model.progress)
                        .tint(style.gear.color)
                        .padding(.horizontal, 40)
                        .padding(.top, 12)
                    Text("\(Int(model.progress * 100))%").font(.headline).monospacedDigit().foregroundStyle(mutedColor(style))
                } else if model.problem == nil, model.step == .speakerModel {
                    ProgressView().tint(style.gear.color).padding(.top, 12)
                } else if let problem = model.problem, model.downloadProblem == nil {
                    // The warm-up stopped (not a download): its reason, under the step's own words.
                    Text(problem).font(.title3).multilineTextAlignment(.center).foregroundStyle(mutedColor(style))
                }
            }
            Spacer(minLength: compact ? 16 : 40)
            if model.problem != nil {
                bigButton(String(localized: "Try again")) { model.retry() }
            } else if let button = copy.button {
                bigButton(button) { model.primaryTapped() }
            }
        }
        .padding(.bottom, compact ? 12 : 24)
    }

    /// The approved button A (#105, #113): the same gummy pill as Start captions.
    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(GummyButtonStyle(style: style))
    }
}

/// First run until there is nothing left to set up, then the main screen.
struct RootView: View {
    @StateObject private var firstRun = FirstRunModel()
    @Environment(\.scenePhase) private var scenePhase
    /// The launch animation (#104): on every cold launch, and again when setup (a download, a warm-up) starts with
    /// nothing covering it, e.g. after the microphone is allowed or after Try again.
    @State private var launch: UUID? = DemoMode.skipsLaunchAnimation ? nil : UUID()

    var body: some View {
        ZStack {
            Group {
                // Demo mode (debug builds, launch flag only) goes straight to the caption screen.
                if DemoMode.gummyDemo { GummyDemoView() }
                else if firstRun.finished || DemoMode.isOn { ContentView() } else { FirstRunView(model: firstRun) }
            }
            .accessibilityHidden(launch != nil)
            .environment(\.launchCovering, launch != nil)
            if let launch {
                LaunchOverlay(firstRun: firstRun, theme: CaptionStyleStore().load()) {
                    self.launch = nil
                    BetaFeedbackCenter.shared.launchAnimationFinished(fullDance: LaunchOverlay.lastFullDance, barShown: LaunchOverlay.lastBarShown)
                }
                    .id(launch)
            }
        }
        .task {
            // Beta or not is known before the main screen needs it; without a launch animation the notice may show
            // straight away (ADR 0023).
            await BetaFeedbackCenter.shared.ensureResolved()
            if launch == nil { BetaFeedbackCenter.shared.launchAnimationFinished(fullDance: false, barShown: false) }
        }
        .task {
            await firstRun.refresh()
            if setupDone { EngineWarmupHost.shared.allow() }
        }
        #if DEBUG
        .task {
            // -ClarityDemoLaunch firstrun (#122 evidence; simctl can't tap): tap Set up, then Continue, as she would.
            guard DemoMode.launch == "firstrun" else { return }
            for step in [FirstRunStep.welcome, .microphone] {
                while !(firstRun.step == step && launch == nil) { try? await Task.sleep(for: .milliseconds(100)) }
                try? await Task.sleep(for: .seconds(2.5))
                firstRun.primaryTapped()
            }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await firstRun.refresh() } }
        }
        // Once there's nothing left to set up, the captioning engine loads behind the launch animation (#119).
        .onChange(of: setupDone) { _, done in
            if done { EngineWarmupHost.shared.allow() }
        }
        .onChange(of: setupNeedsCover) { _, needs in
            if needs && launch == nil { launch = UUID() }
        }
    }

    private var setupNeedsCover: Bool { firstRun.checked && firstRun.step.isAutomaticSetup && firstRun.problem == nil }
    private var setupDone: Bool { firstRun.checked && firstRun.step == .done }
}

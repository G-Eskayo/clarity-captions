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
            working = true; problem = nil; progress = 0
            let startTime = Date()
            // Always ends: installed, or plain words and Try again -- never a spinner that runs forever (#81).
            switch await system.speechDownload.run(onProgress: { p in Task { @MainActor in self.progress = p } }) {
            case .installed: break
            case .failed(let why): problem = why.message
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

    func retry() { problem = nil; Task { await refresh() } }
}

struct FirstRunView: View {
    @ObservedObject var model: FirstRunModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        let copy = FirstRunCopy.for(model.step)
        let compact = verticalSizeClass == .compact
        // Scrolls when sideways (landscape is short), and fills the screen otherwise.
        GeometryReader { geo in ScrollView { VStack(spacing: compact ? 14 : 28) {
            Spacer()
            // A download or warm-up runs behind the launch animation (#104); this screen only shows them when one
            // stopped, with Try again.
            Image(systemName: symbol)
                .font(.system(size: compact ? 36 : 72))
                .foregroundStyle(.white)
                .frame(width: compact ? 72 : 150, height: compact ? 72 : 150)
                .background(Color("LaunchBackground"), in: Circle())
                .accessibilityHidden(true)
            Text(copy.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(copy.message).font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if model.step == .speechModel && model.problem == nil {
                ProgressView(value: model.progress).padding(.horizontal, 40)
                Text("\(Int(model.progress * 100))%").font(.headline).monospacedDigit()
            } else if model.step == .speakerModel && model.problem == nil {
                ProgressView().controlSize(.large)
            }
            if let problem = model.problem {
                Text(problem).font(.headline).foregroundStyle(.red).multilineTextAlignment(.center)
                bigButton("Try again") { model.retry() }
            } else if let button = copy.button {
                bigButton(button) { model.primaryTapped() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: geo.size.height)
        .padding(24) }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: model.step) { _, newStep in
            UIAccessibility.post(notification: .screenChanged, argument: FirstRunCopy.for(newStep).title)
        }
        }
    }

    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 72) }
            .buttonStyle(.borderedProminent)
    }

    private var symbol: String {
        switch model.step {
        case .unsupported: "exclamationmark.bubble.fill"
        case .welcome: "hand.wave.fill"
        case .microphone: "mic.fill"
        case .microphoneDenied: "mic.slash.fill"
        case .speechModel: "arrow.down.circle.fill"
        case .speakerModel: "waveform.circle.fill"
        case .done: "checkmark.circle.fill"
        }
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
            if let launch {
                LaunchOverlay(firstRun: firstRun, theme: CaptionStyleStore().load()) { self.launch = nil }
                    .id(launch)
            }
        }
        .task { await firstRun.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await firstRun.refresh() } }
        }
        .onChange(of: setupNeedsCover) { _, needs in
            if needs && launch == nil { launch = UUID() }
        }
    }

    private var setupNeedsCover: Bool { firstRun.checked && firstRun.step.isAutomaticSetup && firstRun.problem == nil }
}

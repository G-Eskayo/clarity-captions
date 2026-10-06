import AVFoundation
import CaptionCore
import SwiftUI
import UIKit

@MainActor
final class FirstRunModel: ObservableObject {
    @Published var step: FirstRunStep = .welcome
    @Published var progress = 0.0
    @Published var problem: String?
    /// True once there is nothing left to set up, and the main screen can take over.
    @Published var finished = false
    private var sawSetupScreen = false
    private var working = false
    private let store = FirstRunStore()

    private var buildKey: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(ProcessInfo.processInfo.operatingSystemVersionString) / \(v)"
    }

    private var modelURL: URL? { Bundle.main.url(forResource: "Sortformer_v2.1", withExtension: "mlmodelc") }

    /// Re-reads the facts and shows the right screen. Called on launch and whenever the app comes back to the front.
    func refresh() async {
        let mic: MicrophoneAccess = switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
        let facts = FirstRunFacts(
            hasSeenWelcome: store.hasSeenWelcome,
            microphone: mic,
            speechModelInstalled: await SpeechModelInstaller.isInstalled(),
            speakerModelWarm: store.isSpeakerModelWarm(forBuild: buildKey))
        let next = FirstRun.step(for: facts)
        step = next
        if next == .done && !sawSetupScreen { finished = true; return }
        sawSetupScreen = true
        await runAutomaticStep()
    }

    private func runAutomaticStep() async {
        guard !working else { return }
        switch step {
        case .speechModel:
            working = true; problem = nil; progress = 0
            let startTime = Date()
            do { try await SpeechModelInstaller.install { p in Task { @MainActor in self.progress = p } } }
            catch { problem = "I couldn't finish the download. Check that Wi-Fi is on, then try again." }
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
                guard let url = modelURL else { throw SpeakerModelError.modelMissing(URL(fileURLWithPath: "Sortformer_v2.1.mlmodelc")) }
                try await TranscriptionEngine.warmUp(diarizerModelURL: url)
                store.markSpeakerModelWarm(forBuild: buildKey)
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
            store.markWelcomeSeen()
            Task { await refresh() }
        case .microphone:
            Task { _ = await AVAudioApplication.requestRecordPermission(); await refresh() }
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
            if model.step == .speechModel || model.step == .speakerModel {
                LaunchAnimationView()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 36 : 72))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 72 : 150, height: compact ? 72 : 150)
                    .background(Color("LaunchBackground"), in: Circle())
                    .accessibilityHidden(true)
            }
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
        case .welcome: "hand.wave.fill"
        case .microphone: "mic.fill"
        case .microphoneDenied: "mic.slash.fill"
        case .speechModel, .speakerModel: "" // Shown as LaunchAnimationView instead
        case .done: "checkmark.circle.fill"
        }
    }
}

/// First run until there is nothing left to set up, then the main screen.
struct RootView: View {
    @StateObject private var firstRun = FirstRunModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            // Demo mode (debug builds, launch flag only) goes straight to the caption screen.
            if firstRun.finished || DemoMode.isOn { ContentView() } else { FirstRunView(model: firstRun) }
        }
        .task { await firstRun.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await firstRun.refresh() } }
        }
    }
}

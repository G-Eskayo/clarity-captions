import CaptionCore
import Foundation

/// A scripted conversation for screenshots and demos (portfolio page, App Store). Debug builds only, and only when
/// launched with a flag, so it can never run in a shipped app:
///   -ClarityDemo          plays the conversation at speaking pace, words firming up as they would live
///   -ClarityDemoStatic    shows the whole conversation at once, for repeatable screenshots
///   -ClarityDemoSettings  also opens the appearance settings
///   -ClarityDemoSettingsSection idleStop   scrolls those settings to a section (simctl can't scroll)
///   -ClarityDemoTheme night  -ClarityDemoFont serif   start with this look
///   -ClarityDemoGummy     a screen of gummy buttons pressing by themselves
///   -ClarityDemoPaused    pauses after the conversation: the dim with [ Save ] / [ New ] (#102)
///   -ClarityDemoSaved     paused and saved: [ Saved ] in green
///   -ClarityDemoVeilCleared  paused with the dim tapped away, and the hint
///   -ClarityDemoFlow save|clear|new|copy|start   plays a flow for screen recordings: pause, save, resume and pause again;
///                         tap the dim away and hold to bring it back; [ New ] asking first; select across lines,
///                         wait for Copy, resize, copy (#107: simctl can't touch, so the selection is scripted)
///   -ClarityDemoSelect    a selection across three captions with its handles and, after half a second, Copy (#107)
///   -ClarityDemoPreset <id>   shows a color preset (e.g. night, paper)
///   -ClarityDemoLandscape rotates to landscape (simctl can't rotate)
///   -ClarityDemoTour flow|1-6   the how-to-use tour (#108): the whole tour driven through the real model calls
///                         (simctl can't tap), or one step as a still
///   -ClarityDemoLaunch ordinary|first|fail   runs the real launch animation and first-run flow with a pretend system
///                         (#104): ordinary = everything ready; first = a slow speech download, then the warm-up,
///                         through the real SpeechDownload path; fail = the download stops partway, for Try again;
///                         welcome / microphone / micdenied / unsupported open on that first-run screen; firstrun taps
///                         through welcome and microphone by itself, then setup runs behind the launch (#122)
///   -ClarityDemoBeta      behave as a TestFlight install (ADR 0023): rating card, Settings' Test version section
///   -ClarityDemoBetaSeed  with four recorded conversations to send (measurements only), as in mock-up 04
///   -ClarityDemoBetaCard  paused, with the rating card up (mock-up 01); -ClarityDemoBetaNote with a note open (02)
///   -ClarityDemoBetaNotice  the one-time test-version notice (06), even if it was seen
///   -ClarityDemoBetaPreview opens Settings' "What will be sent" (04)
///   -ClarityDemoFlow rate|feedback   pause, [ New ], tap 8 and the card fades; or Settings → preview → Messages
///   -ClarityDemoShow <id>  one state for the UI audit (2026-10-10; simctl can't tap): banner, preparing, confirmnew,
///                         namespeaker, jump, canthear, failed, quiet, tour4save, savebeta
///   -ClarityDemoSettingsPush saved|credits|deleteall   Settings opened on a sub-screen (with -ClarityDemoSettings)
/// It feeds the same CaptionStream the real engine feeds, so what you see is the real caption view: speaker colours,
/// names, line breaks and sound labels. No microphone, speech model or network is involved.
enum DemoMode {
    static var isOn: Bool { flag("-ClarityDemo") || isStatic || tour != nil || show != nil }
    static var isStatic: Bool { flag("-ClarityDemoStatic") }
    static var opensSettings: Bool { flag("-ClarityDemoSettings") }
    /// The section id to scroll Settings to, from `-ClarityDemoSettingsSection <id>`. Debug builds only.
    static var settingsSection: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ClarityDemoSettingsSection"), i + 1 < args.count else { return nil }
        return args[i + 1]
        #else
        return nil
        #endif
    }

    /// `-ClarityDemoTheme <id>` and `-ClarityDemoFont <rawValue>`: start with this look (saved, like a user's choice),
    /// for screenshots of every theme and lettering. Debug builds only.
    static var theme: CaptionPreset? { value(after: "-ClarityDemoTheme").flatMap { id in CaptionPreset.all.first { $0.id == id } } }
    static var font: CaptionFont? { value(after: "-ClarityDemoFont").flatMap(CaptionFont.init(rawValue:)) }
    /// `-ClarityDemoGummy`: a screen of gummy buttons that press and release by themselves (simctl can't tap).
    static var gummyDemo: Bool { flag("-ClarityDemoGummy") }

    /// Applies -ClarityDemoTheme / -ClarityDemoFont before the main screen reads the saved style.
    static func applyLookOverrides() {
        guard theme != nil || font != nil else { return }
        let store = CaptionStyleStore()
        var style = store.load()
        if let theme { style = style.applying(theme) }
        if let font { style.font = font }
        store.save(style)
    }

    static var paused: Bool { flag("-ClarityDemoPaused") || saved || veilCleared }
    static var saved: Bool { flag("-ClarityDemoSaved") }
    static var veilCleared: Bool { flag("-ClarityDemoVeilCleared") }
    static var select: Bool { flag("-ClarityDemoSelect") }
    static var landscape: Bool { flag("-ClarityDemoLandscape") }
    static var flow: String? { value(after: "-ClarityDemoFlow") }
    static var preset: String? { value(after: "-ClarityDemoPreset") }
    static var launch: String? { value(after: "-ClarityDemoLaunch") }
    /// `-ClarityDemoTour flow` plays the whole how-to-use tour; `-ClarityDemoTour <1-6>` shows one step (#108).
    static var tour: String? { value(after: "-ClarityDemoTour") }
    static var show: String? { value(after: "-ClarityDemoShow") }
    static var settingsPush: String? { value(after: "-ClarityDemoSettingsPush") }
    /// Round 2 (#118): three saved conversations to show the saved list (mock-up round2/02), written once on launch.
    static var seedsSaved: Bool {
        flag("-ClarityDemoSavedSeed") || settingsPush == "saved" || settingsPush == "deleteall" || flow == "saved" || flow == "delete"
    }
    static var forcesBeta: Bool { flag("-ClarityDemoBeta") || betaSeed || betaCard || betaNotice || betaPreview || flow == "rate" || flow == "feedback" }
    static var betaSeed: Bool { flag("-ClarityDemoBetaSeed") || betaPreview || flow == "feedback" }
    static var betaCard: Bool { flag("-ClarityDemoBetaCard") || betaNote }
    static var betaNote: Bool { flag("-ClarityDemoBetaNote") }
    static var betaNotice: Bool { flag("-ClarityDemoBetaNotice") }
    static var betaPreview: Bool { flag("-ClarityDemoBetaPreview") }
    /// Caption-screen demos and the gummy screen go straight in, so their screenshots stay repeatable.
    static var skipsLaunchAnimation: Bool { launch == nil && (isOn || gummyDemo) }

    /// The pretend system behind `-ClarityDemoLaunch`, or nil (always nil in a shipped app).
    static var launchDemoSystem: FirstRunSystem? {
        #if DEBUG
        guard let kind = launch else { return nil }
        let state = LaunchDemoState(ready: kind == "ordinary")
        return FirstRunSystem(
            // "microphone" opens on the microphone screen; "firstrun" walks welcome → microphone → setup (#122 evidence).
            microphone: {
                switch kind {
                case "welcome": .undetermined
                case "micdenied": .denied
                case "microphone", "firstrun": state.micGranted ? .granted : .undetermined
                default: .granted
                }
            },
            requestMicrophone: { state.micGranted = true },
            speechModelInstalled: { state.installed },
            speechSupport: { kind == "unsupported" ? .unsupportedDevice : .supported },
            hasSeenWelcome: { kind == "welcome" ? false : kind == "firstrun" ? state.welcomeSeen : true },
            markWelcomeSeen: { state.welcomeSeen = true },
            speakerModelWarm: { state.warm },
            warmUpSpeakerModel: {
                try? await Task.sleep(for: .seconds(3))
                state.warm = true
            },
            speechDownload: SpeechDownload(install: { progress in
                // Uneven like a real download: quick at first, a slower stretch, then done (about 7 s).
                let points: [(Double, Double)] = [(0, 0), (3.5, 0.55), (5.25, 0.65), (7, 1)]
                for i in 1..<points.count {
                    let (t0, p0) = points[i - 1], (t1, p1) = points[i]
                    for step in 1...Int((t1 - t0) * 10) {
                        try await Task.sleep(for: .milliseconds(100))
                        let p = p0 + (p1 - p0) * Double(step) / ((t1 - t0) * 10)
                        if kind == "fail" && p >= 0.4 { throw URLError(.notConnectedToInternet) }
                        progress(p)
                    }
                }
                state.installed = true
            }))
        #else
        return nil
        #endif
    }

    private static func value(after name: String) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
        #else
        return nil
        #endif
    }

    private static func flag(_ name: String) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(name)
        #else
        return false
        #endif
    }

    enum Step {
        case line(speaker: Int, text: String)
        case sound(SoundLabelKind)
    }

    static let speakers = [0: "Gil", 1: "Dana"]

    static let script: [Step] = [
        .line(speaker: 0, text: "Happy birthday, Mom. Watch the screen while we talk."),
        .line(speaker: 1, text: "It's catching every word, even from across the table."),
        .line(speaker: 0, text: "And it works in airplane mode. Nothing leaves the phone."),
        .sound(.laughter),
        .line(speaker: 1, text: "So no more paying every month just to follow a conversation?"),
        .line(speaker: 0, text: "Not a cent. It's yours, and it's free for anyone who needs it."),
        .line(speaker: 1, text: "Each of us gets our own colour, so you know who's talking."),
        .line(speaker: 0, text: "Okay, what should we try first"),
    ]
}

extension CaptionModel {
    /// Plays DemoMode.script through the caption stream. The last line stays unfinished, the way a live caption looks
    /// mid-sentence.
    func runDemo() {
        state = .listening
        for (speaker, name) in DemoMode.speakers { speakerNames.apply(name, to: speaker) }
        let steps = DemoMode.script
        if DemoMode.isStatic {
            for (i, step) in steps.enumerated() { play(step, isFinal: i < steps.count - 1) }
            return
        }
        Task { @MainActor in
            for (i, step) in steps.enumerated() {
                if case .line(_, let text) = step {
                    // Words arrive a few at a time, as the live engine's volatile results do.
                    let words = text.split(separator: " ")
                    for n in stride(from: 3, to: words.count, by: 3) {
                        play(.line(speaker: speakerOf(step), text: words.prefix(n).joined(separator: " ")), isFinal: false)
                        try? await Task.sleep(nanoseconds: 350_000_000)
                    }
                }
                play(step, isFinal: i < steps.count - 1)
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
        }
    }

    private func speakerOf(_ step: DemoMode.Step) -> Int {
        if case .line(let speaker, _) = step { return speaker }
        return 0
    }

    private func play(_ step: DemoMode.Step, isFinal: Bool) {
        switch step {
        case .line(let speaker, let text): stream.apply(text: text, isFinal: isFinal, speaker: speaker)
        case .sound(let kind): stream.insertSoundLabel(kind)
        }
    }
}

extension CaptionModel {
    /// Debug only: moves the screen between captioning and paused the way the real controller's states do.
    func demoSetState(_ newState: CaptionState) {
        handleCaptionStateChange(newState)
    }

    /// Debug only: a few more words after resuming, so the saved state visibly turns back into [ Save ].
    func demoSay(_ text: String, speaker: Int) {
        stream.apply(text: text, isFinal: true, speaker: speaker)
    }

    /// Debug only: applies `-ClarityDemoPreset <id>` for screenshots in each look.
    func demoApplyPreset() {
        guard let id = DemoMode.preset, let preset = CaptionPreset.all.first(where: { $0.id == id }) else { return }
        style = style.applying(preset)
    }
}

#if DEBUG
/// What the pretend system behind `-ClarityDemoLaunch` has done so far.
private final class LaunchDemoState: @unchecked Sendable {
    private let lock = NSLock()
    private var _installed: Bool
    private var _warm: Bool
    private var _welcomeSeen = false
    private var _micGranted = false
    init(ready: Bool) { _installed = ready; _warm = ready }
    var welcomeSeen: Bool { get { lock.withLock { _welcomeSeen } } set { lock.withLock { _welcomeSeen = newValue } } }
    var micGranted: Bool { get { lock.withLock { _micGranted } } set { lock.withLock { _micGranted = newValue } } }
    var installed: Bool { get { lock.withLock { _installed } } set { lock.withLock { _installed = newValue } } }
    var warm: Bool { get { lock.withLock { _warm } } set { lock.withLock { _warm = newValue } } }
}
#endif

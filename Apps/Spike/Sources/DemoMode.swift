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
///   -ClarityDemoFlow save|clear|new|copy   plays a flow for screen recordings: pause, save, resume and pause again;
///                         tap the dim away and hold to bring it back; [ New ] asking first; select across lines,
///                         wait for Copy, resize, copy (#107: simctl can't touch, so the selection is scripted)
///   -ClarityDemoSelect    a selection across three captions with its handles and, after half a second, Copy (#107)
///   -ClarityDemoPreset <id>   shows a color preset (e.g. night, paper)
///   -ClarityDemoLandscape rotates to landscape (simctl can't rotate)
/// It feeds the same CaptionStream the real engine feeds, so what you see is the real caption view: speaker colours,
/// names, line breaks and sound labels. No microphone, speech model or network is involved.
enum DemoMode {
    static var isOn: Bool { flag("-ClarityDemo") || isStatic }
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

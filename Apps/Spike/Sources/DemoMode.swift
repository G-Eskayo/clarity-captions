import CaptionCore
import Foundation

/// A scripted conversation for screenshots and demos (portfolio page, App Store). Debug builds only, and only when
/// launched with a flag, so it can never run in a shipped app:
///   -ClarityDemo          plays the conversation at speaking pace, words firming up as they would live
///   -ClarityDemoStatic    shows the whole conversation at once, for repeatable screenshots
///   -ClarityDemoSettings  also opens the appearance settings
///   -ClarityDemoSettingsSection idleStop   scrolls those settings to a section (simctl can't scroll)
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

import AVFoundation
import CaptionCore
import Foundation
import OSLog
import UIKit

/// Live Translation in your ear (#233): the translation spoken into her headphones as people talk, with Apple's
/// on-device voices. Turned on in Settings only ("turnon" A, #238); any headphones, never the iPhone's speaker
/// ("headphones" A); the iPhone's own mic keeps listening ("mic" C, `MicSessionSetup`). Nothing is downloaded here
/// (owner, 2026-10-30): it uses a voice already on the device, and a language with none is captions only ("novoice" A).
/// Foreground only (App Review 2.5.4): leaving the app stops the voice.
@MainActor
final class EarCenter: NSObject, ObservableObject {
    static let shared = EarCenter()
    static let onKey = "earTranslationOn"
    private static let log = Logger(subsystem: "com.gileskayo.captions", category: "ear")

    /// The line the voice is saying, which of its words, and how far through them (0...1), for the speaker mark.
    struct Speaking: Equatable {
        let lineID: Int
        let words: Range<Int>
        var share: Double
    }

    @Published private(set) var isOn: Bool
    @Published private(set) var headphones = false
    @Published private(set) var speaking: Speaking?
    /// What was spoken for each line, joined: shown in place of a line's translation until that arrives (an early
    /// phrase is spoken before the line is finished, and only finished lines get their translation).
    @Published private(set) var spokenTranslations: [Int: String] = [:]
    /// The voice for the translation language, chosen from the voices already on the device.
    @Published private(set) var voice: AVSpeechSynthesisVoice?

    /// Asked for when words are holding still and will be ready to speak early: the translator looks again then.
    var onCheck: (() -> Void)?

    private let defaults: UserDefaults
    private let synthesizer = AVSpeechSynthesizer()
    private let warmer = AVSpeechSynthesizer()
    private var phrases = EarPhrases()
    private var echo = EchoGuard()
    private struct Queued { let phrase: EarPhrases.Phrase; let text: String }
    private var queue: [Queued] = []
    private var current: (item: Queued, utterance: ObjectIdentifier, start: Double)?
    private var target: Locale?
    private var check: Task<Void, Never>?
    private var foreground = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isOn = defaults.bool(forKey: Self.onKey)
        super.init()
        synthesizer.delegate = self
        #if DEBUG
        if DemoMode.ear != nil { isOn = true }
        #endif
        MicAudioSource.speaksIntoEar = isOn && Self.offered
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRoute() }
        }
        refreshRoute()
    }

    /// On iPhone, iPad and Duo; not the iPhone app running on a Mac (the Mac app stays without it, #233).
    static var offered: Bool { !ProcessInfo.processInfo.isiOSAppOnMac }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// For Settings' note and for whether anything is spoken.
    var state: EarState { EarState(on: isOn, hasVoice: voice != nil, headphones: headphones) }

    // MARK: settings

    func setOn(_ on: Bool) {
        isOn = on
        defaults.set(on, forKey: Self.onKey)
        MicAudioSource.speaksIntoEar = on && Self.offered
        if on { warmUp() } else { stopAll() }
    }

    /// The translation language changed (or was first read): pick its voice from what's on the device, and load it
    /// now, in Settings, so the first line isn't late (the spike: up to 10 s for the first sentence after a boot).
    func targetChanged(_ locale: Locale?) {
        guard locale?.identifier != target?.identifier || voice == nil else { return }
        target = locale
        voice = locale.flatMap(Self.bestVoice(for:))
        stopAll()
        if isOn { warmUp() }
    }

    /// The best installed voice that speaks `locale`'s language (VoiceCoverage, #237), premium before enhanced before
    /// the default; never a novelty voice.
    static func bestVoice(for locale: Locale) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
        guard let code = VoiceCoverage.voice(for: locale.language.minimalIdentifier, among: voices.map(\.language)) else { return nil }
        return voices.filter { $0.language == code }.max { $0.quality.rawValue < $1.quality.rawValue }
    }

    /// Renders a short sentence to nowhere so the voice is loaded before anyone talks. Nothing plays.
    private func warmUp() {
        guard let voice else { return }
        let utterance = AVSpeechUtterance(string: LanguageSettingsState.sample(target ?? Locale(identifier: voice.language)) ?? "OK")
        utterance.voice = voice
        warmer.write(utterance) { _ in }
    }

    // MARK: the captions

    /// The phrases to translate and speak now. While it can't speak (off, no voice, no headphones, the split open,
    /// translation off), what's said is passed over, so turning it on later doesn't read out the past.
    func take(from lines: [CaptionLine], active: Bool) -> [EarPhrases.Phrase] {
        if lines.isEmpty { phrases.reset(); spokenTranslations = [:]; return [] }
        guard active, foreground, state.speaks else { phrases.skip(lines); scheduleCheck(nil); return [] }
        let now = Self.now
        let ready = phrases.take(from: lines, now: now).filter { phrase in
            // The app's own voice, picked up by the mic and captioned (the spike's echo): never spoken again.
            let isEcho = echo.isEcho(phrase.text, from: now - 3, to: now)
            if isEcho { Self.log.info("echo not spoken, line \(phrase.lineID)") }
            return !isEcho
        }
        scheduleCheck(phrases.nextCheck)
        return ready
    }

    /// A phrase came back translated: say it after what's already queued ("behind" A: never skipped).
    func speak(_ phrase: EarPhrases.Phrase, translation: String) {
        let text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.speaks, foreground, !text.isEmpty else { return }
        spokenTranslations[phrase.lineID] = [spokenTranslations[phrase.lineID], text].compactMap { $0 }.joined(separator: " ")
        #if DEBUG
        if DemoMode.ear == "mark" { demoHold(phrase); return }
        #endif
        queue.append(Queued(phrase: phrase, text: text))
        speakNext()
    }

    private func speakNext() {
        guard current == nil, !queue.isEmpty, let voice else { return }
        let item = queue.removeFirst()
        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = voice
        // A little faster while more is waiting, so it catches up without skipping.
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                             AVSpeechUtteranceDefaultSpeechRate * Float(EarPace.speed(waiting: queue.count)))
        let start = Self.now
        current = (item, ObjectIdentifier(utterance), start)
        // Counted as said from now, with a generous end, so its echo is caught while it's still playing.
        echo.spoke(item.text, from: start, to: start + 0.6 * Double(item.text.split(separator: " ").count) + 1)
        speaking = Speaking(lineID: item.phrase.lineID, words: item.phrase.words, share: 0)
        synthesizer.speak(utterance)
    }

    private func finished(_ id: ObjectIdentifier) {
        guard let current, current.utterance == id else { return }
        let now = Self.now
        echo.spoke(current.item.text, from: current.start, to: now)
        echo.forget(before: now - 30)
        self.current = nil
        speaking = nil
        speakNext()
    }

    /// Stops at once and drops what's queued: turned off, headphones gone, the app left, or a new language.
    func stopAll() {
        queue = []
        current = nil
        speaking = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// The app came on screen or left it. Leaving stops the voice (App Review 2.5.4: no background audio).
    func foregroundChanged(_ active: Bool) {
        foreground = active
        if !active { stopAll() }
    }

    // MARK: headphones

    private func refreshRoute() {
        #if DEBUG
        // Screenshots on the simulator, whose only output is its speaker.
        if let ear = DemoMode.ear, ear != "noheadphones" { headphones = true; return }
        #endif
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue)
        let can = EarRoute.canSpeak(outputs: outputs)
        // Unplugged or disconnected: iOS would carry on through the speaker, so stop at once.
        if !can { stopAll() }
        headphones = can
    }

    private func scheduleCheck(_ at: Double?) {
        check?.cancel()
        guard let at else { check = nil; return }
        let wait = max(0, at - Self.now) + 0.02
        check = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.onCheck?()
        }
    }

    #if DEBUG
    /// `-ClarityDemoEar mark`: the newest translated line held part-way through being said, for the screenshot (the
    /// simulator can't play into headphones).
    private func demoHold(_ phrase: EarPhrases.Phrase) {
        speaking = Speaking(lineID: phrase.lineID, words: phrase.words, share: 0.55)
    }
    #endif
}

extension EarCenter: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let length = (utterance.speechString as NSString).length
        let share = length == 0 ? 1 : Double(characterRange.location + characterRange.length) / Double(length)
        Task { @MainActor in
            guard let current = self.current, current.utterance == id, self.speaking != nil else { return }
            self.speaking?.share = share
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }
}

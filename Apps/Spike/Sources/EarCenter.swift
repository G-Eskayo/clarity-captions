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
    /// "Sound like the speaker" (#247, PR #254 "setting" B): its own On/Off under Speak it in my ear; off to start.
    static let matchKey = "earSoundsLikeSpeaker"
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
    @Published private(set) var matchOn: Bool
    /// The installed voices for the translation language that the shipped table has measured (#247): the speakers'
    /// voices are chosen from these. None: everyone gets `voice`, as before.
    @Published private(set) var matchVoices: [VoiceCalibration] = []

    /// Asked for when words are holding still and will be ready to speak early: the translator looks again then.
    var onCheck: (() -> Void)?

    private let defaults: UserDefaults
    private let synthesizer = AVSpeechSynthesizer()
    private let warmer = AVSpeechSynthesizer()
    private var phrases = EarPhrases()
    private var echo = EchoGuard()
    private struct Queued { let phrase: EarPhrases.Phrase; let text: String; let speaker: Int?; let instanceID: Int }
    private let recorder: SpeakerVoiceRecorder
    private var chooser = EarVoiceChooser(voices: [], normalSyllablesPerSecond: nil, defaultVoiceID: nil)
    private var chooserSession = -1
    private var queue: [Queued] = []
    private var current: (item: Queued, utterance: ObjectIdentifier, start: Double, instanceID: Int)?
    private var target: Locale?
    private var check: Task<Void, Never>?
    private var foreground = true

    init(defaults: UserDefaults = .standard, recorder: SpeakerVoiceRecorder = .shared) {
        self.defaults = defaults
        self.recorder = recorder
        isOn = defaults.bool(forKey: Self.onKey)
        matchOn = defaults.bool(forKey: Self.matchKey)
        super.init()
        synthesizer.delegate = self
        #if DEBUG
        if DemoMode.ear != nil { isOn = true }
        if DemoMode.earMatch != nil { matchOn = true }
        #endif
        MicAudioSource.speaksIntoEar = isOn && Self.offered
        recorder.isRecording = isOn && matchOn && Self.offered
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

    /// For the note under Sound like the speaker.
    var matchState: EarMatchState {
        #if DEBUG
        if DemoMode.earMatch == "one" { return EarMatchState(on: matchOn, voices: 0) }
        if DemoMode.earMatch != nil { return EarMatchState(on: matchOn, voices: max(1, matchVoices.count)) }
        #endif
        return EarMatchState(on: matchOn, voices: matchVoices.count)
    }

    // MARK: settings

    func setOn(_ on: Bool) {
        isOn = on
        defaults.set(on, forKey: Self.onKey)
        MicAudioSource.speaksIntoEar = on && Self.offered
        recorder.isRecording = on && matchOn && Self.offered
        if on { warmUp() } else { stopAll() }
    }

    /// Sound like the speaker, on or off. Takes effect from the next phrase; speakers are learned from then on.
    func setMatch(_ on: Bool) {
        matchOn = on
        defaults.set(on, forKey: Self.matchKey)
        recorder.isRecording = isOn && on && Self.offered
        resetChooser()
        if on && isOn { warmUp() }
    }

    /// The translation language changed (or was first read): pick its voice from what's on the device, and load it
    /// now, in Settings, so the first line isn't late (the spike: up to 10 s for the first sentence after a boot).
    func targetChanged(_ locale: Locale?) {
        guard locale?.identifier != target?.identifier || voice == nil else { return }
        target = locale
        voice = locale.flatMap(Self.bestVoice(for:))
        matchVoices = voice.map(Self.calibratedVoices(like:)) ?? []
        resetChooser()
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

    /// The installed voices in `voice`'s own locale (no switching accent between speakers) that the shipped table
    /// measured. Only voices already on the device: nothing is downloaded or measured here.
    static func calibratedVoices(like voice: AVSpeechSynthesisVoice) -> [VoiceCalibration] {
        let installed = Set(AVSpeechSynthesisVoice.speechVoices().filter { $0.language == voice.language }.map(\.identifier))
        return VoiceCalibrationTable.shipped.voices(for: voice.language, installed: installed)
    }

    /// Speakers belong to one captioning session, and their voices to one translation language.
    private func resetChooser() {
        chooser = EarVoiceChooser(voices: matchOn ? matchVoices : [], normalSyllablesPerSecond: VoiceCalibrationTable.shipped.normalPace(for: recorder.language),
                                  defaultVoiceID: voice?.identifier)
        chooserSession = recorder.session
    }

    /// Renders a short sentence to nowhere so the voice is loaded before anyone talks. Nothing plays. With Sound
    /// like the speaker on, the speakers' voices too, so a new speaker's first phrase isn't late.
    private func warmUp() {
        guard let voice else { return }
        let text = LanguageSettingsState.sample(target ?? Locale(identifier: voice.language)) ?? "OK"
        var ids = [voice.identifier]
        if matchOn { ids += matchVoices.map(\.id).filter { $0 != voice.identifier } }
        for id in ids {
            guard let v = AVSpeechSynthesisVoice(identifier: id) else { continue }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = v
            warmer.write(utterance) { _ in }
        }
    }

    // MARK: the captions

    /// The phrases to translate and speak now. While it can't speak (off, no voice, no headphones, the split open,
    /// translation off), what's said is passed over, so turning it on later doesn't read out the past.
    func take(from lines: [CaptionLine], active: Bool) -> [EarPhrases.Phrase] {
        if lines.isEmpty { phrases.reset(); spokenTranslations = [:]; resetChooser(); return [] }
        guard active, foreground, state.speaks else { phrases.skip(lines); scheduleCheck(nil); return [] }
        let now = Self.now
        let ready = phrases.take(from: lines, now: now).filter { phrase in
            // The app's own voice, picked up by the mic and captioned (the spike's echo): never spoken again.
            let isEcho = echo.isEcho(phrase.text, from: now - 3, to: now)
            if isEcho { Self.log.info("echo not spoken, line \(phrase.lineID)") }
            return !isEcho
        }
        scheduleCheck(phrases.nextCheck)
        for phrase in ready { speakers[phrase.lineID] = lines.first { $0.id == phrase.lineID }?.speaker }
        return ready
    }

    /// Whose line each phrase came from, so it's said in that speaker's voice.
    private var speakers: [Int: Int] = [:]
    /// When each phrase (by lineID) was finalized on screen (for behind-by metric).
    private var phraseEndDates: [Int: Date] = [:]

    /// Called when voice events happen: instanceID, event type, timestamp.
    var onVoiceEvent: ((Int, VoiceEvent, Date) -> Void)?
    private var nextInstanceID = 0

    /// Voice event types for ear-delay tracking.
    enum VoiceEvent { case started, finished, cutOff }

    /// A phrase came back translated: say it after what's already queued ("behind" A: never skipped).
    func speak(_ phrase: EarPhrases.Phrase, translation: String, instanceID: Int) {
        let text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.speaks, foreground, !text.isEmpty else { return }
        spokenTranslations[phrase.lineID] = [spokenTranslations[phrase.lineID], text].compactMap { $0 }.joined(separator: " ")
        #if DEBUG
        if DemoMode.ear == "mark" { demoHold(phrase); return }
        #endif
        queue.append(Queued(phrase: phrase, text: text, speaker: speakers[phrase.lineID], instanceID: instanceID))
        if speakers.count > 200 { speakers = speakers.filter { $0.key >= phrase.lineID - 50 } }
        if phraseEndDates.count > 200 { phraseEndDates = phraseEndDates.filter { $0.key >= phrase.lineID - 50 } }
        speakNext()
    }

    private func speakNext() {
        guard current == nil, !queue.isEmpty, let voice else { return }
        let item = queue.removeFirst()
        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = voice
        // A little faster while more is waiting, so it catches up without skipping.
        let catchUp = EarPace.speed(waiting: queue.count)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(catchUp))
        if matchOn, chooser.canMatch {
            // #247: the speaker's own voice, pitch and pace, once they've said about two seconds; until then the usual.
            if recorder.session != chooserSession { resetChooser() }
            let matched = chooser.voice(for: item.speaker, traits: recorder.traits(for: item.speaker))
            if let id = matched.voiceID, let v = AVSpeechSynthesisVoice(identifier: id) { utterance.voice = v }
            utterance.pitchMultiplier = matched.pitchMultiplier
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, matched.rate(catchUp: catchUp))
        }
        let start = Self.now
        let instanceID = item.instanceID
        current = (item, ObjectIdentifier(utterance), start, instanceID)
        // Counted as said from now, with a generous end, so its echo is caught while it's still playing.
        echo.spoke(item.text, from: start, to: start + 0.6 * Double(item.text.split(separator: " ").count) + 1)
        speaking = Speaking(lineID: item.phrase.lineID, words: item.phrase.words, share: 0)
        onVoiceEvent?(instanceID, .started, Date())
        synthesizer.speak(utterance)
    }

    private func finished(_ id: ObjectIdentifier) {
        guard let current, current.utterance == id else { return }
        let now = Self.now
        echo.spoke(current.item.text, from: current.start, to: now)
        echo.forget(before: now - 30)
        if let phraseEndDate = phraseEndDates[current.item.phrase.lineID] {
            onVoiceEvent?(current.instanceID, .finished, phraseEndDate)
        }
        self.current = nil
        speaking = nil
        speakNext()
    }

    /// Stops at once and drops what's queued: turned off, headphones gone, the app left, or a new language.
    func stopAll() {
        if let current { onVoiceEvent?(current.instanceID, .cutOff, Date()) }
        for item in queue { onVoiceEvent?(item.instanceID, .cutOff, Date()) }
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

    /// Record when a phrase was finalized on screen, for computing behind-by metric.
    func recordPhraseEnd(lineID: Int, at date: Date) {
        phraseEndDates[lineID] = date
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

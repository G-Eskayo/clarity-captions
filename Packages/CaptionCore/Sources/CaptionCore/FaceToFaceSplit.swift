import Foundation

/// #208, the owner's answers on PR #216 (2026-10-29): the split's own state, apart from the engines.
/// - **Each half picks its language** from its list, and the tap starts that half. Nothing runs before the first pick.
/// - **One half picked:** that language's engine captions everything, as said, on that half. Nothing is translated.
/// - **Both picked:** voices are matched to halves by the language of their words, between those two languages only.
/// - **Pick again:** tap a half's language name; captions carry on until a different language is tapped.
/// - **Stop** is in her half from the moment the split opens, and leaves it. Captions that stop on their own leave it
///   paused, lines kept, Start in her half; Start carries on with both halves' languages.
///
/// Each captioning session in the split runs one `Captions`; a new pick ends it and starts the next. When a session
/// ends its lines are settled: they keep the half they had, whatever the next session's voice numbers say (numbers
/// restart with each session), and the other engine's try at the same words goes.
///
/// Space: O(lines settled).
public struct FaceToFaceSplit: Equatable, Sendable {
    /// What a captioning session in the split runs.
    public enum Captions: Equatable, Sendable {
        /// Only this half has picked: one engine, in its language, everything on it.
        case one(FaceToFaceHalf, Locale)
        /// Both halves have picked: an engine per half, voices matched between the two.
        case both(owner: Locale, partner: Locale)
    }

    /// Her half's one control.
    public enum Control: Equatable, Sendable { case stop, start }

    private var owner: Locale?
    private var partner: Locale?
    private var listOpen: Set<FaceToFaceHalf> = []
    public private(set) var isPaused = false
    /// The captions the session now running was started with; nil between sessions.
    public private(set) var running: Captions?
    private var settledHalf: [Int: FaceToFaceHalf] = [:]
    private var settledAsSaid: Set<Int> = []

    /// The split just opened. Lines already on screen were one-way captions: they show as said on both halves.
    public init(opening lines: [CaptionLine] = []) {
        settledAsSaid = Set(lines.map(\.id))
    }

    public func language(of half: FaceToFaceHalf) -> Locale? { half == .owner ? owner : partner }

    /// A half shows its list until it has picked, and again while it picks anew.
    public func showsList(_ half: FaceToFaceHalf) -> Bool { language(of: half) == nil || listOpen.contains(half) }

    /// The list a half picks from: the downloaded languages, without the one the other half picked.
    public func choices(for half: FaceToFaceHalf, downloaded: [Locale], name: (Locale) -> String) -> [Locale] {
        FaceToFace.choices(downloaded: downloaded, takenByOtherHalf: language(of: half.other), name: name)
    }

    /// What captions run in once started (paused or not); nil before the first pick.
    public var captions: Captions? {
        switch (owner, partner) {
        case let (o?, p?): .both(owner: o, partner: p)
        case let (o?, nil): .one(.owner, o)
        case let (nil, p?): .one(.partner, p)
        case (nil, nil): nil
        }
    }

    /// The two picked languages, for matching voices and translating; nil until both halves have picked.
    public var languagePair: LanguagePair? {
        guard let owner, let partner else { return nil }
        return LanguagePair(owner: owner, partner: partner)
    }

    public var control: Control { isPaused ? .start : .stop }

    /// A language tapped in a half's list. True when captions must start, or restart in the new languages: a new
    /// language, or any tap while paused. The same language again while captioning only closes the list.
    @discardableResult
    public mutating func pick(_ locale: Locale, for half: FaceToFaceHalf) -> Bool {
        listOpen.remove(half)
        let same = language(of: half).map(Self.sameLanguage(locale)) ?? false
        if half == .owner { owner = locale } else { partner = locale }
        if same && !isPaused { return false }
        isPaused = false
        return true
    }

    /// Her language name tapped at the middle line: the half shows its list again. Nothing stops.
    public mutating func openList(_ half: FaceToFaceHalf) {
        guard language(of: half) != nil else { return }
        listOpen.insert(half)
    }

    /// Captions ended some way other than Stop (the quiet stop, an error): stay, paused. Nothing to pause before a pick.
    public mutating func stoppedOnTheirOwn() {
        if captions != nil { isPaused = true }
    }

    /// Start in the paused split. True when captions must start.
    public mutating func resume() -> Bool {
        guard isPaused, captions != nil else { return false }
        isPaused = false
        return true
    }

    /// A captioning session in the split started, in `captions`.
    public mutating func sessionStarted() { running = captions }

    /// The session ended: its lines keep their half from now on. Returns the lines to take out, the other engine's try at
    /// words a voice's own engine wrote. Nothing to do when no session was running.
    @discardableResult
    public mutating func sessionEnded(_ lines: [CaptionLine], languages: SpeakerLanguages) -> Set<Int> {
        guard running != nil else { return [] }
        var gone: Set<Int> = []
        for line in lines where !isSettled(line) {
            if !isShown(line, languages: languages) { gone.insert(line.id); continue }
            if let half = half(of: line, languages: languages) { settledHalf[line.id] = half } else { settledAsSaid.insert(line.id) }
        }
        running = nil
        return gone
    }

    /// The half a line belongs to: settled, else what the running session says. Sound labels and unmatched voices: none.
    public func half(of line: CaptionLine, languages: SpeakerLanguages) -> FaceToFaceHalf? {
        if let half = settledHalf[line.id] { return half }
        if settledAsSaid.contains(line.id) || line.isSoundLabel { return nil }
        switch running {
        case .one(let half, _): return half
        case .both: return languages.half(of: line)
        case nil: return nil
        }
    }

    /// Whether the split shows a line: settled lines always; in a two-language session, only each voice's own engine.
    public func isShown(_ line: CaptionLine, languages: SpeakerLanguages) -> Bool {
        if isSettled(line) { return true }
        if case .both = running { return FaceToFace.isShown(line, languages: languages) }
        return true
    }

    public func shown(_ lines: [CaptionLine], languages: SpeakerLanguages) -> [CaptionLine] {
        lines.filter { isShown($0, languages: languages) }
    }

    private func isSettled(_ line: CaptionLine) -> Bool { settledHalf[line.id] != nil || settledAsSaid.contains(line.id) }

    private static func sameLanguage(_ a: Locale) -> (Locale) -> Bool {
        { b in (a.language.languageCode?.identifier ?? a.identifier) == (b.language.languageCode?.identifier ?? b.identifier) }
    }
}

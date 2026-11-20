import Foundation

/// #213: whose words a Mac caption is. On a call the Mac hears two streams, the call's sound (the process tap, #172)
/// and its microphone, so it knows which captions are the other people's without guessing from voices.
public enum MacAudioSide: Equatable, Hashable, Sendable {
    /// The microphone with no call: the people near the Mac.
    case room
    /// The call's sound: the other people on the call (or anything else the Mac plays).
    case theirs
    /// A headset's mic during a call: only her own voice.
    case yours

    /// Which stream the sound came in on.
    public enum Source: Equatable, Sendable { case call, microphone }

    /// `mic`: which microphone joins the call (`RoomMicChoice`). Owner's note on PR #231: without headphones the Mac's
    /// own mic hears the people beside her as well as her, so on a call it is still the room's. Only a headset's mic is
    /// hers alone.
    public init(source: Source, onCall: Bool, mic: RoomMicChoice) {
        switch source {
        case .call: self = .theirs
        case .microphone: self = onCall && mic == .headset ? .yours : .room
        }
    }

    /// Her lines are labelled "You" (owner, PR #231): only when they can't be anyone else's.
    public var isYou: Bool { self == .yours }
}

/// #213: what the Mac translates, from which language, into which. Pure: the app's translator (Apple's Translation,
/// #159, the same path as the iPhone) does the work, one session per `Pair`, and `CaptionTranslations` keeps the
/// bookkeeping per session. Owner's decisions on #213: on a call only the other people's words are translated, and
/// the same purchase translates the room. Apple's speech engine can't detect a language (E27), so the room and the
/// call each have their own From language.
public struct MacTranslation: Equatable, Sendable {
    /// A translator's two languages.
    public struct Pair: Equatable, Hashable, Sendable {
        public let from: Locale
        public let into: Locale
        public init(from: Locale, into: Locale) {
            self.from = from
            self.into = into
        }
    }

    /// What people near the Mac speak (the room's From).
    public var room: Locale
    /// What the other people on calls speak (the call's From).
    public var call: Locale
    /// What she reads: every translation goes into it.
    public var into: Locale

    /// Languages captioned by an engine that hears every one of them (Parakeet: it takes no language setting, ADR 0029),
    /// so a side in one of them can be translated from another of them, line by line. Apple's engine hears only the
    /// language it was started in (E27).
    public var multilingual: Set<String>

    public init(room: Locale, call: Locale, into: Locale, multilingual: Set<String> = CaptionEngineRouting.parakeetLanguages) {
        self.room = room
        self.call = call
        self.into = into
        self.multilingual = multilingual
    }

    /// The saved choices: the call's language follows the room's until one is picked for it.
    public init(store: CaptionLanguageStore, room: Locale, into: Locale) {
        self.init(room: room, call: store.callLanguage ?? room, into: into)
    }

    /// The translator for a side's captions, or nil when they aren't translated: her own words (owner, #213), or a
    /// side that already speaks her language.
    public func pair(for side: MacAudioSide) -> Pair? {
        let from: Locale
        switch side {
        case .yours: return nil
        case .room: from = room
        case .theirs: from = call
        }
        return Self.sameLanguage(from, into) ? nil : Pair(from: from, into: into)
    }

    /// The languages a side's lines can be in, its own From first: the languages set up for this conversation (Room,
    /// Calls, Into) that its engine hears. Nothing else, so nothing new is ever downloaded mid-call (owner's rule).
    /// Her own lines: none.
    public func languages(for side: MacAudioSide) -> [Locale] {
        let own: Locale
        switch side {
        case .yours: return []
        case .room: own = room
        case .theirs: own = call
        }
        var heard = [own]
        if hearsSeveral(own) {
            for l in [room, call] where hearsSeveral(l) { heard.append(l) }
        }
        heard.append(into)
        var out: [Locale] = []
        for l in heard where !out.contains(where: { Self.sameLanguage($0, l) }) { out.append(l) }
        return out
    }

    /// Every translator needed, each once: room first, then the call.
    public var pairs: [Pair] {
        var seen: [Pair] = []
        for side in [MacAudioSide.room, .theirs] {
            for from in languages(for: side) where !Self.sameLanguage(from, into) {
                let p = Pair(from: from, into: into)
                if !seen.contains(where: { Self.samePair($0, p) }) { seen.append(p) }
            }
        }
        return seen
    }

    func hearsSeveral(_ locale: Locale) -> Bool {
        locale.language.languageCode.map { multilingual.contains($0.identifier) } ?? false
    }

    /// Same language for translation: the language and its script (Traditional and Simplified Chinese differ), not
    /// the region (US and UK English don't).
    static func sameLanguage(_ a: Locale, _ b: Locale) -> Bool {
        let x = Locale.Language(identifier: a.identifier(.bcp47)), y = Locale.Language(identifier: b.identifier(.bcp47))
        return x.languageCode == y.languageCode && x.maximalIdentifierScript == y.maximalIdentifierScript
    }

    static func samePair(_ a: Pair, _ b: Pair) -> Bool {
        sameLanguage(a.from, b.from) && sameLanguage(a.into, b.into)
    }
}

private extension Locale.Language {
    /// The script, filled in from the language and region when the identifier leaves it out (zh-TW → Hant).
    var maximalIdentifierScript: Locale.Script? { Locale.Language(identifier: maximalIdentifier).script }
}

public extension CaptionLanguageStore {
    static let callLanguageKey = "callLanguage"

    /// #213: what the other people on calls speak, on the Mac. Nil until picked: the call follows the room's language.
    var callLanguage: Locale? {
        get { defaults.string(forKey: Self.callLanguageKey).map(Locale.init(identifier:)) }
        nonmutating set { defaults.set(newValue.map(CaptionLanguage.bcp47), forKey: Self.callLanguageKey) }
    }
}

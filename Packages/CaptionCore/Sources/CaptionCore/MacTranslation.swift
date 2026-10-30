import Foundation

/// #213: whose words a Mac caption is. On a call the Mac hears two streams, the call's sound (the process tap, #172)
/// and its microphone, so it knows which captions are the other people's without guessing from voices.
public enum MacAudioSide: Equatable, Hashable, Sendable {
    /// The microphone with no call: the people near the Mac.
    case room
    /// The call's sound: the other people on the call (or anything else the Mac plays).
    case theirs
    /// The microphone during a call: her own voice.
    case yours

    /// Which stream the sound came in on.
    public enum Source: Equatable, Sendable { case call, microphone }

    public init(source: Source, onCall: Bool) {
        switch source {
        case .call: self = .theirs
        case .microphone: self = onCall ? .yours : .room
        }
    }
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

    public init(room: Locale, call: Locale, into: Locale) {
        self.room = room
        self.call = call
        self.into = into
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

    /// Every translator needed, each once: room first, then the call.
    public var pairs: [Pair] {
        var seen: [Pair] = []
        for side in [MacAudioSide.room, .theirs] {
            if let p = pair(for: side), !seen.contains(where: { Self.samePair($0, p) }) { seen.append(p) }
        }
        return seen
    }

    /// The lines a pair's translator takes, in order. A line whose side isn't known is left alone: better untranslated
    /// than her own words translated by mistake.
    public func lines(_ lines: [CaptionLine], for pair: Pair, side: (CaptionLine) -> MacAudioSide?) -> [CaptionLine] {
        lines.filter { line in
            guard let s = side(line), let p = self.pair(for: s) else { return false }
            return Self.samePair(p, pair)
        }
    }

    /// Same language for translation: the language and its script (Traditional and Simplified Chinese differ), not
    /// the region (US and UK English don't).
    static func sameLanguage(_ a: Locale, _ b: Locale) -> Bool {
        let x = Locale.Language(identifier: a.identifier(.bcp47)), y = Locale.Language(identifier: b.identifier(.bcp47))
        return x.languageCode == y.languageCode && x.maximalIdentifierScript == y.maximalIdentifierScript
    }

    private static func samePair(_ a: Pair, _ b: Pair) -> Bool {
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

import Foundation

/// The language captions are made in (#37) and the one they're translated into (#53). Pure: the device's preferred
/// languages and the engine's supported list are passed in, so every rule is tested without a device.
public enum CaptionLanguage {
    public enum Choice: Equatable, Sendable {
        /// Use this language without asking.
        case use(Locale)
        /// First run asks. `suggested` are the regions of the device language when there are several, else empty.
        case ask(suggested: [Locale])
    }

    /// The default caption language. The device's languages are tried in the person's order: an exact match is used;
    /// the one region the engine has of that language is used; several regions and no exact match means ask. A
    /// language the engine doesn't have moves on to the person's next language. Scripts count as different languages
    /// (Traditional Chinese never silently becomes Simplified).
    public static func defaultChoice(preferred: [String], supported: [Locale]) -> Choice {
        let supported = supported.sorted { bcp47($0) < bcp47($1) }
        for id in preferred {
            let wanted = Locale(identifier: id)
            if let exact = supported.first(where: { sameLanguage($0, wanted) && $0.region == wanted.region && wanted.region != nil }) {
                return .use(exact)
            }
            let matches = supported.filter { sameLanguage($0, wanted) }
            if matches.count == 1 { return .use(matches[0]) }
            if matches.count > 1 { return .ask(suggested: matches) }
        }
        return .ask(suggested: [])
    }

    /// Where translation goes by default: the first of the person's languages that isn't the caption language. Nil
    /// when they read only the caption language, so there's nothing to translate into until they pick one.
    public static func translationTarget(captions: Locale, preferred: [String]) -> Locale? {
        preferred.lazy.map { Locale(identifier: Locale(identifier: $0).identifier(.bcp47)) }
            .first { !sameLanguage($0, captions) }
    }

    /// Same language and script; the region may differ.
    static func sameLanguage(_ a: Locale, _ b: Locale) -> Bool {
        a.language.languageCode == b.language.languageCode && script(a) == script(b)
    }

    private static func script(_ l: Locale) -> String? {
        Locale.Language(identifier: l.language.maximalIdentifier).script?.identifier
    }

    static func bcp47(_ l: Locale) -> String { l.identifier(.bcp47) }
}

/// The list behind "Caption language" and translation's "From" (#37, #53): the language people around her speak.
/// Apple's speech engine is told one language before it starts and doesn't detect it, so this is chosen, never guessed.
/// Pure: the engine's lists are passed in.
public enum CaptionLanguageList {
    public enum Translation: Equatable, Sendable {
        /// Translation is off or not bought: the list says nothing about it.
        case off
        /// Translates into her language.
        case translates
        /// Captioned, but Apple's Translation doesn't have it (Cantonese, 2026-10-28): said plainly, not hidden (#53).
        case captionsOnly
        /// Her own language: nothing to translate.
        case yourLanguage

        /// Where it sits in the list: what translates first, then captions-only, then her own language.
        public var listGroup: Int {
            switch self {
            case .off, .translates: 0
            case .captionsOnly: 1
            case .yourLanguage: 2
            }
        }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public let locale: Locale
        public let isCurrent: Bool
        /// The speech model is on the device: no download.
        public let onDevice: Bool
        public let translation: Translation
        /// False only for a chosen language the engine no longer lists, kept so she can see what's set.
        public let supported: Bool
        public var id: String { CaptionLanguage.bcp47(locale) }
    }

    /// The chosen language first, then every language the engine has, in a fixed order, grouped by `listGroup`.
    /// `translation`: where captions are translated into and the languages Translation has; nil when it's off.
    public static func rows(speech: [Locale], installed: [Locale], current: Locale,
                            translation: (into: Locale, supported: [Locale.Language])?) -> [Row] {
        let key = CaptionLanguage.bcp47
        let installedIDs = Set(installed.map(key))
        func row(_ locale: Locale, supported: Bool) -> Row {
            let t: Translation
            if let translation {
                if CaptionLanguage.sameLanguage(locale, translation.into) { t = .yourLanguage }
                else if translation.supported.contains(where: { CaptionLanguage.sameLanguage(locale, Locale(identifier: $0.maximalIdentifier)) }) { t = .translates }
                else { t = .captionsOnly }
            } else { t = .off }
            return Row(locale: locale, isCurrent: key(locale) == key(current), onDevice: installedIDs.contains(key(locale)),
                       translation: t, supported: supported)
        }
        var seen = Set<String>()
        let others = speech.filter { seen.insert(key($0)).inserted && key($0) != key(current) }.sorted { key($0) < key($1) }
        let currentSupported = speech.contains { key($0) == key(current) }
        let rest = others.map { row($0, supported: true) }.enumerated()
            .sorted { ($0.element.translation.listGroup, $0.offset) < ($1.element.translation.listGroup, $1.offset) }.map(\.element)
        return [row(current, supported: currentSupported)] + rest
    }
}

/// The caption language and translation choices, saved like the other settings. No stored caption language means
/// "follow the device".
public struct CaptionLanguageStore {
    public static let captionKey = "captionLanguage"
    public static let translationOnKey = "translationOn"
    public static let translationTargetKey = "translationTarget"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var captionLanguage: Locale? {
        get { defaults.string(forKey: Self.captionKey).map(Locale.init(identifier:)) }
        nonmutating set { defaults.set(newValue.map(CaptionLanguage.bcp47), forKey: Self.captionKey) }
    }

    public var translationOn: Bool {
        get { defaults.bool(forKey: Self.translationOnKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.translationOnKey) }
    }

    public var translationTarget: Locale? {
        get { defaults.string(forKey: Self.translationTargetKey).map(Locale.init(identifier:)) }
        nonmutating set { defaults.set(newValue.map(CaptionLanguage.bcp47), forKey: Self.translationTargetKey) }
    }
}

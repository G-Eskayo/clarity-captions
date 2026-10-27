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
            let sameLanguage = supported.filter { sameLanguage($0, wanted) }
            if sameLanguage.count == 1 { return .use(sameLanguage[0]) }
            if sameLanguage.count > 1 { return .ask(suggested: sameLanguage) }
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

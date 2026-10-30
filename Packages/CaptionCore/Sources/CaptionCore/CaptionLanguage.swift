import Foundation

/// The language captions are made in (#37) and the one they're translated into (#53). Pure: the device's preferred
/// languages and the engine's supported list are passed in, so every rule is tested without a device.
public enum CaptionLanguage {
    public enum Choice: Equatable, Sendable {
        /// Use this language without asking.
        case use(Locale)
        /// First run asks. `suggested` are the regions of the device language when there are several, else empty.
        case ask(suggested: [Locale])

        /// The language to use, when there's no need to ask.
        public var locale: Locale? { if case .use(let l) = self { l } else { nil } }
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

    /// The caption language to use now: the one she chose, while the engine still has it (or while its list hasn't
    /// come back), else the device's default.
    public static func resolve(saved: Locale?, preferred: [String], supported: [Locale]) -> Choice {
        if let saved {
            if supported.isEmpty { return .use(saved) }
            if let match = supported.first(where: { bcp47($0) == bcp47(saved) }) { return .use(match) }
        }
        return defaultChoice(preferred: preferred, supported: supported)
    }

    /// Where translation goes by default: the first of the person's languages that isn't the caption language. Nil
    /// when they read only the caption language, so there's nothing to translate into until they pick one.
    public static func translationTarget(captions: Locale, preferred: [String]) -> Locale? {
        preferred.lazy.map { Locale(identifier: Locale(identifier: $0).identifier(.bcp47)) }
            .first { !sameLanguage($0, captions) }
    }

    /// The same language on both sides, which the owner allows (#252): Apple's Translation has no pair for it, so the
    /// words pass through as they are. Regions read the same; scripts don't (Simplified into Traditional is real work).
    public static func needsNoTranslation(from: Locale.Language, into: Locale.Language) -> Bool {
        sameLanguage(Locale(identifier: from.maximalIdentifier), Locale(identifier: into.maximalIdentifier))
    }

    /// Same language and script; the region may differ.
    static func sameLanguage(_ a: Locale, _ b: Locale) -> Bool {
        a.language.languageCode == b.language.languageCode && script(a) == script(b)
    }

    private static func script(_ l: Locale) -> String? {
        Locale.Language(identifier: l.language.maximalIdentifier).script?.identifier
    }

    public static func bcp47(_ l: Locale) -> String { l.identifier(.bcp47) }
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

/// Switching the caption language (#37). Captions keep the old language until the new one's speech files are on the
/// device; a failed download changes nothing and says why; only the newest choice counts.
public struct CaptionLanguageSwitch: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case ready
        case downloading(Locale, progress: Double)
        case failed(Locale, DownloadProblem)
    }

    public private(set) var current: Locale
    public private(set) var phase: Phase = .ready

    public init(current: Locale) { self.current = current }

    private var wanted: Locale? {
        switch phase {
        case .ready: nil
        case .downloading(let l, _), .failed(let l, _): l
        }
    }

    private static func same(_ a: Locale, _ b: Locale) -> Bool { CaptionLanguage.bcp47(a) == CaptionLanguage.bcp47(b) }

    /// Returns the language to download, or nil when there's nothing to download.
    public mutating func choose(_ locale: Locale, installed: Bool) -> Locale? {
        if Self.same(locale, current) { phase = .ready; return nil }
        if installed { current = locale; phase = .ready; return nil }
        phase = .downloading(locale, progress: 0)
        return locale
    }

    /// What translation's From row names (#252): the language just picked, with its download's progress, from the
    /// moment it's picked; else the one captions are really in. A failed pick shows the language still in use.
    public struct Shown: Equatable, Sendable {
        public let locale: Locale
        /// 0...1 while it downloads; nil when it's on the device.
        public let downloading: Double?
        public init(locale: Locale, downloading: Double?) { self.locale = locale; self.downloading = downloading }

        public init(current: Locale, phase: Phase) {
            if case .downloading(let l, let p) = phase { self.init(locale: l, downloading: p) }
            else { self.init(locale: current, downloading: nil) }
        }
    }

    public var shown: Shown { Shown(current: current, phase: phase) }

    public mutating func progress(_ p: Double, for locale: Locale) {
        guard case .downloading(let l, let shown) = phase, Self.same(l, locale) else { return }
        phase = .downloading(l, progress: max(shown, min(p, 1)))
    }

    public mutating func finished(_ outcome: DownloadOutcome, for locale: Locale) {
        guard let wanted, Self.same(wanted, locale), case .downloading = phase else { return }
        switch outcome {
        case .installed: current = wanted; phase = .ready
        case .failed(let why): phase = .failed(wanted, why)
        case .alreadyRunning: break
        }
    }
}

/// The Into list (#53): every language Apple's Translation has, each once, the current one first. The one being
/// captioned is listed too: the same language on both sides is allowed (owner, #252). Scripts stay apart (Simplified
/// and Traditional Chinese are two rows).
public enum TranslationTargetList {
    public struct Row: Equatable, Sendable, Identifiable {
        public let locale: Locale
        public let isCurrent: Bool
        public var id: String { CaptionLanguage.bcp47(locale) }
    }

    public static func rows(supported: [Locale.Language], from captions: Locale, current: Locale?) -> [Row] {
        var seen = Set<String>()
        // Named the way a person reads them: the script only where it tells two apart (Chinese).
        let locales = supported.map { lang -> Locale in
            let full = Locale.Language(identifier: lang.maximalIdentifier)
            let code = full.languageCode?.identifier ?? lang.maximalIdentifier
            let parts = [code, code == "zh" ? full.script?.identifier : nil, full.region?.identifier].compactMap { $0 }
            return Locale(identifier: parts.joined(separator: "-"))
        }
            .filter { seen.insert(CaptionLanguage.bcp47($0)).inserted }
            .sorted { CaptionLanguage.bcp47($0) < CaptionLanguage.bcp47($1) }
        let isCurrent = { (l: Locale) in current.map { CaptionLanguage.sameLanguage($0, l) && ($0.region == nil || $0.region == l.region) } ?? false }
        var rows = locales.map { Row(locale: $0, isCurrent: isCurrent($0)) }
        // One tick: the closest match to the current target.
        if let i = rows.firstIndex(where: \.isCurrent) {
            let first = rows.remove(at: i)
            rows = [first] + rows.map { Row(locale: $0.locale, isCurrent: false) }
        }
        return rows
    }
}

/// Swapping translation's From and Into (#252). From is captioned, so it must be a language the speech engine has; Into
/// may be any language Translation has. Into becomes From in the speech engine's own name for it (its region if the
/// engine has it, else the one she uses, else the first in a fixed order; scripts never cross), and From becomes Into
/// as it is. Into changes at once; From may need its download first, and if that fails, Into goes back.
public struct LanguageSwap: Equatable, Sendable {
    /// The new From (the caption language) and Into.
    public let from: Locale
    public let into: Locale
    /// Into before the swap, for a From download that fails.
    public let previousInto: Locale

    /// Nil when there's nothing to swap: Into isn't chosen, the engine's list hasn't come back, or the engine can't
    /// caption the Into language.
    public static func plan(from: Locale, into: Locale?, speech: [Locale], preferred: [String]) -> LanguageSwap? {
        guard let into else { return nil }
        let key = CaptionLanguage.bcp47
        let candidates = speech.filter { CaptionLanguage.sameLanguage($0, into) }.sorted { key($0) < key($1) }
        let hinted = preferred.map(Locale.init(identifier:)).filter { CaptionLanguage.sameLanguage($0, into) }.compactMap(\.region)
        let regions = (into.region.map { [$0] } ?? []) + hinted
        let pick = regions.lazy.compactMap { r in candidates.first { $0.region == r } }.first ?? candidates.first
        guard let pick else { return nil }
        return LanguageSwap(from: pick, into: from, previousInto: into)
    }

    /// Into once the caption language has moved on: the swap's, unless the swap's own download failed and captions
    /// are still in the old language. A newer pick of From keeps the swapped Into.
    public func into(after change: CaptionLanguageSwitch) -> Locale {
        let key = CaptionLanguage.bcp47
        if case .failed(let l, _) = change.phase, key(l) == key(from), key(change.current) != key(from) { return previousInto }
        return into
    }
}
